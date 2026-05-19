import SwiftUI
import WaveformKit

/// Shows WaveformViewport's programmatic zoom/pan API.
/// Gesture wiring (pinch-to-zoom) ships in Phase 3; this screen demonstrates the data model.
struct ViewportScreen: View {

    private let summary: WaveformSummary = .demo(duration: 60, bars: 400, seed: 99)
    @State private var viewport: WaveformViewport

    init() {
        _viewport = State(initialValue: WaveformViewport(duration: 60))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                infoCard
                waveformSection
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
        Text("`WaveformViewport` models the visible time window. Zoom and pan update the rendered slice without resampling the full summary. Gesture wiring ships in Phase 3.")
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    // MARK: - Waveform

    private var waveformSection: some View {
        VStack(spacing: 8) {
            WaveformView(
                summary: summary,
                currentTime: viewport.visibleRange.lowerBound + visibleSpan * 0.4,
                style: .bars(count: 120),
                movement: .progress,
                colors: .init(played: .accentColor, unplayed: .accentColor.opacity(0.2)),
                viewport: $viewport
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

            Text("Pinch-to-zoom gesture wiring ships in Phase 3")
                .font(.caption2)
                .foregroundStyle(.tertiary)
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
