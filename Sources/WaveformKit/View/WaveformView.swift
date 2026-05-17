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
    private let markers: [WaveformMarker]
    private let onSeek: ((TimeInterval) -> Void)?
    private let onMarkerTap: ((WaveformMarker) -> Void)?

    @State private var dragState = DragState()

    public init(
        summary: WaveformSummary,
        currentTime: TimeInterval,
        amplitude: Float = 0,
        bands: [Float] = [],
        style: WaveformStyle = .bars(),
        movement: WaveformMovement = .progress,
        colors: WaveformColors = WaveformColors(),
        markers: [WaveformMarker] = [],
        onSeek: ((TimeInterval) -> Void)? = nil,
        onMarkerTap: ((WaveformMarker) -> Void)? = nil
    ) {
        self.summary = summary
        self.currentTime = currentTime
        self.amplitude = amplitude
        self.bands = bands
        self.style = style
        self.movement = movement
        self.colors = colors
        self.markers = markers
        self.onSeek = onSeek
        self.onMarkerTap = onMarkerTap
    }

    public var body: some View {
        GeometryReader { geo in
            content(width: geo.size.width, height: geo.size.height)
        }
    }

    @ViewBuilder
    private func content(width: CGFloat, height: CGFloat) -> some View {
        let size = CGSize(width: width, height: height)
        ZStack {
            if case .idle = movement {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
                    let phase = Self.idleProgress(at: timeline.date.timeIntervalSinceReferenceDate, cycle: 2.5)
                    renderer(progressOverride: phase, forceShowsProgress: true)
                }
            } else {
                renderer(progressOverride: nil, forceShowsProgress: false)
                    .animation(.linear(duration: 0.05), value: currentTime)
            }
            if shouldRenderMarkers {
                MarkersOverlay(markers: markers, duration: summary.duration)
            }
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .gesture(seekGesture(size: size))
    }

    private var shouldRenderMarkers: Bool {
        guard !markers.isEmpty, summary.duration > 0 else { return false }
        if case .circular = style { return false }
        return true
    }

    @ViewBuilder
    private func renderer(progressOverride: Double?, forceShowsProgress: Bool) -> some View {
        let activeProgress = progressOverride ?? progress
        let activeShowsProgress = forceShowsProgress || movement.showsProgress
        switch style {
        case let .bars(count, spacing, cornerRadius):
            BarsRenderer(
                amplitudes: resampled(to: count),
                progress: activeProgress,
                amplitudeScale: amplitudeScale,
                showsProgress: activeShowsProgress,
                spacing: spacing,
                cornerRadius: cornerRadius,
                colors: colors,
                mirrored: false
            )
        case let .mirroredBars(count, spacing, cornerRadius):
            BarsRenderer(
                amplitudes: resampled(to: count),
                progress: activeProgress,
                amplitudeScale: amplitudeScale,
                showsProgress: activeShowsProgress,
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
                progress: activeProgress,
                showsProgress: activeShowsProgress,
                spacing: spacing,
                cornerRadius: cornerRadius,
                colors: colors
            )
        case let .line(thickness):
            LineRenderer(
                amplitudes: resampled(to: max(2, min(400, summary.amplitudes.count))),
                progress: activeProgress,
                amplitudeScale: amplitudeScale,
                showsProgress: activeShowsProgress,
                thickness: thickness,
                colors: colors
            )
        case let .dots(count, dotSize, spacing):
            DotsRenderer(
                amplitudes: resampled(to: count),
                progress: activeProgress,
                amplitudeScale: amplitudeScale,
                showsProgress: activeShowsProgress,
                dotSize: dotSize,
                spacing: spacing,
                colors: colors
            )
        case let .circular(count, innerRadiusFraction, barWidth):
            CircularBarsRenderer(
                amplitudes: resampled(to: count),
                progress: activeProgress,
                amplitudeScale: amplitudeScale,
                showsProgress: activeShowsProgress,
                innerRadiusFraction: innerRadiusFraction,
                barWidth: barWidth,
                colors: colors
            )
        }
    }

    /// Smooth ping-pong shimmer in `[0, 1]` for `.idle` movement. Continuous and seamless across
    /// cycle boundaries (no jumps to 0). Pure function for unit testing.
    static func idleProgress(at time: TimeInterval, cycle: TimeInterval) -> Double {
        guard cycle > 0 else { return 0 }
        let theta = (time / cycle) * 2 * .pi
        return (1 - cos(theta)) / 2
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

    private func seekGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard summary.duration > 0, size.width > 0 else { return }

                if !dragState.checkedFirstTouch {
                    dragState.checkedFirstTouch = true
                    if onMarkerTap != nil, !markers.isEmpty {
                        dragState.startedOnMarker = Self.hitTestMarker(
                            markers,
                            at: value.startLocation,
                            in: size,
                            duration: summary.duration,
                            style: style
                        )
                    }
                }

                let translation = hypot(value.translation.width, value.translation.height)
                if translation > Self.dragThreshold { dragState.hasDragged = true }

                // While the user is potentially tapping a marker (no drag yet), suppress seek so
                // the marker's onTap fires cleanly on release.
                if dragState.startedOnMarker != nil && !dragState.hasDragged { return }

                let p = Self.seekProgress(for: value.location, in: size, style: style)
                onSeek?(p * summary.duration)
            }
            .onEnded { _ in
                if let marker = dragState.startedOnMarker, !dragState.hasDragged {
                    onMarkerTap?(marker)
                }
                dragState = DragState()
            }
    }

    private static let dragThreshold: CGFloat = 4

    /// Map a touch point to 0...1 progress. Linear for X-axis styles, angular for circular.
    private static func seekProgress(for location: CGPoint, in size: CGSize, style: WaveformStyle) -> Double {
        switch style {
        case .circular:
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let dx = Double(location.x - center.x)
            let dy = Double(location.y - center.y)
            // Match the renderer: angle 0 is at the top, sweeping clockwise.
            var angle = atan2(dy, dx) + .pi / 2
            if angle < 0 { angle += 2 * .pi }
            return min(1, max(0, angle / (2 * .pi)))
        default:
            return min(1, max(0, Double(location.x) / Double(size.width)))
        }
    }

    /// Returns the marker nearest to `location` along the X axis within `hitRadius` points,
    /// or `nil` if none qualify. Region markers report a distance of 0 when the touch is inside.
    /// Always returns `nil` for `.circular` style (markers are linear-only in this release).
    static func hitTestMarker(
        _ markers: [WaveformMarker],
        at location: CGPoint,
        in size: CGSize,
        duration: TimeInterval,
        style: WaveformStyle,
        hitRadius: CGFloat = 14
    ) -> WaveformMarker? {
        guard duration > 0, size.width > 0, !markers.isEmpty else { return nil }
        if case .circular = style { return nil }
        let widthPerSecond = size.width / CGFloat(duration)
        var best: WaveformMarker?
        var bestDistance: CGFloat = .infinity
        for m in markers {
            let startX = CGFloat(m.time) * widthPerSecond
            let dx: CGFloat
            if m.isRegion {
                let endX = startX + CGFloat(m.duration) * widthPerSecond
                if location.x >= startX, location.x <= endX {
                    dx = 0
                } else {
                    dx = min(abs(location.x - startX), abs(location.x - endX))
                }
            } else {
                dx = abs(location.x - startX)
            }
            if dx <= hitRadius, dx < bestDistance {
                best = m
                bestDistance = dx
            }
        }
        return best
    }

    private func resampled(to count: Int) -> [Float] {
        let src = summary.amplitudes
        if src.isEmpty {
            if case .idle = movement { return Self.placeholderAmplitudes(count: count) }
            return []
        }
        guard count > 0 else { return [] }
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

    /// Rolling sinusoidal placeholder used when `.idle` is requested with no loaded summary, so
    /// loading-skeleton UIs render a sensible shape for the shimmer to scan across.
    static func placeholderAmplitudes(count: Int) -> [Float] {
        guard count > 0 else { return [] }
        var out: [Float] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            let t = Float(i) / Float(max(1, count - 1))
            let value = 0.15 + 0.45 * (0.5 + 0.5 * sin(t * .pi * 4))
            out.append(value)
        }
        return out
    }
}

private struct DragState {
    var checkedFirstTouch: Bool = false
    var startedOnMarker: WaveformMarker?
    var hasDragged: Bool = false
}

// MARK: - Previews

#Preview("Bars — progress") {
    WaveformView(
        summary: .demo(),
        currentTime: 12,
        style: .bars(count: 120),
        colors: WaveformColors(played: .accentColor, unplayed: .secondary.opacity(0.3))
    )
    .frame(height: 80)
    .padding()
}

#Preview("Mirrored bars — voice memo") {
    WaveformView(
        summary: .demo(duration: 18),
        currentTime: 9,
        style: .mirroredBars(count: 80),
        colors: WaveformColors(played: .red, unplayed: .red.opacity(0.25))
    )
    .frame(height: 60)
    .padding()
}

#Preview("Dancing bars — reactive") {
    WaveformView(
        summary: .demo(),
        currentTime: 10,
        amplitude: 0.6,
        style: .dancingBars(count: 32),
        movement: .reactive(boost: 1.4)
    )
    .frame(height: 80)
    .padding()
}

#Preview("Line") {
    WaveformView(
        summary: .demo(),
        currentTime: 18,
        style: .line(thickness: 2)
    )
    .frame(height: 80)
    .padding()
}

#Preview("Dots") {
    WaveformView(
        summary: .demo(),
        currentTime: 14,
        style: .dots(count: 60)
    )
    .frame(height: 60)
    .padding()
}

#Preview("Circular") {
    WaveformView(
        summary: .demo(),
        currentTime: 12,
        style: .circular(count: 64),
        colors: WaveformColors(played: .purple, unplayed: .purple.opacity(0.25))
    )
    .aspectRatio(1, contentMode: .fit)
    .frame(width: 220)
    .padding()
}

#Preview("Idle — loading shimmer") {
    WaveformView(
        summary: .empty,
        currentTime: 0,
        style: .bars(count: 80),
        movement: .idle,
        colors: WaveformColors(played: .accentColor, unplayed: .gray.opacity(0.2))
    )
    .frame(height: 60)
    .padding()
}
