import Foundation
import CoreGraphics

/// Controls the pinch-zoom, pan, and double-tap gestures on a `WaveformView`.
///
/// Gestures only become active when the view is also given a `viewport` binding — without one
/// there is no zoom state for them to drive, and these options are ignored entirely.  A view
/// with no viewport behaves exactly as it did before 0.6.0.
///
/// ```swift
/// @State private var viewport = WaveformViewport(duration: summary.duration)
///
/// WaveformView(
///     summary:     summary,
///     currentTime: player.currentTime,
///     viewport:    $viewport,
///     zoom:        .editor,
///     onSeek:      { player.seek(to: $0) }
/// )
/// ```
public struct WaveformZoomOptions: Sendable, Equatable {

    /// How a single-finger drag is interpreted.
    ///
    /// Pinch always zooms; the ambiguous input is the one-finger drag, which could reasonably
    /// mean either "scrub" or "scroll the timeline".  This picks which.
    public enum DragBehavior: Sendable, Equatable {
        /// A drag always seeks, at every zoom level.  Panning is still reachable by pinching,
        /// since a pinch anchored off-centre walks the visible range sideways.  This is the
        /// pre-0.6.0 behaviour and the right default for players, where scrubbing is the
        /// primary interaction.
        case seek
        /// A drag pans the visible range while zoomed in, and seeks at 1×.  The right choice for
        /// editor-style UIs, where the waveform reads as a timeline rather than a seek bar.
        case panWhenZoomed
    }

    /// Master switch.  When `false`, a viewport can still be driven programmatically but no
    /// gesture touches it.
    public var isEnabled: Bool

    /// How single-finger drags are interpreted.  Defaults to `.seek`.
    public var dragBehavior: DragBehavior

    /// Upper bound on `WaveformViewport.zoomFactor`.
    public var maxZoomFactor: Double

    /// Smallest visible span, in seconds.  Bounds zoom independently of `maxZoomFactor`, which
    /// on a short file would otherwise allow zooming far past any useful level of detail.
    public var minVisibleDuration: TimeInterval

    /// Double-tapping resets to the full-duration view.
    ///
    /// The first tap of the pair still seeks — on a waveform a tap means "play from here", and
    /// suppressing it would require delaying every single tap by the double-tap interval.  Only
    /// the second tap is consumed.
    public var resetsOnDoubleTap: Bool

    /// Hand predominantly-vertical drags to an enclosing `ScrollView` instead of seeking.
    ///
    /// Set this whenever the waveform is a row in a scrolling list.  The gesture is attached
    /// simultaneously rather than exclusively, and no seek or pan is applied until the touch has
    /// travelled `scrollIntentThreshold` points — at which point a drag that is taller than it is
    /// wide is abandoned for the rest of the gesture, leaving the scroll view to handle it.
    /// Taps are unaffected and still seek.
    public var yieldsToVerticalScroll: Bool

    /// Movement, in points, required before a drag's direction is judged.
    /// Only consulted when `yieldsToVerticalScroll` is `true`.
    public var scrollIntentThreshold: CGFloat

    public init(
        isEnabled: Bool = true,
        dragBehavior: DragBehavior = .seek,
        maxZoomFactor: Double = 50,
        minVisibleDuration: TimeInterval = 0.25,
        resetsOnDoubleTap: Bool = true,
        yieldsToVerticalScroll: Bool = false,
        scrollIntentThreshold: CGFloat = 10
    ) {
        self.isEnabled              = isEnabled
        self.dragBehavior           = dragBehavior
        self.maxZoomFactor          = max(1, maxZoomFactor)
        self.minVisibleDuration     = max(0, minVisibleDuration)
        self.resetsOnDoubleTap      = resetsOnDoubleTap
        self.yieldsToVerticalScroll = yieldsToVerticalScroll
        self.scrollIntentThreshold  = max(0, scrollIntentThreshold)
    }

    // MARK: - Presets

    /// Pinch, pan, and double-tap all disabled.  A viewport remains programmatically drivable.
    public static let disabled = WaveformZoomOptions(isEnabled: false)

    /// Editor-style: a drag pans the timeline once zoomed in, and seeks at 1×.
    public static let editor = WaveformZoomOptions(dragBehavior: .panWhenZoomed)

    /// For a waveform row inside a `ScrollView` or `List` — vertical drags scroll the list.
    public static let inScrollView = WaveformZoomOptions(yieldsToVerticalScroll: true)

    // MARK: - Gesture arithmetic
    //
    // Split out as pure functions so the gesture behaviour is unit-testable without a
    // running SwiftUI hierarchy.

    /// Zoom factor a pinch should land on, given the factor when the gesture began and the
    /// gesture's cumulative magnification.  Clamped to `[1, maxZoomFactor]`.
    public func zoomTarget(base: Double, magnification: CGFloat) -> Double {
        let scaled = base * Double(magnification)
        guard scaled.isFinite else { return base }
        return min(maxZoomFactor, max(1, scaled))
    }

    /// Seconds to pan for a horizontal drag of `deltaPoints`, given the currently visible span
    /// and the view's width.  Negated so that dragging right reveals earlier audio, matching
    /// the direction of every scrollable surface on the platform.
    public static func panSeconds(deltaPoints: CGFloat, visibleSpan: TimeInterval, width: CGFloat) -> TimeInterval {
        guard width > 0, visibleSpan > 0 else { return 0 }
        return -TimeInterval(deltaPoints) * (visibleSpan / TimeInterval(width))
    }
}
