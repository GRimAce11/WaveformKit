import Foundation

/// Multi-resolution amplitude data that lets a zoomed-in `WaveformView` show real detail.
///
/// A `WaveformSummary`'s `amplitudes` array is decoded at a fixed, small resolution — 200 bins
/// by default.  That is plenty for a full-width seek bar, but zoom in 20× and the view has only
/// ten bins left to spread across its bars, so it stretches them into wide flat blocks.  A
/// pyramid carries a much finer base level (16 384 bins by default) plus a ladder of coarser
/// levels, each half the length of the one below.  At any zoom factor the view picks the
/// coarsest level that still has at least one bin per bar, so the work per frame stays
/// proportional to the number of bars on screen, not to the length of the file.
///
/// `AudioDecoder` and `WaveformLoader` build one automatically; `WaveformView` uses it whenever
/// the summary carries one.  You only touch this type directly when you produce summaries
/// yourself — on a server, say — and want them to zoom as well as decoded ones:
///
/// ```swift
/// let pyramid = WaveformSummaryPyramid(amplitudes: fineBins)   // any length, values in 0...1
/// let summary = WaveformSummary(
///     amplitudes: coarseBins, duration: d, sampleRate: 44_100, channelCount: 2,
///     pyramid: pyramid
/// )
/// ```
///
/// ## Precision and size
///
/// Values are clamped to `0...1` and stored at 16-bit precision (steps of 1/65 535 — far below
/// anything a display can show).  Quantising at construction rather than at encode time keeps a
/// `Codable` round trip exact.  Only the base level is encoded; the coarser levels are rebuilt
/// on decode, so the default resolution costs about 44 KB of JSON and about 190 KB in memory.
public struct WaveformSummaryPyramid: Sendable, Equatable {

    /// Base-level bin count `AudioDecoder` aims for unless told otherwise.
    ///
    /// Enough for the default `WaveformZoomOptions.maxZoomFactor` of 50 to keep roughly one bin
    /// per bar on a 300-bar view.
    public static let defaultResolution = 16_384

    /// Levels ordered finest first.  `peakLevels[0]` and `meanLevels[0]` are the same array
    /// (shared storage); each later level halves the previous one by max or by mean.
    private let peakLevels: [[Float]]
    private let meanLevels: [[Float]]

    /// Build a pyramid from its finest level.
    ///
    /// - Parameter amplitudes: Base-level bins in time order, normalised to `0...1`.  Values
    ///   outside that range are clamped and non-finite values read as silence.
    public init(amplitudes: [Float]) {
        let base = amplitudes.map(Self.quantise)
        var peaks: [[Float]] = [base]
        var means: [[Float]] = [base]
        while let lastPeak = peaks.last, let lastMean = means.last, lastPeak.count > 1 {
            peaks.append(Self.halve(lastPeak, by: { Swift.max($0, $1) }))
            means.append(Self.halve(lastMean, by: { ($0 + $1) / 2 }))
        }
        peakLevels = base.isEmpty ? [] : peaks
        meanLevels = base.isEmpty ? [] : means
    }

    // MARK: - Shape

    /// Number of bins in the finest level.
    public var resolution: Int { peakLevels.first?.count ?? 0 }

    /// Number of levels, counting the base.  A 16 384-bin base has 15.
    public var levelCount: Int { peakLevels.count }

    /// `true` when the pyramid holds no data.
    public var isEmpty: Bool { peakLevels.isEmpty }

    /// The finest level — the bins the pyramid was built from, after quantisation.
    public var baseAmplitudes: [Float] { peakLevels.first ?? [] }

    /// The bins of one level, pooled the way `mode` pools.
    ///
    /// Level 0 is the base; level `n` has `ceil(resolution / 2ⁿ)` bins.  Under `.peak` each bin
    /// is the loudest base bin it covers, under `.mean` the average — the same reductions
    /// `WaveformView` applies when it resamples, so picking a level never changes which mode
    /// you get.
    public func level(_ index: Int, mode: WaveformResampleMode = .peak) -> [Float] {
        let levels = mode == .peak ? peakLevels : meanLevels
        guard levels.indices.contains(index) else { return [] }
        return levels[index]
    }

    // MARK: - Rendering

    /// Amplitudes for `count` bars spanning `normalizedRange` of the file.
    ///
    /// - Parameters:
    ///   - normalizedRange: The visible portion of the file, as fractions of its duration —
    ///     `WaveformViewport.normalizedRange`.  `0...1` is the whole file.
    ///   - count: Bars to produce.
    ///   - mode: How bins are pooled into bars.
    public func amplitudes(
        in normalizedRange: ClosedRange<Double> = 0...1,
        count: Int,
        mode: WaveformResampleMode = .peak
    ) -> [Float] {
        guard let slice = slice(for: normalizedRange, count: count) else { return [] }
        return resampleAmplitudes(
            src: level(slice.level, mode: mode),
            startIdx: slice.start, endIdx: slice.end,
            targetCount: count, mode: mode
        )
    }

    /// Which level, and which bins of it, cover `normalizedRange` at `count` bars.
    struct Slice: Equatable {
        var level: Int
        var start: Int
        var end: Int
    }

    /// Picks the coarsest level that still has at least `count` bins inside the range, so a bar
    /// never stands for less than one bin (which would discard detail the pyramid holds) and the
    /// resampler never walks more than about two bins per bar.  When even the base level has
    /// fewer bins than bars, the base is used and the resampler repeats bins.
    func slice(for normalizedRange: ClosedRange<Double>, count: Int) -> Slice? {
        let total = resolution
        guard total > 0, count > 0 else { return nil }

        // Clamp before converting to Int: a stray 1e300 would otherwise trap.
        func clampedFraction(_ value: Double, fallback: Double) -> Double {
            value.isFinite ? min(1, max(0, value)) : fallback
        }
        let lowerFraction = clampedFraction(normalizedRange.lowerBound, fallback: 0)
        let upperFraction = clampedFraction(normalizedRange.upperBound, fallback: 1)
        let lo = min(total - 1, max(0, Int((lowerFraction * Double(total)).rounded(.down))))
        let hi = min(total, max(lo + 1, Int((upperFraction * Double(total)).rounded(.up))))
        let span = hi - lo

        var level = 0
        while level + 1 < levelCount, span >> (level + 1) >= count {
            level += 1
        }
        let binCount = peakLevels[level].count
        let start = lo >> level
        let end = min(binCount, max(start + 1, (hi + (1 << level) - 1) >> level))
        return Slice(level: level, start: start, end: end)
    }

    // MARK: - Building

    private static func quantise(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return Float(UInt16(min(1, max(0, value)) * Float(UInt16.max) + 0.5)) / Float(UInt16.max)
    }

    /// Pairs neighbouring bins.  An odd trailing bin carries up unpaired.
    private static func halve(_ src: [Float], by combine: (Float, Float) -> Float) -> [Float] {
        var out = [Float]()
        out.reserveCapacity((src.count + 1) / 2)
        var i = 0
        while i + 1 < src.count {
            out.append(combine(src[i], src[i + 1]))
            i += 2
        }
        if i < src.count { out.append(src[i]) }
        return out
    }

    // MARK: - Equatable

    /// Two pyramids are equal when their base levels are; every other level is derived.
    public static func == (lhs: WaveformSummaryPyramid, rhs: WaveformSummaryPyramid) -> Bool {
        lhs.baseAmplitudes == rhs.baseAmplitudes
    }
}

// MARK: - Codable

extension WaveformSummaryPyramid: Codable {

    private enum CodingKeys: String, CodingKey {
        /// Base level as little-endian `UInt16`s.  `JSONEncoder` writes `Data` as base64, which
        /// is about a fifth the size of the same bins written as JSON numbers.
        case base
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let data = try container.decode(Data.self, forKey: .base)
        guard data.count.isMultiple(of: 2) else {
            throw DecodingError.dataCorruptedError(
                forKey: .base, in: container,
                debugDescription: "Pyramid data must be a whole number of 16-bit values."
            )
        }
        let values: [Float] = data.withUnsafeBytes { raw in
            (0..<(data.count / 2)).map { i in
                let bits = raw.loadUnaligned(fromByteOffset: i * 2, as: UInt16.self)
                return Float(UInt16(littleEndian: bits)) / Float(UInt16.max)
            }
        }
        self.init(amplitudes: values)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let words = baseAmplitudes.map { UInt16($0 * Float(UInt16.max) + 0.5).littleEndian }
        let data = words.withUnsafeBufferPointer { Data(buffer: $0) }
        try container.encode(data, forKey: .base)
    }
}
