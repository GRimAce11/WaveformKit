import Foundation

public struct WaveformSummary: Sendable, Codable, Equatable {
    public let amplitudes: [Float]
    public let duration: TimeInterval
    public let sampleRate: Double
    public let channelCount: Int

    public init(
        amplitudes: [Float],
        duration: TimeInterval,
        sampleRate: Double,
        channelCount: Int
    ) {
        self.amplitudes = amplitudes
        self.duration = duration
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }

    public static let empty = WaveformSummary(
        amplitudes: [],
        duration: 0,
        sampleRate: 0,
        channelCount: 0
    )
}
