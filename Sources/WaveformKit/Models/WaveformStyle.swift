import Foundation

public enum WaveformStyle: Sendable, Equatable {
    /// Vertical bars rising from the bottom. Classic SoundCloud / podcast seeker.
    case bars(count: Int = 100, spacing: CGFloat = 2, cornerRadius: CGFloat = 1.5)
    /// Bars centered on the midline — WhatsApp / iMessage voice-note look.
    case mirroredBars(count: Int = 100, spacing: CGFloat = 2, cornerRadius: CGFloat = 1.5)
}

public enum WaveformMovement: Sendable, Equatable {
    /// Static waveform; played portion is colored differently.
    case progress
}
