import Foundation

public enum AudioSource: Sendable {
    case file(URL)
    case precomputed(WaveformSummary)
}
