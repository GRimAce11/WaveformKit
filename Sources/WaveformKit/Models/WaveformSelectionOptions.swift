import SwiftUI

/// Controls how a `WaveformView` creates and edits a selected time range.
///
/// Selection turns on when the view is given a `selection` binding; these options shape the
/// gestures.  The selected range is an ordinary `ClosedRange<TimeInterval>?` that you own, so a
/// trim button, a loop toggle, or an export sheet reads it directly:
///
/// ```swift
/// @State private var selection: ClosedRange<TimeInterval>?
///
/// WaveformView(
///     summary: summary,
///     currentTime: player.currentTime,
///     selection: $selection,
///     selectionOptions: .editor,
///     onSeek: { player.seek(to: $0) }
/// )
/// ```
///
/// ## Gestures
///
/// - **Create** — touch, hold for `Activation.longPress(holdDuration:)`, then drag (the
///   default); or just drag, under `.drag`.  The touch-down point is one end and the finger is
///   the other.
/// - **Adjust** — drag either edge of an existing selection.  Each edge has a full 44-point
///   touch target, wider than the handle you can see.  Dragging one edge past the other swaps
///   them rather than stopping.
/// - **Clear** — tap outside the selection, when `clearsOnTapOutside` is set.  The tap still
///   seeks.
///
/// Selection works on every linear style.  `.circular` ignores it.
public struct WaveformSelectionOptions: Sendable, Equatable {

    /// What a drag has to do before it starts a new selection instead of seeking or panning.
    public enum Activation: Sendable, Equatable {
        /// Hold still for `holdDuration` seconds, then drag.  An ordinary drag still seeks (or
        /// pans), so this suits players where scrubbing comes first — the same split as text
        /// selection on iOS.
        case longPress(holdDuration: TimeInterval = 0.4)
        /// Any horizontal drag selects; taps still seek.  Suits editors, where the waveform is a
        /// timeline to cut rather than a seek bar.  With this activation a drag never pans —
        /// pan by pinching off-centre, or drive the viewport from code.
        case drag
    }

    /// What starts a new selection.  Defaults to `.longPress()`.
    public var activation: Activation

    /// Selections shorter than this, in seconds, are discarded when the finger lifts — a drag
    /// that barely moved was almost certainly meant as a tap.
    public var minimumLength: TimeInterval

    /// When set, both edges snap to multiples of this many seconds — 0.1 for a decisecond
    /// grid, or one beat's length for musical editing.  `nil` leaves them where the finger is.
    public var snapInterval: TimeInterval?

    /// A tap outside the selection clears it, as well as seeking.
    public var clearsOnTapOutside: Bool

    /// Write the binding on every movement of the finger (`true`) or once, when it lifts
    /// (`false`).  Turn it off when something expensive reacts to the selection — restarting a
    /// looped playback, say — so it runs once per gesture instead of once per frame.  The
    /// selection is drawn live either way.
    public var updatesWhileDragging: Bool

    /// Fill and handle colour.  `nil` uses the view's played colour.
    public var tint: Color?

    public init(
        activation: Activation = .longPress(),
        minimumLength: TimeInterval = 0.1,
        snapInterval: TimeInterval? = nil,
        clearsOnTapOutside: Bool = true,
        updatesWhileDragging: Bool = true,
        tint: Color? = nil
    ) {
        self.activation         = activation
        self.minimumLength      = max(0, minimumLength)
        self.snapInterval       = snapInterval.flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
        self.clearsOnTapOutside = clearsOnTapOutside
        self.updatesWhileDragging = updatesWhileDragging
        self.tint               = tint
    }

    // MARK: - Presets

    /// Long-press then drag to select.  The default.
    public static let `default` = WaveformSelectionOptions()

    /// Drag to select, for trim and edit screens.
    public static let editor = WaveformSelectionOptions(activation: .drag)

    // MARK: - Arithmetic
    //
    // Pure functions, so the selection behaviour is unit-testable without a gesture in flight.

    /// `time` rounded to the nearest `snapInterval`, clamped to `0...duration`.
    public func snapped(_ time: TimeInterval, duration: TimeInterval) -> TimeInterval {
        let upper = max(0, duration)
        guard time.isFinite else { return 0 }
        var t = min(upper, max(0, time))
        if let snapInterval {
            t = min(upper, (t / snapInterval).rounded() * snapInterval)
        }
        return t
    }

    /// The range between two times in either order, snapped and clamped to the file.
    ///
    /// Returns `nil` when it is shorter than `minimumLength` — pass `enforcingMinimum: false`
    /// for the in-progress range drawn under the finger, which may legitimately be tiny.
    public func range(
        from a: TimeInterval,
        to b: TimeInterval,
        duration: TimeInterval,
        enforcingMinimum: Bool = true
    ) -> ClosedRange<TimeInterval>? {
        guard duration > 0 else { return nil }
        let lo = snapped(min(a, b), duration: duration)
        let hi = snapped(max(a, b), duration: duration)
        if enforcingMinimum, hi - lo < max(minimumLength, .ulpOfOne) { return nil }
        return lo...hi
    }

    /// Whether a drag whose touch went down at `touchDown` and first moved at `firstMove`
    /// should create a selection.
    public func activatesSelection(touchDown: Date, firstMove: Date) -> Bool {
        switch activation {
        case .drag:
            return true
        case .longPress(let holdDuration):
            return firstMove.timeIntervalSince(touchDown) >= holdDuration
        }
    }

    /// Distance, in seconds, that one VoiceOver swipe moves a selection edge: the snap interval
    /// if there is one, otherwise 1 % of the file, but never less than `minimumLength`.
    public func accessibilityStep(duration: TimeInterval) -> TimeInterval {
        if let snapInterval { return snapInterval }
        return max(minimumLength, max(0, duration) * 0.01)
    }
}
