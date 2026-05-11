import SwiftUI

struct LineRenderer: View {
    let amplitudes: [Float]
    let progress: Double
    let amplitudeScale: CGFloat
    let showsProgress: Bool
    let thickness: CGFloat
    let colors: WaveformColors

    var body: some View {
        Canvas { context, size in
            let count = amplitudes.count
            guard count > 1, size.width > 0, size.height > 0 else { return }

            let dx = size.width / CGFloat(count - 1)
            let centerY = size.height / 2
            let progressX = size.width * CGFloat(progress)

            // Build the filled, mirrored envelope path.
            var path = Path()
            path.move(to: CGPoint(x: 0, y: centerY - upper(0) * size.height / 2))
            for i in 1..<count {
                let x = CGFloat(i) * dx
                let y = centerY - upper(i) * size.height / 2
                path.addLine(to: CGPoint(x: x, y: y))
            }
            for i in (0..<count).reversed() {
                let x = CGFloat(i) * dx
                let y = centerY + upper(i) * size.height / 2
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.closeSubpath()

            let playedShading = shading(colors.played, gradient: colors.playedGradient, size: size)
            let unplayedShading = shading(colors.unplayed, gradient: colors.unplayedGradient, size: size)

            if showsProgress {
                context.drawLayer { ctx in
                    ctx.clip(to: Path(CGRect(x: 0, y: 0, width: progressX, height: size.height)))
                    ctx.fill(path, with: playedShading)
                }
                context.drawLayer { ctx in
                    ctx.clip(to: Path(CGRect(x: progressX, y: 0, width: size.width - progressX, height: size.height)))
                    ctx.fill(path, with: unplayedShading)
                }
            } else {
                context.fill(path, with: playedShading)
            }

            // Center line stroke for a "line" aesthetic.
            if thickness > 0 {
                var stroke = Path()
                stroke.move(to: CGPoint(x: 0, y: centerY))
                stroke.addLine(to: CGPoint(x: size.width, y: centerY))
                context.stroke(stroke, with: playedShading, lineWidth: 0.5)
            }
        }
        .drawingGroup()
    }

    private func upper(_ i: Int) -> CGFloat {
        let a = CGFloat(amplitudes[i]) * amplitudeScale
        return min(1, max(0, a))
    }

    private func shading(_ color: Color, gradient: Gradient?, size: CGSize) -> GraphicsContext.Shading {
        if let gradient {
            return .linearGradient(gradient, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: size.width, y: 0))
        }
        return .color(color)
    }
}
