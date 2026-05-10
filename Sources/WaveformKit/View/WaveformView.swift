import SwiftUI

/// A SwiftUI waveform view that doubles as a seek control.
///
/// Reactive usage with an FFT-capable tap:
/// ```swift
/// WaveformView(
///     summary: summary,
///     currentTime: adapter.currentTime,
///     amplitude: tap.currentAmplitude,
///     bands: tap.bands,
///     style: .dancingBars(count: 32),
///     movement: .reactive(boost: 1.5),
///     onSeek: { adapter.seek(to: $0) }
/// )
/// ```
public struct WaveformView: View {
    private let summary: WaveformSummary
    private let currentTime: TimeInterval
    private let amplitude: Float
    private let bands: [Float]
    private let style: WaveformStyle
    private let movement: WaveformMovement
    private let colors: WaveformColors
    private let onSeek: ((TimeInterval) -> Void)?

    public init(
        summary: WaveformSummary,
        currentTime: TimeInterval,
        amplitude: Float = 0,
        bands: [Float] = [],
        style: WaveformStyle = .bars(),
        movement: WaveformMovement = .progress,
        colors: WaveformColors = WaveformColors(),
        onSeek: ((TimeInterval) -> Void)? = nil
    ) {
        self.summary = summary
        self.currentTime = currentTime
        self.amplitude = amplitude
        self.bands = bands
        self.style = style
        self.movement = movement
        self.colors = colors
        self.onSeek = onSeek
    }

    public var body: some View {
        GeometryReader { geo in
            renderer
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(seekGesture(width: geo.size.width))
                .animation(.linear(duration: 0.05), value: currentTime)
        }
    }

    @ViewBuilder
    private var renderer: some View {
        switch style {
        case let .bars(count, spacing, cornerRadius):
            BarsRenderer(
                amplitudes: resampled(to: count),
                progress: progress,
                amplitudeScale: amplitudeScale,
                showsProgress: movement.showsProgress,
                spacing: spacing,
                cornerRadius: cornerRadius,
                colors: colors,
                mirrored: false
            )
        case let .mirroredBars(count, spacing, cornerRadius):
            BarsRenderer(
                amplitudes: resampled(to: count),
                progress: progress,
                amplitudeScale: amplitudeScale,
                showsProgress: movement.showsProgress,
                spacing: spacing,
                cornerRadius: cornerRadius,
                colors: colors,
                mirrored: true
            )
        case let .dancingBars(count, spacing, cornerRadius):
            DancingBarsRenderer(
                count: count,
                amplitude: amplitude,
                bands: bands,
                progress: progress,
                showsProgress: movement.showsProgress,
                spacing: spacing,
                cornerRadius: cornerRadius,
                colors: colors
            )
        }
    }

    private var progress: Double {
        guard summary.duration > 0 else { return 0 }
        return min(1, max(0, currentTime / summary.duration))
    }

    private var amplitudeScale: CGFloat {
        let boost = movement.reactiveBoost
        guard boost > 0 else { return 1 }
        return 1 + boost * CGFloat(amplitude)
    }

    private func seekGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard summary.duration > 0, width > 0 else { return }
                let p = max(0, min(1, value.location.x / width))
                onSeek?(p * summary.duration)
            }
    }

    private func resampled(to count: Int) -> [Float] {
        let src = summary.amplitudes
        guard !src.isEmpty, count > 0 else { return [] }
        if src.count == count { return src }
        var out: [Float] = []
        out.reserveCapacity(count)
        let stride = Double(src.count) / Double(count)
        for i in 0..<count {
            let start = Int(Double(i) * stride)
            let end = max(start + 1, min(src.count, Int(Double(i + 1) * stride)))
            let slice = src[start..<end]
            let sum = slice.reduce(0, +)
            out.append(sum / Float(slice.count))
        }
        return out
    }
}
