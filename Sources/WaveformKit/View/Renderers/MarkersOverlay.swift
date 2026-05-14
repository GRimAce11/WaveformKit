import SwiftUI

/// Renders `WaveformMarker`s above any linear waveform style. Hit-testing happens in
/// `WaveformView`; this view is purely visual and disables its own hit testing so the parent's
/// drag gesture continues to receive all touches.
struct MarkersOverlay: View {
    let markers: [WaveformMarker]
    let duration: TimeInterval

    var body: some View {
        Canvas { context, size in
            guard duration > 0, size.width > 0, size.height > 0, !markers.isEmpty else { return }
            let widthPerSecond = size.width / CGFloat(duration)
            let dotSize: CGFloat = 8
            let topPad: CGFloat = dotSize + 2

            for m in markers {
                let startX = clamp(CGFloat(m.time) * widthPerSecond, 0, size.width)

                if m.isRegion {
                    let endX = clamp(CGFloat(m.time + m.duration) * widthPerSecond, 0, size.width)
                    let bandWidth = max(1, endX - startX)
                    let band = CGRect(x: startX, y: 0, width: bandWidth, height: size.height)
                    context.fill(Path(band), with: .color(m.color.opacity(0.22)))

                    var edge = Path()
                    edge.move(to: CGPoint(x: startX, y: 0))
                    edge.addLine(to: CGPoint(x: startX, y: size.height))
                    context.stroke(edge, with: .color(m.color), lineWidth: 1.5)
                } else {
                    var line = Path()
                    line.move(to: CGPoint(x: startX, y: topPad))
                    line.addLine(to: CGPoint(x: startX, y: size.height))
                    context.stroke(line, with: .color(m.color), lineWidth: 1.5)

                    let dot = CGRect(x: startX - dotSize / 2, y: 0, width: dotSize, height: dotSize)
                    context.fill(Path(ellipseIn: dot), with: .color(m.color))
                }

                if let label = m.label {
                    let text = Text(label).font(.system(size: 10, weight: .medium))
                    let resolved = context.resolve(text)
                    let labelX: CGFloat
                    let anchor: UnitPoint
                    if m.isRegion {
                        let endX = clamp(CGFloat(m.time + m.duration) * widthPerSecond, 0, size.width)
                        labelX = (startX + endX) / 2
                        anchor = .top
                    } else {
                        labelX = startX + dotSize
                        anchor = .topLeading
                    }
                    context.draw(resolved, at: CGPoint(x: labelX, y: 0), anchor: anchor)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func clamp(_ x: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(hi, max(lo, x))
    }
}
