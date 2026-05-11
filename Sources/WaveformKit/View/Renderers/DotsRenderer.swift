import SwiftUI

struct DotsRenderer: View {
    let amplitudes: [Float]
    let progress: Double
    let amplitudeScale: CGFloat
    let showsProgress: Bool
    let dotSize: CGFloat
    let spacing: CGFloat
    let colors: WaveformColors

    var body: some View {
        Canvas { context, size in
            let count = amplitudes.count
            guard count > 0, size.width > 0, size.height > 0 else { return }

            let centerY = size.height / 2
            let totalSpacing = spacing * CGFloat(max(0, count - 1))
            let stride = max(dotSize, (size.width - totalSpacing) / CGFloat(count))
            let progressX = size.width * CGFloat(progress)

            let playedShading = shading(colors.played, gradient: colors.playedGradient, size: size)
            let unplayedShading = shading(colors.unplayed, gradient: colors.unplayedGradient, size: size)

            for i in 0..<count {
                let amp = CGFloat(amplitudes[i]) * amplitudeScale
                let x = CGFloat(i) * (stride + spacing)
                // Capsule scales vertically with amplitude; minimum keeps it visible at silence.
                let h = max(dotSize, min(size.height, amp * size.height))
                let rect = CGRect(x: x, y: centerY - h / 2, width: dotSize, height: h)
                let path = Path(roundedRect: rect, cornerRadius: dotSize / 2)
                let isPlayed = !showsProgress || (x + dotSize / 2) <= progressX
                context.fill(path, with: isPlayed ? playedShading : unplayedShading)
            }
        }
        .drawingGroup()
    }

    private func shading(_ color: Color, gradient: Gradient?, size: CGSize) -> GraphicsContext.Shading {
        if let gradient {
            return .linearGradient(gradient, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: size.width, y: 0))
        }
        return .color(color)
    }
}
