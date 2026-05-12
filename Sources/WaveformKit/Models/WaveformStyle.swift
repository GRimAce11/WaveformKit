import Foundation

public enum WaveformStyle: Sendable, Equatable {
    /// Vertical bars rising from the bottom. Classic SoundCloud / podcast seeker.
    case bars(count: Int = 100, spacing: CGFloat = 2, cornerRadius: CGFloat = 1.5)
    /// Bars centered on the midline — WhatsApp / iMessage voice-note look.
    case mirroredBars(count: Int = 100, spacing: CGFloat = 2, cornerRadius: CGFloat = 1.5)
    /// Equalizer-style bouncing bars driven by live amplitude (or FFT bands if the tap provides them).
    case dancingBars(count: Int = 32, spacing: CGFloat = 3, cornerRadius: CGFloat = 2)
    /// A smooth filled mirrored curve. Minimal/elegant.
    case line(thickness: CGFloat = 2)
    /// Discrete capsules along the midline — voice-note minimal style.
    case dots(count: Int = 60, dotSize: CGFloat = 4, spacing: CGFloat = 4)
    /// Bars arranged radially around a center point. View must be square for best results.
    case circular(count: Int = 64, innerRadiusFraction: CGFloat = 0.45, barWidth: CGFloat = 3)
}

public enum WaveformMovement: Sendable, Equatable {
    /// Static waveform; played portion is colored differently.
    case progress
    /// Bars/shapes scale by `1 + boost * amplitude`. No progress fill.
    case reactive(boost: CGFloat = 1.5)
    /// Progress fill + reactive amplitude scaling on the played portion.
    case combined(boost: CGFloat = 1.0)
    /// Subtle shimmer when no audio is playing.
    case idle
}

extension WaveformMovement {
    var reactiveBoost: CGFloat {
        switch self {
        case .reactive(let b): return b
        case .combined(let b): return b
        default: return 0
        }
    }

    var showsProgress: Bool {
        switch self {
        case .progress, .combined: return true
        default: return false
        }
    }
}
