import Foundation

@MainActor
public protocol AmplitudeTap: AnyObject {
    /// Smoothed whole-channel amplitude in 0...1 (attack/decay envelope applied).
    var currentAmplitude: Float { get }
    /// Per-band magnitudes 0...1 (log-spaced). Empty when the underlying player can't expose PCM
    /// (e.g. `AVAudioPlayer`), in which case fall back to `currentAmplitude` for visuals.
    var bands: [Float] { get }
}

/// Attack/decay envelope follower. Apply on the main thread at the polling rate.
struct AmplitudeEnvelope {
    var value: Float = 0
    var attackTime: Float = 0.04
    var decayTime: Float = 0.25

    mutating func step(target: Float, dt: Float) -> Float {
        let tau = target > value ? attackTime : decayTime
        let alpha = tau > 0 ? min(1, dt / tau) : 1
        value += (target - value) * alpha
        return value
    }
}
