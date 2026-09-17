import Foundation
import Accelerate

// MARK: - ResampleCache

/// Cache for resampled amplitude arrays, keyed by (summaryID, targetCount, visibleSlice).
///
/// `WaveformView` holds one `ResampleCache` instance per view identity via `@State`.
/// Under reactive or dancing-bars movement the view body runs at 30–60 Hz; without caching
/// `resampled(to:)` would allocate a new `[Float]` every frame even though the source
/// amplitudes haven't changed.
///
/// ## Ownership
/// Accessed only on the main thread (inside SwiftUI's view body evaluation).
/// Not thread-safe; no lock required.
///
/// ## Eviction
/// Two-level.  All entries are dropped the moment a summary with a different `id` is seen, and
/// within a single summary the cache is a fixed-capacity LRU.  The LRU bound matters as soon as
/// zoom gestures are live: a pinch mints a new `(startIdx, endIdx)` slice on every frame, so a
/// cache keyed on the slice and evicted only on summary change would grow without limit for as
/// long as the user keeps zooming.
final class ResampleCache {

    /// Entries retained per summary.  Sixteen covers a multi-style view plus a gesture's worth of
    /// in-flight zoom levels; at 200 bars that is roughly 13 KB.
    static let defaultCapacity = 16

    struct Key: Hashable {
        var summaryID: UUID
        var count: Int
        var startIdx: Int
        var endIdx: Int
    }

    private struct Entry {
        var value: [Float]
        /// Logical timestamp of the last `get`/`set`.  Compared only against other entries, so
        /// wrap-around after 2^64 accesses is not a concern.
        var lastUsed: UInt64
    }

    private var store: [Key: Entry] = [:]
    private var activeSummaryID: UUID?
    private var clock: UInt64 = 0
    private let capacity: Int

    init(capacity: Int = ResampleCache.defaultCapacity) {
        self.capacity = max(1, capacity)
    }

    func get(summaryID: UUID, count: Int, startIdx: Int, endIdx: Int) -> [Float]? {
        let key = Key(summaryID: summaryID, count: count, startIdx: startIdx, endIdx: endIdx)
        guard let entry = store[key] else { return nil }
        clock &+= 1
        store[key]?.lastUsed = clock
        return entry.value
    }

    func set(_ result: [Float], summaryID: UUID, count: Int, startIdx: Int, endIdx: Int) {
        // Evict stale entries the moment a new summary arrives.
        if summaryID != activeSummaryID {
            store.removeAll(keepingCapacity: true)
            activeSummaryID = summaryID
        }
        clock &+= 1
        store[Key(summaryID: summaryID, count: count, startIdx: startIdx, endIdx: endIdx)] =
            Entry(value: result, lastUsed: clock)
        evictIfNeeded()
    }

    /// Number of live entries.  Exposed for tests.
    var count: Int { store.count }

    private func evictIfNeeded() {
        // `capacity` is small, so a linear scan for the oldest entry is cheaper than maintaining
        // the intrusive linked list a general-purpose LRU would use.
        while store.count > capacity {
            guard let oldest = store.min(by: { $0.value.lastUsed < $1.value.lastUsed })?.key else { return }
            store.removeValue(forKey: oldest)
        }
    }
}

// MARK: - Vectorised resampler

/// Downsample `src[startIdx..<endIdx]` to `targetCount` bars using mean-over-bins pooling.
///
/// Each output bar is the arithmetic mean of the source bins it covers.  `vDSP_sve`
/// (vectorised sum) replaces the scalar `reduce(0, +)` loop from the original implementation,
/// giving a ~4–8× speedup on ARM NEON for the typical 100–400 bar range.
///
/// This is the **only** place in the render path that should allocate;  the result is
/// immediately stored in `ResampleCache` and reused until the summary changes.
func resampleAmplitudes(src: [Float], startIdx: Int, endIdx: Int, targetCount: Int) -> [Float] {
    let sliceCount = endIdx - startIdx
    guard sliceCount > 0, targetCount > 0 else { return [] }
    if sliceCount == targetCount { return Array(src[startIdx..<endIdx]) }

    var out = [Float]()
    out.reserveCapacity(targetCount)
    let stride = Double(sliceCount) / Double(targetCount)

    src.withUnsafeBufferPointer { buf in
        guard let base = buf.baseAddress else { return }
        for i in 0..<targetCount {
            let localStart = Int(Double(i) * stride)
            let localEnd   = max(localStart + 1, min(sliceCount, Int(Double(i + 1) * stride)))
            let binCount   = localEnd - localStart
            var sum: Float = 0
            vDSP_sve(base + startIdx + localStart, 1, &sum, vDSP_Length(binCount))
            out.append(sum / Float(binCount))
        }
    }
    return out
}
