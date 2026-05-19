import SwiftUI
import WaveformKit

/// Demonstrates the WaveformRenderer protocol with three distinct custom styles.
/// Each card shows the renderer's source code (abbreviated) alongside its output.
struct CustomRendererScreen: View {

    private let summary: WaveformSummary = .demo(duration: 20, bars: 200, seed: 13)
    @State private var progress: Double = 0.35
    @State private var amplitude: Float = 0
    @State private var animTimer: Timer?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Implement **WaveformRenderer** to draw any style without modifying WaveformKit.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                RendererCard(
                    title: "OscilloscopeRenderer",
                    description: "Continuous line through amplitude values",
                    codeSnippet: """
                    context.stroke(path, with: .color(colors.played), lineWidth: 1.5)
                    """,
                    renderer: OscilloscopeRenderer(),
                    summary: summary,
                    progress: progress,
                    amplitude: amplitude,
                    barCount: 200,
                    height: 100
                )

                RendererCard(
                    title: "MirrorFillRenderer",
                    description: "Symmetric vertical fill with gradient",
                    codeSnippet: """
                    context.fill(topPath, with: .linearGradient(...))
                    context.fill(bottomPath, with: .linearGradient(...))
                    """,
                    renderer: MirrorFillRenderer(),
                    summary: summary,
                    progress: progress,
                    amplitude: amplitude,
                    barCount: 150,
                    height: 100
                )

                RendererCard(
                    title: "LevelMeterRenderer",
                    description: "Vertical level-meter segments",
                    codeSnippet: """
                    for segment in segments {
                        context.fill(segment, with: color(for: amp))
                    }
                    """,
                    renderer: LevelMeterRenderer(),
                    summary: summary,
                    progress: progress,
                    amplitude: amplitude,
                    barCount: 60,
                    height: 80
                )

                progressControl
            }
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .navigationTitle("Custom Renderer")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: startAnimation)
        .onDisappear(perform: stopAnimation)
    }

    private var progressControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Playback progress: \(Int(progress * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: $progress, in: 0...1)
                .padding(.horizontal)
        }
    }

    private func startAnimation() {
        var t: Float = 0
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            t += 0.07
            amplitude = abs(sin(t * 0.8)) * 0.7 + 0.1
        }
    }

    private func stopAnimation() {
        animTimer?.invalidate()
        animTimer = nil
    }
}

// MARK: - Renderer Card

private struct RendererCard: View {
    let title: String
    let description: String
    let codeSnippet: String
    let renderer: any WaveformRenderer
    let summary: WaveformSummary
    let progress: Double
    let amplitude: Float
    let barCount: Int
    let height: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.callout, design: .monospaced))
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            WaveformView(
                summary: summary,
                currentTime: progress * summary.duration,
                amplitude: amplitude,
                bands: [],
                style: .custom(renderer: renderer, barCount: barCount),
                movement: .combined(boost: 0.8),
                colors: WaveformColors(
                    played: .accentColor,
                    unplayed: .accentColor.opacity(0.2)
                )
            )
            .frame(height: height)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            Text(codeSnippet)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)
        }
    }
}

// MARK: - Custom Renderer implementations

/// Draws the waveform as a continuous path through the amplitude values.
struct OscilloscopeRenderer: WaveformRenderer {
    func draw(
        context: inout GraphicsContext,
        size: CGSize,
        amplitudes: [Float],
        progress: Double,
        amplitudeScale: CGFloat,
        showsProgress: Bool,
        colors: WaveformColors
    ) {
        guard amplitudes.count > 1 else { return }
        let midY = size.height / 2
        let progressX = size.width * CGFloat(progress)

        func makePath(flipped: Bool) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: midY))
            for (i, amp) in amplitudes.enumerated() {
                let x = size.width * CGFloat(i) / CGFloat(amplitudes.count - 1)
                let sign: CGFloat = flipped ? 1 : -1
                let y = midY + sign * CGFloat(amp) * amplitudeScale * midY
                i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
            }
            return path
        }

        // Draw played portion
        if showsProgress {
            context.clip(to: Path(CGRect(x: 0, y: 0, width: progressX, height: size.height)))
        }
        context.stroke(makePath(flipped: false), with: .color(colors.played), lineWidth: 1.5)
        context.stroke(makePath(flipped: true),  with: .color(colors.played.opacity(0.4)), lineWidth: 1)

        if showsProgress {
            context.resetClip()
            let unplayed = Path(CGRect(x: progressX, y: 0,
                                      width: size.width - progressX, height: size.height))
            context.clip(to: unplayed)
            context.stroke(makePath(flipped: false), with: .color(colors.unplayed), lineWidth: 1.5)
            context.stroke(makePath(flipped: true),  with: .color(colors.unplayed.opacity(0.4)), lineWidth: 1)
            context.resetClip()
        }
    }
}

/// Symmetric top/bottom fill with a vertical gradient.
struct MirrorFillRenderer: WaveformRenderer {
    func draw(
        context: inout GraphicsContext,
        size: CGSize,
        amplitudes: [Float],
        progress: Double,
        amplitudeScale: CGFloat,
        showsProgress: Bool,
        colors: WaveformColors
    ) {
        guard amplitudes.count > 1 else { return }
        let midY = size.height / 2
        let progressX = size.width * CGFloat(progress)
        let gradient = Gradient(colors: [colors.played, colors.played.opacity(0.15)])

        func buildFill() -> Path {
            var top = Path(), bot = Path()
            top.move(to: CGPoint(x: 0, y: midY))
            bot.move(to: CGPoint(x: 0, y: midY))
            for (i, amp) in amplitudes.enumerated() {
                let x = size.width * CGFloat(i) / CGFloat(amplitudes.count - 1)
                let h = CGFloat(amp) * amplitudeScale * midY * 0.9
                top.addLine(to: CGPoint(x: x, y: midY - h))
                bot.addLine(to: CGPoint(x: x, y: midY + h))
            }
            top.addLine(to: CGPoint(x: size.width, y: midY))
            top.closeSubpath()
            bot.addLine(to: CGPoint(x: size.width, y: midY))
            bot.closeSubpath()
            var combined = top
            combined.addPath(bot)
            return combined
        }

        let fill = buildFill()
        let shading = GraphicsContext.Shading.linearGradient(
            gradient,
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 0, y: size.height)
        )

        if showsProgress {
            context.clip(to: Path(CGRect(x: 0, y: 0, width: progressX, height: size.height)))
            context.fill(fill, with: shading)
            context.resetClip()
            let unplayedGrad = Gradient(colors: [colors.unplayed, colors.unplayed.opacity(0.05)])
            let unplayedShading = GraphicsContext.Shading.linearGradient(
                unplayedGrad, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height))
            context.clip(to: Path(CGRect(x: progressX, y: 0,
                                         width: size.width - progressX, height: size.height)))
            context.fill(fill, with: unplayedShading)
            context.resetClip()
        } else {
            context.fill(fill, with: shading)
        }
    }
}

/// Multi-segment level-meter style, colour-coded by intensity.
struct LevelMeterRenderer: WaveformRenderer {
    private let segmentCount = 8

    func draw(
        context: inout GraphicsContext,
        size: CGSize,
        amplitudes: [Float],
        progress: Double,
        amplitudeScale: CGFloat,
        showsProgress: Bool,
        colors: WaveformColors
    ) {
        guard !amplitudes.isEmpty else { return }
        let barW  = size.width / CGFloat(amplitudes.count)
        let segH  = size.height / CGFloat(segmentCount)
        let gap: CGFloat = 1.5
        let progressX = size.width * CGFloat(progress)

        for (i, amp) in amplitudes.enumerated() {
            let x = CGFloat(i) * barW
            let lit = Int((CGFloat(amp) * amplitudeScale * CGFloat(segmentCount)).rounded())
            let isPlayed = showsProgress && (x + barW / 2 <= progressX)

            for seg in 0..<min(lit, segmentCount) {
                let frac = Double(seg) / Double(segmentCount)
                let segColor: Color = frac > 0.75 ? .red
                    : frac > 0.5  ? .orange
                    : isPlayed    ? colors.played
                    : colors.unplayed

                let y = size.height - CGFloat(seg + 1) * segH
                let rect = CGRect(x: x + 1, y: y + gap / 2,
                                  width: barW - 2, height: segH - gap)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(segColor))
            }

            // Unlit segments
            for seg in lit..<segmentCount {
                let y = size.height - CGFloat(seg + 1) * segH
                let rect = CGRect(x: x + 1, y: y + gap / 2,
                                  width: barW - 2, height: segH - gap)
                context.fill(Path(roundedRect: rect, cornerRadius: 1),
                             with: .color(Color.gray.opacity(0.12)))
            }
        }
    }
}

#Preview {
    NavigationStack { CustomRendererScreen() }
}
