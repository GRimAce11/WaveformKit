import SwiftUI

struct CircularBarsRenderer: View {
    let amplitudes: [Float]
    let progress: Double
    let amplitudeScale: CGFloat
    let showsProgress: Bool
    let innerRadiusFraction: CGFloat
    let barWidth: CGFloat
    let colors: WaveformColors

    var body: some View {
        Canvas { context, size in
            let count = amplitudes.count
            guard count > 0, size.width > 0, size.height > 0 else { return }

            let side = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outerR = side / 2
            let innerR = outerR * innerRadiusFraction
            let maxLen = outerR - innerR

            let playedShading = shading(colors.played, gradient: colors.playedGradient, size: size)
            let unplayedShading = shading(colors.unplayed, gradient: colors.unplayedGradient, size: size)

            // Progress sweeps clockwise starting from the top.
            let progressFrac = CGFloat(progress)

            for i in 0..<count {
                let amp = CGFloat(amplitudes[i]) * amplitudeScale
                let len = max(2, min(maxLen, amp * maxLen))

                let angleFrac = CGFloat(i) / CGFloat(count)
                let angle = -CGFloat.pi / 2 + angleFrac * .pi * 2

                let dx = cos(angle)
                let dy = sin(angle)

                let start = CGPoint(x: center.x + dx * innerR, y: center.y + dy * innerR)
                let end = CGPoint(x: center.x + dx * (innerR + len), y: center.y + dy * (innerR + len))

                var path = Path()
                path.move(to: start)
                path.addLine(to: end)

                let isPlayed = !showsProgress || angleFrac <= progressFrac
                context.stroke(
                    path,
                    with: isPlayed ? playedShading : unplayedShading,
                    style: StrokeStyle(lineWidth: barWidth, lineCap: .round)
                )
            }
        }
        .drawingGroup()
    }

    private func shading(_ color: Color, gradient: Gradient?, size: CGSize) -> GraphicsContext.Shading {
        if let gradient {
            return .linearGradient(gradient, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height))
        }
        return .color(color)
    }
}
