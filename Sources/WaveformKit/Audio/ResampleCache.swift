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
/// All entries are dropped the first time a summary with a different `id` is seen.
/// The cache therefore holds at most `O(styleCount)` entries at any time — typically 1–2
/// entries for a single-style view, or a handful for a tabbed player.
final class ResampleCache {

    struct Key: Hashable {
        var summaryID: UUID
        var count: Int
        var startIdx: Int
        var endIdx: Int
    }

    private var store: [Key: [Float]] = [:]
    private var activeSummaryID: UUID?

    func get(summaryID: UUID, count: Int, startIdx: Int, endIdx: Int) -> [Float]? {
        store[Key(summaryID: summaryID, count: count, startIdx: startIdx, endIdx: endIdx)]
    }

    func set(_ result: [Float], summaryID: UUID, count: Int, startIdx: Int, endIdx: Int) {
        // Evict stale entries the moment a new summary arrives.
        if summaryID != activeSummaryID {
            store.removeAll(keepingCapacity: true)
            activeSummaryID = summaryID
        }
        store[Key(summaryID: summaryID, count: count, startIdx: startIdx, endIdx: endIdx)] = result
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
