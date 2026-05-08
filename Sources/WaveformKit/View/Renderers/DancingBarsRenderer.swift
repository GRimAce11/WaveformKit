import SwiftUI

struct DancingBarsRenderer: View {
    let count: Int
    let amplitude: Float          // smoothed 0...1 from AmplitudeTap
    let progress: Double
    let showsProgress: Bool
    let spacing: CGFloat
    let cornerRadius: CGFloat
    let colors: WaveformColors

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                draw(context: context, size: size, time: t)
            }
            .drawingGroup()
        }
    }

    private func draw(context: GraphicsContext, size: CGSize, time: TimeInterval) {
        guard count > 0, size.width > 0, size.height > 0 else { return }

        let totalSpacing = spacing * CGFloat(max(0, count - 1))
        let barWidth = max(1, (size.width - totalSpacing) / CGFloat(count))
        let centerY = size.height / 2
        let progressX = size.width * CGFloat(progress)
        let minBarHeight: CGFloat = 3

        let playedShading = shading(colors.played, gradient: colors.playedGradient, size: size)
        let unplayedShading = shading(colors.unplayed, gradient: colors.unplayedGradient, size: size)

        let amp = CGFloat(amplitude)

        for i in 0..<count {
            let phase = Self.phase(for: i)
            let wobble = 0.5 + 0.5 * sin(time * 6.2 + Double(phase) * .pi * 2)
            let perBar = amp * (0.45 + 0.55 * CGFloat(wobble))
            // Floor so quiet sections still show a "resting" pulse.
            let resting: CGFloat = 0.04 + 0.02 * CGFloat(sin(time * 1.7 + Double(phase) * 4))
            let h = max(minBarHeight, max(resting, perBar) * size.height)

            let x = CGFloat(i) * (barWidth + spacing)
            let rect = CGRect(x: x, y: centerY - h / 2, width: barWidth, height: h)
            let path = Path(roundedRect: rect, cornerRadius: cornerRadius)
            let isPlayed = !showsProgress || (x + barWidth / 2) <= progressX
            context.fill(path, with: isPlayed ? playedShading : unplayedShading)
        }
    }

    /// Stable pseudo-random phase per bar so adjacent bars don't move together.
    private static func phase(for index: Int) -> Float {
        let x = Float(index) * 12.9898
        let s = sin(x) * 43758.5453
        return s - floor(s)
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
