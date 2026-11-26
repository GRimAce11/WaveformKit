import SwiftUI

/// Draws the selected range: a translucent band, an edge line at each end, and a round grab
/// handle on each line so the edges read as draggable.
///
/// Purely visual — hit-testing lives in `WaveformView`, whose touch targets are wider than the
/// handles drawn here.
struct SelectionOverlay: View {
    let selection: ClosedRange<TimeInterval>
    let timeline: WaveformTimeline
    let tint: Color

    /// Diameter of the visible grab handles.
    static let handleSize: CGFloat = 10

    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0, timeline.pointsPerSecond > 0 else { return }
            let rawStart = timeline.x(for: selection.lowerBound)
            let rawEnd = timeline.x(for: selection.upperBound)
            // Entirely off screen while zoomed elsewhere: nothing to draw.
            guard rawEnd >= 0, rawStart <= size.width else { return }

            let startX = min(size.width, max(0, rawStart))
            let endX = min(size.width, max(0, rawEnd))
            let band = CGRect(x: startX, y: 0, width: max(1, endX - startX), height: size.height)
            context.fill(Path(band), with: .color(tint.opacity(0.18)))

            // Only draw an edge that is actually on screen; a clipped edge has no handle to grab.
            for x in [rawStart, rawEnd] where x >= 0 && x <= size.width {
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(line, with: .color(tint), lineWidth: 2)

                let d = Self.handleSize
                for y in [d / 2, size.height - d / 2] {
                    let knob = CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d)
                    context.fill(Path(ellipseIn: knob), with: .color(tint))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
