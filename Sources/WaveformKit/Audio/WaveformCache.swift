import Foundation

/// Persists `WaveformSummary` instances on disk so repeat opens of the same file are instant.
///
/// Cache key = file name + size + mtime + targetBars + format version.
/// We deliberately avoid hashing file contents — `fingerprint` is cheap and stable enough
/// for local audio that's not being rewritten in place.
public enum WaveformCache {
    private static let formatVersion = 1

    private static var directory: URL? {
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
        directory?.appendingPathComponent(key + ".wfm")
    }

    public static func load(url: URL, targetBars: Int) -> WaveformSummary? {
        guard let key = fingerprint(for: url, targetBars: targetBars),
              let fileURL = fileURL(for: key),
              let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(WaveformSummary.self, from: data)
    }

    public static func save(_ summary: WaveformSummary, url: URL, targetBars: Int) {
        guard let key = fingerprint(for: url, targetBars: targetBars),
              let fileURL = fileURL(for: key),
              let data = try? JSONEncoder().encode(summary) else { return }
        try? data.write(to: fileURL, options: .atomic)
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
}

// WaveformLoader (instance + static API) has moved to WaveformLoader.swift.
// The static WaveformLoader.load(url:targetBars:useCache:) convenience method
// is preserved there with the same signature for source compatibility.
