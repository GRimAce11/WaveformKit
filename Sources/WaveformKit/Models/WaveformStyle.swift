import Foundation

public enum WaveformStyle: Sendable, Equatable {
    /// Vertical bars rising from the bottom. Classic SoundCloud / podcast seeker.
    case bars(count: Int = 100, spacing: CGFloat = 2, cornerRadius: CGFloat = 1.5)
    /// Bars centered on the midline — WhatsApp / iMessage voice-note look.
    case mirroredBars(count: Int = 100, spacing: CGFloat = 2, cornerRadius: CGFloat = 1.5)
    /// Equalizer-style bouncing bars driven by live amplitude.
    /// Each bar has a stable pseudo-random phase so the row "dances" instead of moving as one block.
    case dancingBars(count: Int = 32, spacing: CGFloat = 3, cornerRadius: CGFloat = 2)
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
