import SwiftUI
import WaveformKit

/// Region selection: create a range by gesture, adjust its edges, snap it to a grid, and act
/// on it.  Shares a viewport so selection can be tried while zoomed.
struct SelectionScreen: View {

    private let summary: WaveformSummary = .demo(duration: 60, bars: 400, seed: 7)
    @State private var selection: ClosedRange<TimeInterval>? = 12...27
    @State private var viewport = WaveformViewport(duration: 60)
    @State private var currentTime: TimeInterval = 0
    @State private var usesDragActivation = true
    @State private var snapsToHalfSeconds = false
    @State private var updatesWhileDragging = true
    /// Lays the waveform out right to left, as an Arabic or Hebrew UI would, without changing
    /// the device language.
    @State private var rightToLeft = false
    /// Counts binding writes, to show what `updatesWhileDragging` changes.
    @State private var selectionWrites = 0

    private var options: WaveformSelectionOptions {
        WaveformSelectionOptions(
            activation: usesDragActivation ? .drag : .longPress(),
            minimumLength: 0.5,
            snapInterval: snapsToHalfSeconds ? 0.5 : nil,
            updatesWhileDragging: updatesWhileDragging,
            tint: .orange
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text(instructions)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                WaveformView(
                    summary: summary,
                    currentTime: currentTime,
                    style: .bars(count: 120),
                    colors: .init(played: .accentColor, unplayed: .accentColor.opacity(0.25)),
                    viewport: $viewport,
                    zoom: .inScrollView,
                    selection: $selection,
                    selectionOptions: options,
                    onSeek: { currentTime = $0 }
                )
                .frame(height: 110)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)

                controls
                actions
                stats
            }
            .padding()
        }
        .onChange(of: selection) { selectionWrites += 1 }
        .navigationTitle("Selection")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var instructions: String {
        usesDragActivation
            ? "Drag across the waveform to select. Drag an orange edge to adjust it. Tap outside to clear; a tap still seeks. Pinch to zoom."
            : "Touch and hold, then drag to select — a plain drag still seeks. Drag an orange edge to adjust it. Tap outside to clear."
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Drag to select (editor)", isOn: $usesDragActivation)
            Toggle("Snap to 0.5 s", isOn: $snapsToHalfSeconds)
            Toggle("Update while dragging", isOn: $updatesWhileDragging)
            Toggle("Right-to-left layout", isOn: $rightToLeft)
        }
        .font(.callout)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button("Select 0:20–0:40") { selection = 20...40 }
            Button("Zoom to selection") {
                guard let selection else { return }
                withAnimation(.spring(duration: 0.3)) { viewport.visibleRange = selection }
            }
            .disabled(selection == nil)
            Button("Clear", role: .destructive) { selection = nil }
                .disabled(selection == nil)
        }
        .buttonStyle(.bordered)
        .font(.callout)
    }

    private var stats: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                label("Selection")
                value(selection.map { "\(format($0.lowerBound)) → \(format($0.upperBound))" } ?? "none")
            }
            GridRow {
                label("Length")
                value(selection.map { format($0.upperBound - $0.lowerBound) } ?? "—")
            }
            GridRow {
                label("Binding writes")
                value("\(selectionWrites)")
            }
            GridRow {
                label("Playhead")
                value(format(currentTime))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func label(_ s: String) -> some View {
        Text(s).font(.caption).foregroundStyle(.secondary)
    }

    private func value(_ s: String) -> some View {
        Text(s).font(.system(.caption, design: .monospaced))
    }

    private func format(_ t: TimeInterval) -> String {
        String(format: "%d:%04.1f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60))
    }
}

#Preview {
    NavigationStack { SelectionScreen() }
}
