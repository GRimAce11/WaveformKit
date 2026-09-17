import Foundation

/// Persists `WaveformSummary` instances on disk so repeat opens of the same file are instant.
///
/// Cache key = file name + size + mtime + targetBars + format version.
/// We deliberately avoid hashing file contents — `fingerprint` is cheap and stable enough
/// for local audio that's not being rewritten in place.
///
/// ## Eviction
///
/// The cache is bounded by a byte budget (see `configuration`) and evicts least-recently-used
/// entries once the directory exceeds it.  "Recently used" means last read *or* written: a cache
/// hit stamps the entry so that frequently-opened files outlive one-off imports.  Eviction runs
/// automatically after every `save`, and can be triggered directly via `evictIfNeeded()`.
public enum WaveformCache {
    private static let formatVersion = 1
    private static let fileExtension = "wfm"

    // MARK: - Configuration

    /// Disk budget for cached summaries.
    public struct Configuration: Sendable, Equatable {

        /// Maximum total size, in bytes, of the cache directory.  Once a `save` pushes the
        /// directory past this, least-recently-used entries are deleted until it fits again.
        public var maximumBytes: Int

        public init(maximumBytes: Int = Configuration.defaultMaximumBytes) {
            self.maximumBytes = max(0, maximumBytes)
        }

        /// 32 MB — on the order of 10 000 summaries at the default 200 bars.
        public static let defaultMaximumBytes = 32 * 1024 * 1024

        public static let `default` = Configuration()

        /// Never evict.  This is the pre-0.6.0 behaviour; the cache grows until `clear()`.
        public static let unbounded = Configuration(maximumBytes: .max)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _configuration = Configuration.default

    /// Disk budget for the cache.  Assigning a smaller budget evicts immediately rather than
    /// waiting for the next save, so a "reduce cache size" setting takes effect at once.
    public static var configuration: Configuration {
        get { lock.withLock { _configuration } }
        set {
            lock.withLock { _configuration = newValue }
            evictIfNeeded()
        }
    }

    // MARK: - Paths

    /// Redirects the cache to another directory.
    ///
    /// Test-only seam so the suite can exercise real eviction against a temporary directory
    /// instead of the developer's actual Caches folder.  Production code leaves this `nil`.
    nonisolated(unsafe) static var directoryOverride: URL?

    private static var directory: URL? {
        if let directoryOverride {
            if !FileManager.default.fileExists(atPath: directoryOverride.path) {
                try? FileManager.default.createDirectory(
                    at: directoryOverride, withIntermediateDirectories: true
                )
            }
            return directoryOverride
        }
        let fm = FileManager.default
        guard let base = try? fm.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let dir = base.appendingPathComponent("WaveformKit", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func fingerprint(for url: URL, targetBars: Int) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        let size = (attrs[.size] as? Int) ?? 0
        let mtime = Int((attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)
        return "v\(formatVersion)-\(url.lastPathComponent)-\(size)-\(mtime)-b\(targetBars)"
    }

    private static func fileURL(for key: String) -> URL? {
        directory?.appendingPathComponent(key + "." + fileExtension)
    }

    // MARK: - Read / write

    public static func load(url: URL, targetBars: Int) -> WaveformSummary? {
        guard let key = fingerprint(for: url, targetBars: targetBars),
              let fileURL = fileURL(for: key),
              let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let summary = try? JSONDecoder().decode(WaveformSummary.self, from: data) else {
            return nil
        }
        // Stamp the entry as used so eviction is driven by access, not just by write.
        touch(fileURL)
        return summary
    }

    public static func save(_ summary: WaveformSummary, url: URL, targetBars: Int) {
        guard let key = fingerprint(for: url, targetBars: targetBars),
              let fileURL = fileURL(for: key),
              let data = try? JSONEncoder().encode(summary) else { return }
        try? data.write(to: fileURL, options: .atomic)
        evictIfNeeded()
    }

    /// Remove the cache entry for a specific URL/bar count.
    public static func remove(url: URL, targetBars: Int) {
        guard let key = fingerprint(for: url, targetBars: targetBars),
              let fileURL = fileURL(for: key) else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Nuke all cached summaries.
    public static func clear() {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Eviction

    /// Total size of the cache directory in bytes.  Useful for a "Clear cache (12.4 MB)" row
    /// in a settings screen.
    public static var currentByteSize: Int {
        entries().reduce(0) { $0 + $1.size }
    }

    /// Delete least-recently-used entries until the cache fits `configuration.maximumBytes`.
    ///
    /// Runs automatically after each `save`.  Call it directly after bulk-importing summaries
    /// through some other path, or to reclaim space on demand.
    @discardableResult
    public static func evictIfNeeded() -> Int {
        let budget = configuration.maximumBytes
        guard budget < .max else { return 0 }

        var items = entries()
        var total = items.reduce(0) { $0 + $1.size }
        guard total > budget else { return 0 }

        // Oldest access first; delete until we are back inside the budget.
        items.sort { $0.lastUsed < $1.lastUsed }
        var evicted = 0
        for item in items {
            guard total > budget else { break }
            guard (try? FileManager.default.removeItem(at: item.url)) != nil else { continue }
            total -= item.size
            evicted += 1
        }
        return evicted
    }

    private struct Entry {
        var url: URL
        var size: Int
        var lastUsed: Date
    }

    private static func entries() -> [Entry] {
        guard let directory else { return [] }
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents.compactMap { url in
            guard url.pathExtension == fileExtension else { return nil }
            let values = try? url.resourceValues(forKeys: Set(keys))
            return Entry(
                url: url,
                size: values?.fileSize ?? 0,
                lastUsed: values?.contentModificationDate ?? .distantPast
            )
        }
    }

    /// Update an entry's modification date so it reads as the most recently used.
    private static func touch(_ fileURL: URL) {
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: fileURL.path
        )
    }
}

// WaveformLoader (instance + static API) has moved to WaveformLoader.swift.
// The static WaveformLoader.load(url:targetBars:useCache:) convenience method
// is preserved there with the same signature for source compatibility.
