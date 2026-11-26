import CoreGraphics
import Foundation

/// Maps between time and horizontal position for the linear styles, honouring the viewport.
///
/// One mapping shared by everything that places or hit-tests things in time — markers, the
/// selection, seeking — so that when zoomed they all agree with the bars, which are drawn from
/// the viewport's visible range.
///
/// When `rightToLeft` is set, time runs from the trailing (right) edge to the leading (left)
/// one, so `x(for:)` and `time(forX:)` mirror.  Coordinates are always physical — the view
/// forces a left-to-right layout internally — so this is the only place the flip happens.
struct WaveformTimeline: Equatable {
    /// The time span the view's width represents.
    let visibleRange: ClosedRange<TimeInterval>
    let width: CGFloat
    let rightToLeft: Bool

    /// The full duration when there is no viewport or it is not zoomed, the visible range
    /// otherwise — the same rule the bars use.
    init(duration: TimeInterval, viewport: WaveformViewport?, width: CGFloat, rightToLeft: Bool = false) {
        if let viewport, viewport.isZoomed {
            visibleRange = viewport.visibleRange
        } else {
            visibleRange = 0...max(0, duration)
        }
        self.width = width
        self.rightToLeft = rightToLeft
    }

    init(visibleRange: ClosedRange<TimeInterval>, width: CGFloat, rightToLeft: Bool = false) {
        self.visibleRange = visibleRange
        self.width = width
        self.rightToLeft = rightToLeft
    }

    private var span: TimeInterval { visibleRange.upperBound - visibleRange.lowerBound }

    /// Points per second.  Zero when there is nothing to map.
    var pointsPerSecond: CGFloat {
        span > 0 && width > 0 ? width / CGFloat(span) : 0
    }

    /// Horizontal position of `time`.  Not clamped: times outside the visible range land
    /// outside `0...width`, which callers clip or skip.
    func x(for time: TimeInterval) -> CGFloat {
        let fromStart = CGFloat(time - visibleRange.lowerBound) * pointsPerSecond
        return rightToLeft ? width - fromStart : fromStart
    }

    /// Time at horizontal position `x`, clamped to the visible range.
    func time(forX x: CGFloat) -> TimeInterval {
        guard width > 0 else { return visibleRange.lowerBound }
        return visibleRange.lowerBound + progress(forX: x) * span
    }

    /// Position `x` as a fraction of the way through the visible range, in `0...1`.
    func progress(forX x: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        let p = min(1, max(0, Double(x / width)))
        return rightToLeft ? 1 - p : p
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
