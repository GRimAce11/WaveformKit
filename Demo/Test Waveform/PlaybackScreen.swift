import SwiftUI
import AVFoundation
import WaveformKit

/// Full-featured playback demo: WaveformLoader, player adapters, markers, scrubbing.
/// Shows how a real podcast or music player screen integrates WaveformKit end-to-end.
struct PlaybackScreen: View {

    @State private var loader   = WaveformLoader()
    @State private var adapter  = AVPlayerAdapter(player: AVPlayer())
    @State private var tap: AVPlayerAmplitudeTap?

    @State private var style: WaveformStyle = .bars(count: 120)
    @State private var showMarkers = true
    @State private var showingFilePicker = false
    @State private var audioURL: URL?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                waveformSection
                transportSection
                styleSection
                sourceSection
            }
            .padding()
        }
        .navigationTitle("Playback")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav, .aiff]
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                loadUserFile(url)
            }
        }
        .task { loadTestTone() }
        .onDisappear { adapter.pause() }
    }

    // MARK: - Waveform

    private var waveformSection: some View {
        VStack(spacing: 8) {
            Group {
                if case .circular = style {
                    WaveformView(
                        loader:    loader,
                        currentTime: adapter.currentTime,
                        amplitude: tap?.currentAmplitude ?? 0,
                        bands:     tap?.bands ?? [],
                        style:     style,
                        movement:  .combined(boost: 0.8),
                        colors:    .init(played: .accentColor, unplayed: .accentColor.opacity(0.2)),
                        markers:   showMarkers ? markers : [],
                        onSeek:    { adapter.seek(to: $0) }
                    )
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 240)
                } else {
                    WaveformView(
                        loader:    loader,
                        currentTime: adapter.currentTime,
                        amplitude: tap?.currentAmplitude ?? 0,
                        bands:     tap?.bands ?? [],
                        style:     style,
                        movement:  .combined(boost: 0.8),
                        colors:    .init(played: .accentColor, unplayed: .accentColor.opacity(0.2)),
                        markers:   showMarkers ? markers : [],
                        onSeek:    { adapter.seek(to: $0) },
                        onMarkerTap: { adapter.seek(to: $0.time) }
                    )
                    .frame(height: 100)
                }
            }
            .waveformStateOverlay(loader.state)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 16))

            if showMarkers, let err = loader.state.error {
                Label(err.localizedDescription, systemImage: "xmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Transport

    private var transportSection: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    adapter.isPlaying ? adapter.pause() : adapter.play()
                } label: {
                    Image(systemName: adapter.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(formatTime(adapter.currentTime)) / \(formatTime(adapter.duration))")
                        .font(.subheadline.monospacedDigit())
                    Text(audioURL?.lastPathComponent ?? "—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
        }
    }

    // MARK: - Style picker

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Style").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Toggle("Markers", isOn: $showMarkers)
                    .labelsHidden()
                Text("Markers").font(.caption).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(demoStyles, id: \.name) { s in
                        StyleChip(name: s.name, isSelected: styleName == s.name) {
                            style = s.style
                        }
                    }
                }
            }
        }
    }

    // MARK: - Source picker

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Audio source").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Test Tone") { loadTestTone() }
                    .buttonStyle(.bordered)
                Button("Pick File…") { showingFilePicker = true }
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Markers

    private var markers: [WaveformMarker] {
        guard let d = loader.state.summary?.duration, d > 0 else { return [] }
        return [
            WaveformMarker(time: d * 0.10, color: .yellow, label: "Intro"),
            WaveformMarker(time: d * 0.35, duration: d * 0.20, color: .orange, label: "Verse"),
            WaveformMarker(time: d * 0.80, color: .pink, label: "Outro"),
        ]
    }

    // MARK: - Helpers

    private func loadTestTone() {
        guard let url = AudioCatalog.testTone(duration: 30) else { return }
        audioURL = url
        loader.load(url: url, targetBars: 200)
        let player = AVPlayer(url: url)
        adapter = AVPlayerAdapter(player: player)
        tap = AVPlayerAmplitudeTap(player: player, bandCount: 32)
    }

    private func loadUserFile(_ picked: URL) {
        let didStart = picked.startAccessingSecurityScopedResource()
        defer { if didStart { picked.stopAccessingSecurityScopedResource() } }
        let dest = AudioCatalog.cacheDirectory.appendingPathComponent(picked.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.copyItem(at: picked, to: dest)
        audioURL = dest
        loader.load(url: dest, targetBars: 200)
        let player = AVPlayer(url: dest)
        adapter = AVPlayerAdapter(player: player)
        tap = AVPlayerAmplitudeTap(player: player, bandCount: 32)
    }

    private var styleName: String { demoStyles.first { isSameStyle($0.style, style) }?.name ?? "" }

    private func isSameStyle(_ a: WaveformStyle, _ b: WaveformStyle) -> Bool { a == b }

    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Style chip

private struct StyleChip: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.tertiarySystemGroupedBackground),
                            in: Capsule())
                .foregroundStyle(isSelected ? .white : .primary)
        }
    }
}

private struct DemoStyleDef {
    let name: String
    let style: WaveformStyle
}

private let demoStyles: [DemoStyleDef] = [
    .init(name: "bars",         style: .bars(count: 120)),
    .init(name: "mirroredBars", style: .mirroredBars(count: 120)),
    .init(name: "dancingBars",  style: .dancingBars(count: 32)),
    .init(name: "line",         style: .line(thickness: 2)),
    .init(name: "dots",         style: .dots(count: 60)),
    .init(name: "circular",     style: .circular(count: 64)),
]

#Preview {
    NavigationStack { PlaybackScreen() }
}
