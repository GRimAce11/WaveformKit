import SwiftUI
import WaveformKit

/// Shows `WaveformViewport` driven both ways: by gesture (pinch, pan, double-tap) and
/// programmatically through the buttons below.  The waveform sits inside a `ScrollView`, so it
/// uses `yieldsToVerticalScroll` to leave vertical drags to the scroll view.
struct ViewportScreen: View {

    private let summary: WaveformSummary = .demo(duration: 60, bars: 400, seed: 99)
    @State private var viewport: WaveformViewport
    @State private var currentTime: TimeInterval = 24
    @State private var dragBehavior: WaveformZoomOptions.DragBehavior = .panWhenZoomed

    init() {
        _viewport = State(initialValue: WaveformViewport(duration: 60))
    }

    private var zoomOptions: WaveformZoomOptions {
        WaveformZoomOptions(
            dragBehavior: dragBehavior,
            maxZoomFactor: 32,
            yieldsToVerticalScroll: true
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                infoCard
                waveformSection
                dragBehaviorControl
                zoomControls
                panControls
                statsCard
            }
            .padding()
        }
        .navigationTitle("Viewport")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Info card

    private var infoCard: some View {
        Text("Pinch the waveform to zoom, drag to pan, double-tap to reset. The same `WaveformViewport` is also driven by the buttons below — gestures and code move one value.")
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    // MARK: - Waveform

    private var waveformSection: some View {
        VStack(spacing: 8) {
            WaveformView(
                summary: summary,
                currentTime: currentTime,
                style: .bars(count: 120),
                movement: .progress,
                colors: .init(played: .accentColor, unplayed: .accentColor.opacity(0.2)),
                viewport: $viewport,
                zoom: zoomOptions,
                onSeek: { currentTime = $0 }
            )
            .frame(height: 90)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

            // Visible range indicator
            GeometryReader { geo in
                let norm = viewport.normalizedRange
                let x = geo.size.width * CGFloat(norm.lowerBound)
                let w = geo.size.width * CGFloat(norm.upperBound - norm.lowerBound)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(.tertiarySystemGroupedBackground))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor.opacity(0.5))
                        .frame(width: max(8, w))
                        .offset(x: x)
                }
                .frame(height: 6)
            }
            .frame(height: 6)
            .padding(.horizontal, 2)

            HStack {
                Text(formatTime(viewport.visibleRange.lowerBound))
                Spacer()
                Text(formatTime(viewport.visibleRange.upperBound))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Zoom controls

    private var zoomControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Zoom", systemImage: "magnifyingglass")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ForEach([1.0, 2.0, 4.0, 8.0, 16.0], id: \.self) { factor in
                    Button("\(factor == 1 ? "1×" : "\(Int(factor))×")") {
                        withAnimation(.spring(duration: 0.3)) {
                            if factor == 1 {
                                viewport.resetZoom()
                            } else {
                                viewport.zoom(to: factor, anchor: 0.5)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(abs(viewport.zoomFactor - factor) < 0.1 ? Color.accentColor : Color.secondary)
                }
            }
        }
    }

    // MARK: - Pan controls

    private var panControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Pan", systemImage: "arrow.left.arrow.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button { withAnimation { viewport.pan(by: -visibleSpan * 0.25) } } label: {
                    Image(systemName: "chevron.left.2")
                }
                .buttonStyle(.bordered)

                Button { withAnimation { viewport.pan(by: -visibleSpan * 0.1) } } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button { withAnimation { viewport.pan(by: visibleSpan * 0.1) } } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.bordered)

                Button { withAnimation { viewport.pan(by: visibleSpan * 0.25) } } label: {
                    Image(systemName: "chevron.right.2")
                }
                .buttonStyle(.bordered)
            }

            Text(dragBehavior == .panWhenZoomed
                 ? "Zoom in, then drag the waveform to pan. At 1× a drag seeks."
                 : "A drag always seeks. Pan by pinching off-centre, or with the buttons.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Drag behaviour

    private var dragBehaviorControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Drag behaviour", systemImage: "hand.draw")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("Drag behaviour", selection: $dragBehavior) {
                Text("Seek").tag(WaveformZoomOptions.DragBehavior.seek)
                Text("Pan when zoomed").tag(WaveformZoomOptions.DragBehavior.panWhenZoomed)
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Stats

    private var statsCard: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                statLabel("Zoom factor")
                statValue(String(format: "%.2f×", viewport.zoomFactor))
            }
            GridRow {
                statLabel("Visible span")
                statValue(formatTime(visibleSpan))
            }
            GridRow {
                statLabel("Visible range")
                statValue("\(formatTime(viewport.visibleRange.lowerBound)) → \(formatTime(viewport.visibleRange.upperBound))")
            }
            GridRow {
                statLabel("Playhead")
                statValue(formatTime(currentTime))
            }
            GridRow {
                statLabel("Normalised")
                statValue(String(format: "%.3f … %.3f",
                                 viewport.normalizedRange.lowerBound,
                                 viewport.normalizedRange.upperBound))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func statLabel(_ s: String) -> some View {
        Text(s).font(.caption).foregroundStyle(.secondary)
    }

    private func statValue(_ s: String) -> some View {
        Text(s).font(.system(.caption, design: .monospaced))
    }

    // MARK: - Helpers

    private var visibleSpan: TimeInterval {
        viewport.visibleRange.upperBound - viewport.visibleRange.lowerBound
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let s = Int(t)
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }
}

#Preview {
    NavigationStack { ViewportScreen() }
}
