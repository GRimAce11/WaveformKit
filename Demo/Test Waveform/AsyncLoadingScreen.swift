import SwiftUI
import WaveformKit

/// Demonstrates the WaveformState lifecycle: idle → loading → loaded / failed.
/// The long tone (90 s) makes the loading phase visible so you can see the progress bar update.
struct AsyncLoadingScreen: View {

    @State private var loader = WaveformLoader()
    @State private var stateLog: [String] = []
    @State private var lastLoadURL: URL?

    private let longToneDuration: Double = 90  // long enough to show progress

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                stateCard
                waveformCard
                logCard
                actionButtons
            }
            .padding()
        }
        .navigationTitle("Async Loading")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: stateDescription) { _, new in
            stateLog.insert("→ \(new)", at: 0)
            if stateLog.count > 20 { stateLog.removeLast() }
        }
    }

    // MARK: - State card

    private var stateCard: some View {
        VStack(spacing: 12) {
            HStack {
                stateIndicator
                VStack(alignment: .leading, spacing: 2) {
                    Text(stateTitle)
                        .font(.headline)
                    Text(stateSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if case .loading(let p) = loader.state {
                ProgressView(value: p)
                    .tint(.accentColor)
                    .animation(.linear(duration: 0.1), value: p)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var stateIndicator: some View {
        Group {
            switch loader.state {
            case .idle:
                Image(systemName: "circle.dashed")
                    .foregroundStyle(.secondary)
            case .loading:
                ProgressView()
            case .loaded:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .font(.title2)
        .frame(width: 40)
    }

    // MARK: - Waveform

    private var waveformCard: some View {
        WaveformView(loader: loader, currentTime: 0, style: .bars(count: 150))
            .frame(height: 80)
            .waveformStateOverlay(loader.state)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - State log

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("State transitions").font(.caption).foregroundStyle(.secondary)
            if stateLog.isEmpty {
                Text("Load a file to begin.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(stateLog.prefix(8), id: \.self) { line in
                    Text(line)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Actions

    private var actionButtons: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    startLoad()
                } label: {
                    Label("Load (90 s tone)", systemImage: "waveform.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(loader.state.isLoading)

                Button {
                    loader.cancel()
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!loader.state.isLoading)
            }

            HStack(spacing: 12) {
                Button {
                    simulateError()
                } label: {
                    Label("Simulate Error", systemImage: "exclamationmark.triangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)

                Button {
                    loader.retry()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(loader.state.error == nil)
            }
        }
    }

    // MARK: - Helpers

    private func startLoad() {
        // Generate (or reuse) the long tone synchronously, then load it through WaveformLoader
        // to demonstrate the async progress states.
        guard let url = AudioCatalog.testTone(duration: longToneDuration) else { return }
        lastLoadURL = url
        // Clear the disk cache entry so decoding actually runs (shows progress)
        WaveformCache.remove(url: url, targetBars: 200)
        loader.load(url: url, targetBars: 200, useCache: false)
    }

    private func simulateError() {
        // Load a deliberately invalid URL to produce a .failed state
        let badURL = URL(fileURLWithPath: "/nonexistent/audio.mp3")
        loader.load(url: badURL, targetBars: 200, useCache: false)
    }

    private var stateTitle: String {
        switch loader.state {
        case .idle:              return "Idle"
        case .loading:           return "Loading…"
        case .loaded:            return "Loaded"
        case .failed:            return "Failed"
        }
    }

    private var stateSubtitle: String {
        switch loader.state {
        case .idle:              return "Tap Load to begin"
        case .loading(let p):    return "\(Int(p * 100))% decoded"
        case .loaded(let s):     return "\(s.amplitudes.count) bars · \(formatTime(s.duration))"
        case .failed(let e):     return e.localizedDescription
        }
    }

    private var stateDescription: String {
        switch loader.state {
        case .idle:              return "idle"
        case .loading(let p):    return "loading(\(Int(p * 100))%)"
        case .loaded:            return "loaded"
        case .failed:            return "failed"
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let s = Int(t)
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }
}

#Preview {
    NavigationStack { AsyncLoadingScreen() }
}
