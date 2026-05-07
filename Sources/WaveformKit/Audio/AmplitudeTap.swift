import Foundation

@MainActor
public protocol AmplitudeTap: AnyObject {
    /// Smoothed amplitude in 0...1 (attack/decay envelope applied).
    var currentAmplitude: Float { get }
}

/// Attack/decay envelope follower. Apply on the main thread at the polling rate.
struct AmplitudeEnvelope {
    var value: Float = 0
    var attackTime: Float = 0.04   // seconds to reach a louder target
    var decayTime: Float = 0.25    // seconds to fall to a quieter target

    mutating func step(target: Float, dt: Float) -> Float {
        let tau = target > value ? attackTime : decayTime
        let alpha = tau > 0 ? min(1, dt / tau) : 1
        value += (target - value) * alpha
        return value
    }
}
