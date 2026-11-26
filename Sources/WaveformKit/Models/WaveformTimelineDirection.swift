import SwiftUI

/// Which way time runs across a `WaveformView`.
///
/// Apple's Human Interface Guidelines ask apps to "flip controls that show progress from one
/// value to another" in right-to-left languages, as sliders and progress indicators do.  A
/// waveform seek bar is that kind of control, so by default it follows the layout direction:
/// in Arabic or Hebrew the audio starts at the right edge and plays towards the left.
///
/// Everything that maps time to position flips together — the bars, the playhead's played
/// colouring, seeking, panning, pinch anchoring, markers, the selection, and the positions of
/// VoiceOver elements.  Marker labels stay readable; they move, they do not mirror.
///
/// ```swift
/// // Keep time running left to right everywhere, e.g. in a DAW-style editor:
/// WaveformView(summary: s, currentTime: t)
///     .waveformTimelineDirection(.leftToRight)
/// ```
///
/// `.circular` always runs clockwise from the top.  The guidelines treat clock faces as the same
/// everywhere, and a progress ring reads as one.
public enum WaveformTimelineDirection: Sendable, Hashable, CaseIterable {
    /// Right to left when the layout direction is right to left.  The default.
    case automatic
    /// Always left to right.
    case leftToRight
    /// Always right to left.
    case rightToLeft

    /// Whether time runs right to left under `layoutDirection`.
    public func isRightToLeft(in layoutDirection: LayoutDirection) -> Bool {
        switch self {
        case .automatic:   return layoutDirection == .rightToLeft
        case .leftToRight: return false
        case .rightToLeft: return true
        }
    }
}

// MARK: - Environment

private struct WaveformTimelineDirectionKey: EnvironmentKey {
    static let defaultValue = WaveformTimelineDirection.automatic
}

extension EnvironmentValues {
    /// The direction time runs across `WaveformView`s in this environment.
    public var waveformTimelineDirection: WaveformTimelineDirection {
        get { self[WaveformTimelineDirectionKey.self] }
        set { self[WaveformTimelineDirectionKey.self] = newValue }
    }
}

extension View {
    /// Sets which way time runs across the `WaveformView`s inside this view.
    ///
    /// See `WaveformTimelineDirection`.  The default, `.automatic`, follows the layout
    /// direction.
    public func waveformTimelineDirection(_ direction: WaveformTimelineDirection) -> some View {
        environment(\.waveformTimelineDirection, direction)
    }
}
