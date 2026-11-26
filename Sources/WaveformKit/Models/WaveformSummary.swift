import Foundation

public struct WaveformSummary: Sendable, Codable, Equatable {
    public let amplitudes: [Float]
    public let duration: TimeInterval
    public let sampleRate: Double
    public let channelCount: Int

    /// Fine-grained amplitude levels for zoomed rendering, or `nil` when the summary has only
    /// its flat `amplitudes`.
    ///
    /// `AudioDecoder` builds one by default.  When present, `WaveformView` draws from it at every
    /// zoom level, so the bars keep gaining detail as you zoom in instead of stretching the
    /// 200-odd bins in `amplitudes`.  Summaries from `MicrophoneRecorder`, `demo(...)`, or older
    /// caches have none and render from `amplitudes` exactly as before.
    public let pyramid: WaveformSummaryPyramid?

    /// Opaque cache-keying token.  Two summaries with identical amplitude data compare equal
    /// via `==` regardless of their `id` — `id` is intentionally excluded from `Equatable`.
    /// Each `init(...)` call and each `init(from:)` decode produces a fresh `UUID` so that
    /// `ResampleCache` correctly invalidates when a new summary is assigned to a view.
    public let id: UUID

    public init(
        amplitudes: [Float],
        duration: TimeInterval,
        sampleRate: Double,
        channelCount: Int,
        pyramid: WaveformSummaryPyramid? = nil
    ) {
        self.amplitudes  = amplitudes
        self.duration    = duration
        self.sampleRate  = sampleRate
        self.channelCount = channelCount
        self.pyramid     = pyramid
        self.id          = UUID()
    }

    // MARK: - Equatable (id excluded)

    public static func == (lhs: WaveformSummary, rhs: WaveformSummary) -> Bool {
        lhs.amplitudes   == rhs.amplitudes  &&
        lhs.duration     == rhs.duration    &&
        lhs.sampleRate   == rhs.sampleRate  &&
        lhs.channelCount == rhs.channelCount &&
        lhs.pyramid      == rhs.pyramid
    }

    // MARK: - Codable (id excluded — fresh UUID on each decode)
    //
    // `pyramid` is optional on the wire, so JSON written before 0.7.0 — or by a server that only
    // sends flat amplitudes — still decodes.

    enum CodingKeys: String, CodingKey {
        case amplitudes, duration, sampleRate, channelCount, pyramid
    }

    public init(from decoder: Decoder) throws {
        let c         = try decoder.container(keyedBy: CodingKeys.self)
        amplitudes    = try c.decode([Float].self,       forKey: .amplitudes)
        duration      = try c.decode(TimeInterval.self,  forKey: .duration)
        sampleRate    = try c.decode(Double.self,        forKey: .sampleRate)
        channelCount  = try c.decode(Int.self,           forKey: .channelCount)
        pyramid       = try c.decodeIfPresent(WaveformSummaryPyramid.self, forKey: .pyramid)
        id            = UUID()   // each decoded instance gets a distinct cache-key identity
    }

    public static let empty = WaveformSummary(
        amplitudes: [],
        duration: 0,
        sampleRate: 0,
        channelCount: 0
    )

    /// Synthetic summary for previews, screenshots, and unit fixtures. Produces an envelope-shaped
    /// amplitude curve with a few peaks so all six styles look plausible.
    public static func demo(
        duration: TimeInterval = 30,
        bars: Int = 200,
        sampleRate: Double = 44100,
        seed: UInt64 = 42
    ) -> WaveformSummary {
        guard bars > 0 else { return .empty }
        var rng = seed
        func next() -> Float {
            rng = rng &* 2862933555777941757 &+ 3037000493
            return Float((rng >> 32) & 0xFFFFFFFF) / Float(UInt32.max)
        }
        var out: [Float] = []
        out.reserveCapacity(bars)
        for i in 0..<bars {
            let t = Float(i) / Float(max(1, bars - 1))
            let envelope: Float
            if t < 0.1 { envelope = t / 0.1 * 0.7 }
            else if t < 0.85 { envelope = 0.55 + 0.35 * sin(t * 6) }
            else { envelope = (1 - (t - 0.85) / 0.15) * 0.6 }
            let noise = 0.6 + 0.4 * next()
            out.append(max(0.04, min(0.98, envelope * noise)))
        }
        return WaveformSummary(
            amplitudes: out,
            duration: duration,
            sampleRate: sampleRate,
            channelCount: 1
        )
    }
}
