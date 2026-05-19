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
    private let viewportBinding: Binding<WaveformViewport>?
    private let onSeek: ((TimeInterval) -> Void)?
    private let onMarkerTap: ((WaveformMarker) -> Void)?

    @State private var dragState = DragState()
    /// Per-view-identity cache for resampled amplitude arrays.
    /// Lives in @State so SwiftUI preserves the same instance across re-renders.
    @State private var resampleCache = ResampleCache()

    public init(
        summary: WaveformSummary,
        currentTime: TimeInterval,
        amplitude: Float = 0,
        bands: [Float] = [],
        style: WaveformStyle = .bars(),
        movement: WaveformMovement = .progress,
        colors: WaveformColors = WaveformColors(),
        markers: [WaveformMarker] = [],
        viewport: Binding<WaveformViewport>? = nil,
        onSeek: ((TimeInterval) -> Void)? = nil,
        onMarkerTap: ((WaveformMarker) -> Void)? = nil
    ) {
        self.summary        = summary
        self.currentTime    = currentTime
        self.amplitude      = amplitude
        self.bands          = bands
        self.style          = style
        self.movement       = movement
        self.colors         = colors
        self.markers        = markers
        self.viewportBinding = viewport
        self.onSeek         = onSeek
        self.onMarkerTap    = onMarkerTap
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
                MarkersOverlay(markers: markers, duration: summary.duration, style: style)
            }
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .gesture(seekGesture(size: size))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityValue(accessibilityValueText)
        .accessibilityAdjustableAction { direction in
            guard summary.duration > 0 else { return }
            let stepSize = max(1, summary.duration * 0.05)
            switch direction {
            case .increment:
                onSeek?(min(summary.duration, currentTime + stepSize))
            case .decrement:
                onSeek?(max(0, currentTime - stepSize))
            @unknown default:
                break
            }
        }
        .accessibilityChildren {
            markerAccessibilityChildren
        }
    }

    /// Invisible accessibility-only overlay that exposes each `WaveformMarker` as a focusable
    /// VoiceOver element. Positioned at the marker's visual location so "explore by touch"
    /// works; default action invokes `onMarkerTap`.
    @ViewBuilder
    private var markerAccessibilityChildren: some View {
        if !markers.isEmpty, summary.duration > 0 {
            GeometryReader { geo in
                ForEach(markers) { marker in
                    let position = markerAccessibilityPosition(marker, in: geo.size)
                    Color.clear
                        .frame(width: 30, height: 30)
                        .position(position)
                        .accessibilityElement()
                        .accessibilityLabel(Self.markerAccessibilityLabel(for: marker))
                        .accessibilityAddTraits(onMarkerTap != nil ? .isButton : [])
                        .accessibilityAction {
                            onMarkerTap?(marker)
                        }
                }
            }
        }
    }

    private func markerAccessibilityPosition(_ marker: WaveformMarker, in size: CGSize) -> CGPoint {
        guard summary.duration > 0 else { return .zero }
        if case .circular = style {
            let side = min(size.width, size.height)
            let outerR = side / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            // Stay in CGFloat throughout so `cos` / `sin` resolve unambiguously on toolchains
            // (Swift 6.0 / Xcode 16) where the Double and CGFloat overloads are both visible.
            let progressFrac = CGFloat((marker.time + marker.duration / 2) / summary.duration)
            let angle: CGFloat = -.pi / 2 + progressFrac * 2 * .pi
            return CGPoint(x: center.x + cos(angle) * outerR, y: center.y + sin(angle) * outerR)
        }
        let centerTime = marker.time + marker.duration / 2
        let x = CGFloat(centerTime / summary.duration) * size.width
        return CGPoint(x: x, y: size.height / 2)
    }

    /// Public so apps with custom accessibility wrappers can reuse the same phrasing.
    public static func markerAccessibilityLabel(for marker: WaveformMarker) -> String {
        let startStr = formatTime(marker.time)
        let name = marker.label?.trimmingCharacters(in: .whitespaces)
        if marker.isRegion {
            let endStr = formatTime(marker.time + marker.duration)
            if let name, !name.isEmpty {
                return "\(name), \(startStr) to \(endStr)"
            }
            return "Region, \(startStr) to \(endStr)"
        } else {
            if let name, !name.isEmpty {
                return "\(name), at \(startStr)"
            }
            return "Marker at \(startStr)"
        }
    }

    private var accessibilityLabelText: String {
        let base = summary.duration > 0 ? "Audio waveform" : "Audio waveform, no audio loaded"
        if !markers.isEmpty {
            let suffix = markers.count == 1 ? "1 marker" : "\(markers.count) markers"
            return "\(base), \(suffix)"
        }
        return base
    }

    private var accessibilityValueText: String {
        guard summary.duration > 0 else { return "no audio loaded" }
        return "\(Self.formatTime(currentTime)) of \(Self.formatTime(summary.duration))"
    }

    /// Render a static snapshot of a waveform view as a `CGImage`. Useful for voice-memo
    /// thumbnails, share-sheet previews, App Store screenshots, and any cell-list rendering
    /// where running a live `Canvas` per row would be wasteful.
    ///
    /// Wrap the result in `UIImage(cgImage:)` (iOS / tvOS / visionOS) or
    /// `NSImage(cgImage:size:)` (macOS) as needed.
    @MainActor
    public static func snapshot(
        summary: WaveformSummary,
        size: CGSize,
        currentTime: TimeInterval = 0,
        amplitude: Float = 0,
        bands: [Float] = [],
        style: WaveformStyle = .bars(),
        movement: WaveformMovement = .progress,
        colors: WaveformColors = WaveformColors(),
        markers: [WaveformMarker] = [],
        scale: CGFloat = 2
    ) -> CGImage? {
        let view = WaveformView(
            summary: summary,
            currentTime: currentTime,
            amplitude: amplitude,
            bands: bands,
            style: style,
            movement: movement,
            colors: colors,
            markers: markers
        )
        .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return renderer.cgImage
    }

    static func formatTime(_ t: TimeInterval) -> String {
        let total = Int(t.rounded())
        let minutes = total / 60
        let seconds = total % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let remMin = minutes % 60
            return String(format: "%d:%02d:%02d", hours, remMin, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var shouldRenderMarkers: Bool {
        guard !markers.isEmpty, summary.duration > 0 else { return false }
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
        case let .custom(renderer, barCount):
            CustomRendererView(
                renderer: renderer,
                amplitudes: resampled(to: barCount),
                progress: activeProgress,
                amplitudeScale: amplitudeScale,
                showsProgress: activeShowsProgress,
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
        // When a viewport is active and zoomed, progress is relative to the visible span.
        if let vp = viewportBinding?.wrappedValue, vp.isZoomed {
            return vp.visibleProgress(for: currentTime) ?? (currentTime < vp.visibleRange.lowerBound ? 0 : 1)
        }
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
                // Map the normalised seek position to absolute time, respecting any active viewport.
                let seekTime: TimeInterval
                if let vp = viewportBinding?.wrappedValue, vp.isZoomed {
                    seekTime = vp.time(forVisibleProgress: p)
                } else {
                    seekTime = p * summary.duration
                }
                onSeek?(seekTime)
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

    /// Returns the marker nearest to `location` within `hitRadius` points (measured as horizontal
    /// distance for linear styles, arc length for `.circular`), or `nil` if none qualify. Region
    /// markers report a distance of 0 when the touch is inside their span.
    static func hitTestMarker(
        _ markers: [WaveformMarker],
        at location: CGPoint,
        in size: CGSize,
        duration: TimeInterval,
        style: WaveformStyle,
        hitRadius: CGFloat = 14
    ) -> WaveformMarker? {
        guard duration > 0, size.width > 0, !markers.isEmpty else { return nil }
        if case .circular = style {
            return hitTestCircular(markers, at: location, in: size, duration: duration, hitRadius: hitRadius)
        }
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

    /// Angular hit-test for circular style. Compare arc-length distances along the outer ring.
    private static func hitTestCircular(
        _ markers: [WaveformMarker],
        at location: CGPoint,
        in size: CGSize,
        duration: TimeInterval,
        hitRadius: CGFloat
    ) -> WaveformMarker? {
        let side = min(size.width, size.height)
        let outerR = side / 2
        guard outerR > 0 else { return nil }
        let circumference = 2 * .pi * outerR
        let tapProgress = Self.seekProgress(for: location, in: size, style: .circular())
        var best: WaveformMarker?
        var bestDistance: CGFloat = .infinity
        for m in markers {
            let startP = m.time / duration
            let endP = (m.time + m.duration) / duration
            let arcDistance: CGFloat
            if m.isRegion, tapProgress >= startP, tapProgress <= endP {
                arcDistance = 0
            } else {
                let dStart = Self.angularDistance(tapProgress, startP) * circumference
                let dEnd = m.isRegion ? Self.angularDistance(tapProgress, endP) * circumference : .infinity
                arcDistance = min(dStart, dEnd)
            }
            if arcDistance <= hitRadius, arcDistance < bestDistance {
                best = m
                bestDistance = arcDistance
            }
        }
        return best
    }

    /// Minimum distance between two normalized [0, 1] progress values on a circular ring.
    private static func angularDistance(_ a: Double, _ b: Double) -> CGFloat {
        let raw = abs(a - b)
        return CGFloat(min(raw, 1 - raw))
    }

    /// Returns resampled amplitudes for the current viewport and bar count.
    ///
    /// Results are cached in `resampleCache` keyed by (summaryID, count, visibleSlice).
    /// Under reactive or dancing-bars movement (30–60 Hz re-renders) this eliminates
    /// the per-frame `[Float]` allocation that the original uncached implementation incurred.
    private func resampled(to count: Int) -> [Float] {
        let src = summary.amplitudes
        guard !src.isEmpty else {
            if case .idle = movement { return Self.placeholderAmplitudes(count: count) }
            return []
        }
        guard count > 0 else { return [] }

        // Determine which slice of the amplitude array is currently visible.
        // Full range when no viewport is set or zoom factor == 1.
        let startIdx: Int
        let endIdx: Int
        if let vp = viewportBinding?.wrappedValue, vp.isZoomed {
            let range = vp.visibleIndices(totalBars: src.count)
            startIdx = range.lowerBound
            endIdx   = range.upperBound
        } else {
            startIdx = 0
            endIdx   = src.count
        }
        guard startIdx < endIdx else { return [] }

        if let cached = resampleCache.get(
            summaryID: summary.id, count: count,
            startIdx: startIdx, endIdx: endIdx
        ) {
            return cached
        }

        let result = resampleAmplitudes(
            src: src, startIdx: startIdx, endIdx: endIdx, targetCount: count
        )
        resampleCache.set(
            result, summaryID: summary.id, count: count,
            startIdx: startIdx, endIdx: endIdx
        )
        return result
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

// MARK: - WaveformLoader convenience init

extension WaveformView {
    /// Initialise a `WaveformView` driven directly by a `WaveformLoader`.
    ///
    /// While `loader.state` is `.idle` or `.loading`, the view renders a skeleton shimmer
    /// (`.idle` movement) so the layout placeholder has the correct size immediately.
    /// Once the summary is available (`.loaded`) the view transitions to the requested
    /// `movement` with a SwiftUI animation.
    ///
    /// Combine with `.waveformStateOverlay(_:)` to show a progress bar or error UI:
    ///
    /// ```swift
    /// WaveformView(loader: loader, currentTime: player.currentTime, onSeek: { ... })
    ///     .waveformStateOverlay(loader.state)
    /// ```
    public init(
        loader: WaveformLoader,
        currentTime: TimeInterval,
        amplitude: Float = 0,
        bands: [Float] = [],
        style: WaveformStyle = .bars(),
        movement: WaveformMovement = .progress,
        colors: WaveformColors = WaveformColors(),
        markers: [WaveformMarker] = [],
        viewport: Binding<WaveformViewport>? = nil,
        onSeek: ((TimeInterval) -> Void)? = nil,
        onMarkerTap: ((WaveformMarker) -> Void)? = nil
    ) {
        switch loader.state {
        case .loaded(let summary):
            self.init(
                summary: summary, currentTime: currentTime,
                amplitude: amplitude, bands: bands,
                style: style, movement: movement, colors: colors,
                markers: markers, viewport: viewport,
                onSeek: onSeek, onMarkerTap: onMarkerTap
            )
        default:
            // Not yet loaded — show skeleton shimmer with correct geometry.
            self.init(
                summary: .empty, currentTime: 0,
                amplitude: amplitude, bands: bands,
                style: style, movement: .idle, colors: colors
            )
        }
    }
}

// MARK: - waveformStateOverlay modifier

extension View {
    /// Overlays loading-progress and error UI on any view based on a `WaveformState`.
    ///
    /// - A `.loading(progress:)` state with `progress > 0.02` shows a thin progress bar
    ///   anchored to the bottom edge, animated via SwiftUI's `.linear` timing.
    /// - A `.failed` state shows a centred icon + message using `.regularMaterial` fill.
    /// - All other states leave the view unchanged.
    ///
    /// ```swift
    /// WaveformView(loader: loader, currentTime: 0)
    ///     .waveformStateOverlay(loader.state)
    /// ```
    @ViewBuilder
    public func waveformStateOverlay(_ state: WaveformState) -> some View {
        switch state {
        case .failed(let error):
            overlay {
                ZStack {
                    Rectangle().fill(.regularMaterial)
                    VStack(spacing: 6) {
                        Image(systemName: "waveform.slash")
                            .font(.headline)
                        Text(error.localizedDescription)
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        case .loading(let progress) where progress > 0.02:
            overlay(alignment: .bottom) {
                GeometryReader { geo in
                    Rectangle()
                        .fill(.tint.opacity(0.7))
                        .frame(width: geo.size.width * CGFloat(progress), height: 2)
                        .animation(.linear(duration: 0.08), value: progress)
                }
                .frame(height: 2)
            }
        default:
            self
        }
    }
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
