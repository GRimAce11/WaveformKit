import SwiftUI

/// Siri Remote seeking for tvOS, where there is no touch screen.
///
/// The waveform takes focus with the system's focus effect, and left and right presses on the
/// clickpad move the playhead by a twentieth of the visible span — so steps get finer as you zoom
/// in, and the view pans to keep the playhead in sight.  Up and down, Play/Pause, and Back are
/// left to the system: the guidelines reserve swipes for moving focus, Play/Pause for playback,
/// and Back for returning to the previous screen.
///
/// The arithmetic is compiled everywhere so it can be unit-tested; only the modifier is tvOS.
enum WaveformRemote {
    /// Presses per visible span.  Twenty gives 9-second steps across a 3-minute track.
    static let stepsPerVisibleSpan = 20.0

    /// Seconds for one press: a twentieth of the visible span, never under 0.1 s.
    static func stepSize(visibleRange: ClosedRange<TimeInterval>) -> TimeInterval {
        let span = visibleRange.upperBound - visibleRange.lowerBound
        return max(0.1, span / stepsPerVisibleSpan)
    }

    /// Time to seek to after `presses` steps (negative is earlier), clamped to the file.
    static func seekTarget(
        currentTime: TimeInterval,
        duration: TimeInterval,
        visibleRange: ClosedRange<TimeInterval>,
        presses: Int
    ) -> TimeInterval {
        let target = currentTime + Double(presses) * stepSize(visibleRange: visibleRange)
        return min(duration, max(0, target))
    }

    /// Steps for a left or right press: `+1` (later) for right, `-1` for left, swapped when
    /// time runs right to left.
    static func presses(isLeft: Bool, rightToLeft: Bool) -> Int {
        (isLeft != rightToLeft) ? -1 : 1
    }

    /// The viewport panned just far enough that `time` is inside it.  Unchanged when it is
    /// already visible.
    static func viewport(_ viewport: WaveformViewport, following time: TimeInterval) -> WaveformViewport {
        var vp = viewport
        if time < vp.visibleRange.lowerBound {
            vp.pan(by: time - vp.visibleRange.lowerBound)
        } else if time > vp.visibleRange.upperBound {
            vp.pan(by: time - vp.visibleRange.upperBound)
        }
        return vp
    }
}

#if os(tvOS)
/// Makes the waveform a focusable seek control on tvOS.  Inert without `onSeek`, so a
/// display-only waveform never takes focus it cannot use.
struct WaveformRemoteModifier: ViewModifier {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let viewport: Binding<WaveformViewport>?
    let rightToLeft: Bool
    let onSeek: ((TimeInterval) -> Void)?

    func body(content: Content) -> some View {
        if let onSeek, duration > 0 {
            content
                .focusable()
                .hoverEffect(.highlight)
                .onMoveCommand { direction in
                    let isLeft: Bool
                    switch direction {
                    case .left:  isLeft = true
                    case .right: isLeft = false
                    default:     return
                    }
                    let visible = viewport?.wrappedValue.visibleRange ?? 0...duration
                    let target = WaveformRemote.seekTarget(
                        currentTime: currentTime,
                        duration: duration,
                        visibleRange: visible,
                        presses: WaveformRemote.presses(isLeft: isLeft, rightToLeft: rightToLeft)
                    )
                    if let viewport, viewport.wrappedValue.isZoomed {
                        viewport.wrappedValue = WaveformRemote.viewport(viewport.wrappedValue, following: target)
                    }
                    onSeek(target)
                }
        } else {
            content
        }
    }
}
#endif
