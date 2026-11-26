import SwiftUI

struct BarsRenderer: View {
    let amplitudes: [Float]
    let progress: Double
    let amplitudeScale: CGFloat   // 1 = static, >1 in reactive/combined mode
    let showsProgress: Bool
    let spacing: CGFloat
    let cornerRadius: CGFloat
    let colors: WaveformColors
    let mirrored: Bool

    var body: some View {
        Canvas { context, size in
            let count = amplitudes.count
            guard count > 0, size.width > 0, size.height > 0 else { return }

            let layout = BarLayout(count: count, width: size.width, spacing: spacing)
            let barWidth = layout.barWidth
            let centerY = size.height / 2
            let progressX = size.width * CGFloat(progress)

            let playedShading = shading(colors.played, gradient: colors.playedGradient, size: size)
            let unplayedShading = shading(colors.unplayed, gradient: colors.unplayedGradient, size: size)

            for i in 0..<count {
                let amp = CGFloat(amplitudes[i]) * amplitudeScale
                let x = layout.x(at: i)
                let h = BarLayout.barHeight(amplitude: amp, height: size.height)
                let rect: CGRect
                if mirrored {
                    rect = CGRect(x: x, y: centerY - h / 2, width: barWidth, height: h)
                } else {
                    rect = CGRect(x: x, y: size.height - h, width: barWidth, height: h)
                }
                let path = Path(roundedRect: rect, cornerRadius: cornerRadius)
                let isPlayed = !showsProgress || (x + barWidth / 2) <= progressX
                context.fill(path, with: isPlayed ? playedShading : unplayedShading)
            }
        }
        .drawingGroup()
    }

    private func shading(_ color: Color, gradient: Gradient?, size: CGSize) -> GraphicsContext.Shading {
        if let gradient {
            return .linearGradient(
                gradient,
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: size.width, y: 0)
            )
        }
        return .color(color)
    }
}
