import SwiftUI

struct BarsRenderer: View {
    let amplitudes: [Float]
    let progress: Double
    let spacing: CGFloat
    let cornerRadius: CGFloat
    let colors: WaveformColors
    let mirrored: Bool

    var body: some View {
        Canvas { context, size in
            let count = amplitudes.count
            guard count > 0, size.width > 0, size.height > 0 else { return }

            let totalSpacing = spacing * CGFloat(max(0, count - 1))
            let barWidth = max(1, (size.width - totalSpacing) / CGFloat(count))
            let centerY = size.height / 2
            let progressX = size.width * CGFloat(progress)
            let minBarHeight: CGFloat = 2

            let playedShading = shading(colors.played, gradient: colors.playedGradient, size: size)
            let unplayedShading = shading(colors.unplayed, gradient: colors.unplayedGradient, size: size)

            for i in 0..<count {
                let amp = CGFloat(amplitudes[i])
                let x = CGFloat(i) * (barWidth + spacing)
                let h = max(minBarHeight, min(size.height, amp * size.height))
                let rect: CGRect
                if mirrored {
                    rect = CGRect(x: x, y: centerY - h / 2, width: barWidth, height: h)
                } else {
                    rect = CGRect(x: x, y: size.height - h, width: barWidth, height: h)
                }
                let path = Path(roundedRect: rect, cornerRadius: cornerRadius)
                let isPlayed = (x + barWidth / 2) <= progressX
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
