import CoreGraphics
import Foundation

/// Maps between time and horizontal position for the linear styles, honouring the viewport.
///
/// One mapping shared by everything that places or hit-tests things in time — markers, the
/// selection, seeking — so that when zoomed they all agree with the bars, which are drawn from
/// the viewport's visible range.
struct WaveformTimeline: Equatable {
    /// The time span the view's width represents.
    let visibleRange: ClosedRange<TimeInterval>
    let width: CGFloat

    /// The full duration when there is no viewport or it is not zoomed, the visible range
    /// otherwise — the same rule the bars use.
    init(duration: TimeInterval, viewport: WaveformViewport?, width: CGFloat) {
        if let viewport, viewport.isZoomed {
            visibleRange = viewport.visibleRange
        } else {
            visibleRange = 0...max(0, duration)
        }
        self.width = width
    }

    init(visibleRange: ClosedRange<TimeInterval>, width: CGFloat) {
        self.visibleRange = visibleRange
        self.width = width
    }

    private var span: TimeInterval { visibleRange.upperBound - visibleRange.lowerBound }

    /// Points per second.  Zero when there is nothing to map.
    var pointsPerSecond: CGFloat {
        span > 0 && width > 0 ? width / CGFloat(span) : 0
    }

    /// Horizontal position of `time`.  Not clamped: times outside the visible range land
    /// outside `0...width`, which callers clip or skip.
    func x(for time: TimeInterval) -> CGFloat {
        CGFloat(time - visibleRange.lowerBound) * pointsPerSecond
    }

    /// Time at horizontal position `x`, clamped to the visible range.
    func time(forX x: CGFloat) -> TimeInterval {
        guard width > 0 else { return visibleRange.lowerBound }
        let p = min(1, max(0, Double(x / width)))
        return visibleRange.lowerBound + p * span
    }
}

/// One end of a selected range.
enum SelectionEdge: Equatable {
    case start
    case end

    /// The edge whose touch target contains `x`, preferring the nearer one when they overlap.
    ///
    /// The targets are `hitWidth` wide — 44 points by default, the HIG minimum — centred on
    /// each edge, so the visible handle can stay slim.
    static func hitTest(
        x: CGFloat,
        selection: ClosedRange<TimeInterval>,
        timeline: WaveformTimeline,
        hitWidth: CGFloat = 44
    ) -> SelectionEdge? {
        let startDistance = abs(x - timeline.x(for: selection.lowerBound))
        let endDistance = abs(x - timeline.x(for: selection.upperBound))
        let reach = hitWidth / 2
        switch (startDistance <= reach, endDistance <= reach) {
        case (true, true):   return startDistance <= endDistance ? .start : .end
        case (true, false):  return .start
        case (false, true):  return .end
        case (false, false): return nil
        }
    }
}
