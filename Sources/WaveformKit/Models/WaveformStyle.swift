import Foundation

/// The visual style used to render a `WaveformView`.
///
/// The six built-in cases cover the most common audio-app patterns.  Use `.custom` to supply
/// your own `WaveformRenderer` for full drawing control without forking the library.
public enum WaveformStyle: Sendable {
    /// Vertical bars rising from the bottom. Classic SoundCloud / podcast seeker.
    case bars(count: Int = 100, spacing: CGFloat = 2, cornerRadius: CGFloat = 1.5)
    /// Bars centred on the midline — WhatsApp / iMessage voice-note look.
    case mirroredBars(count: Int = 100, spacing: CGFloat = 2, cornerRadius: CGFloat = 1.5)
    /// Equalizer-style bouncing bars driven by live amplitude (or FFT bands if available).
    case dancingBars(count: Int = 32, spacing: CGFloat = 3, cornerRadius: CGFloat = 2)
    /// A smooth filled mirrored curve. Minimal / elegant.
    case line(thickness: CGFloat = 2)
    /// Discrete capsules along the midline — voice-note minimal style.
    case dots(count: Int = 60, dotSize: CGFloat = 4, spacing: CGFloat = 4)
    /// Bars arranged radially around a centre point. View should be square.
    case circular(count: Int = 64, innerRadiusFraction: CGFloat = 0.45, barWidth: CGFloat = 3)
    /// Fully custom renderer.  `barCount` controls how many resampled amplitude values
    /// the renderer receives.  See `WaveformRenderer` for the drawing protocol.
    case custom(renderer: any WaveformRenderer, barCount: Int = 100)
}

// MARK: - Equatable
// Manual implementation required because `any WaveformRenderer` is not Equatable.
// Two `.custom` cases are never considered equal (renderers carry no comparable identity).

extension WaveformStyle: Equatable {
    public static func == (lhs: WaveformStyle, rhs: WaveformStyle) -> Bool {
        switch (lhs, rhs) {
        case let (.bars(c1, s1, r1),         .bars(c2, s2, r2)):         return c1==c2 && s1==s2 && r1==r2
        case let (.mirroredBars(c1, s1, r1), .mirroredBars(c2, s2, r2)): return c1==c2 && s1==s2 && r1==r2
        case let (.dancingBars(c1, s1, r1),  .dancingBars(c2, s2, r2)):  return c1==c2 && s1==s2 && r1==r2
        case let (.line(t1),                 .line(t2)):                  return t1==t2
        case let (.dots(c1, d1, s1),         .dots(c2, d2, s2)):         return c1==c2 && d1==d2 && s1==s2
        case let (.circular(c1, i1, b1),     .circular(c2, i2, b2)):     return c1==c2 && i1==i2 && b1==b2
        case (.custom, .custom):                                          return false
        default:                                                          return false
        }
    }
}

public enum WaveformMovement: Sendable, Equatable {
    /// Static waveform; played portion is colored differently.
    case progress
    /// Bars/shapes scale by `1 + boost * amplitude`. No progress fill.
    case reactive(boost: CGFloat = 1.5)
    /// Progress fill + reactive amplitude scaling on the played portion.
    case combined(boost: CGFloat = 1.0)
    /// Scanning shimmer (the played color sweeps left-to-right and back) for "loaded but not
    /// playing" or loading-skeleton states. Renders a placeholder waveform if `summary` is empty.
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
