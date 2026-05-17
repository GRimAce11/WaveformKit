import SwiftUI

/// Renders `WaveformMarker`s above a waveform style. Hit-testing happens in `WaveformView`;
/// this view is purely visual and disables its own hit testing so the parent's drag gesture
/// continues to receive all touches.
///
/// Linear styles render point markers as a vertical line + dot + optional label; region markers
/// as a translucent band + edge stripe + label. Circular style renders point markers as a radial
/// tick + dot near the outer edge; regions as a translucent arc band.
struct MarkersOverlay: View {
    let markers: [WaveformMarker]
    let duration: TimeInterval
    let style: WaveformStyle

    var body: some View {
        Canvas { context, size in
            guard duration > 0, size.width > 0, size.height > 0, !markers.isEmpty else { return }
            if case let .circular(_, innerRadiusFraction, barWidth) = style {
                drawCircular(context: context, size: size, innerRadiusFraction: innerRadiusFraction, barWidth: barWidth)
            } else {
                drawLinear(context: context, size: size)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Linear

    private func drawLinear(context: GraphicsContext, size: CGSize) {
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

    // MARK: - Circular

    private func drawCircular(
        context: GraphicsContext,
        size: CGSize,
        innerRadiusFraction: CGFloat,
        barWidth: CGFloat
    ) {
        let side = min(size.width, size.height)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let outerR = side / 2
        let innerR = outerR * innerRadiusFraction
        let tickExtend: CGFloat = max(3, barWidth + 1)
        let dotSize: CGFloat = max(6, barWidth + 3)

        for m in markers {
            let startFrac = CGFloat(m.time / duration)
            let startAngle = -CGFloat.pi / 2 + startFrac * .pi * 2

            if m.isRegion {
                // Arc band from startFrac to endFrac at the bar layer.
                let endFrac = min(1, CGFloat((m.time + m.duration) / duration))
                let endAngle = -CGFloat.pi / 2 + endFrac * .pi * 2
                let arcRadius = (innerR + outerR) / 2
                let arcWidth = outerR - innerR

                var arc = Path()
                arc.addArc(
                    center: center,
                    radius: arcRadius,
                    startAngle: .radians(Double(startAngle)),
                    endAngle: .radians(Double(endAngle)),
                    clockwise: false
                )
                context.stroke(
                    arc,
                    with: .color(m.color.opacity(0.28)),
                    style: StrokeStyle(lineWidth: arcWidth, lineCap: .butt)
                )

                // Edge tick at the start of the region.
                drawRadialTick(context: context, center: center, angle: startAngle, innerR: innerR, outerR: outerR + tickExtend, color: m.color)
            } else {
                // Point marker: a radial tick that extends slightly past the bar layer, plus a dot.
                drawRadialTick(context: context, center: center, angle: startAngle, innerR: innerR, outerR: outerR + tickExtend, color: m.color)

                let dx = cos(startAngle)
                let dy = sin(startAngle)
                let dotCenter = CGPoint(
                    x: center.x + dx * (outerR + tickExtend),
                    y: center.y + dy * (outerR + tickExtend)
                )
                let dotRect = CGRect(
                    x: dotCenter.x - dotSize / 2,
                    y: dotCenter.y - dotSize / 2,
                    width: dotSize,
                    height: dotSize
                )
                context.fill(Path(ellipseIn: dotRect), with: .color(m.color))
            }

            if let label = m.label {
                let labelAngle = m.isRegion
                    ? (startAngle + (-CGFloat.pi / 2 + min(1, CGFloat((m.time + m.duration) / duration)) * .pi * 2)) / 2
                    : startAngle
                let labelDistance = outerR + tickExtend + dotSize
                let lx = center.x + cos(labelAngle) * labelDistance
                let ly = center.y + sin(labelAngle) * labelDistance
                let text = Text(label).font(.system(size: 10, weight: .medium))
                let resolved = context.resolve(text)
                context.draw(resolved, at: CGPoint(x: lx, y: ly), anchor: .center)
            }
        }
    }

    private func drawRadialTick(
        context: GraphicsContext,
        center: CGPoint,
        angle: CGFloat,
        innerR: CGFloat,
        outerR: CGFloat,
        color: Color
    ) {
        let dx = cos(angle)
        let dy = sin(angle)
        var line = Path()
        line.move(to: CGPoint(x: center.x + dx * innerR, y: center.y + dy * innerR))
        line.addLine(to: CGPoint(x: center.x + dx * outerR, y: center.y + dy * outerR))
        context.stroke(line, with: .color(color), lineWidth: 1.5)
    }

    private func clamp(_ x: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(hi, max(lo, x))
    }
}
