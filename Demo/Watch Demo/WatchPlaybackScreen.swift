import SwiftUI
import WaveformKit

/// Decodes a generated tone (the watchOS `AVAudioFile` decoder), plays it with live FFT bands,
/// and zooms with the Digital Crown. The − and + buttons are the touch equivalent Apple asks for.
struct WatchPlaybackScreen: View {
    @State private var loader = WaveformLoader()
    @State private var player: AVAudioEnginePlayer?
    @State private var viewport = WaveformViewport(duration: 1)
    @State private var errorText: String?

    private let zoom = WaveformZoomOptions.editor

    var body: some View {
        VStack(spacing: 6) {
            WaveformView(
                loader:      loader,
                currentTime: player?.currentTime ?? 0,
                amplitude:   player?.currentAmplitude ?? 0,
                bands:       player?.bands ?? [],
                style:       .mirroredBars(count: 36, spacing: 2, cornerRadius: 1.5),
                movement:    .combined(boost: 1.2),
                viewport:    $viewport,
                zoom:        zoom,
                onSeek:      { player?.seek(to: $0) }
            )
            .waveformStateOverlay(loader.state)
            .frame(height: 64)

            Text(String(format: "%.1f× · tap, then turn the crown", viewport.zoomFactor))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            HStack {
                Button { zoomBy(0.5) } label: { Image(systemName: "minus.magnifyingglass") }
                    .accessibilityLabel("Zoom out")
                Button { togglePlayback() } label: {
                    Image(systemName: player?.isPlaying == true ? "pause.fill" : "play.fill")
                }
                .accessibilityLabel(player?.isPlaying == true ? "Pause" : "Play")
                Button { zoomBy(2) } label: { Image(systemName: "plus.magnifyingglass") }
                    .accessibilityLabel("Zoom in")
            }

            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(.red)
            }
        }
        .navigationTitle("Play and zoom")
        .task { setUp() }
        .onDisappear { player?.stop() }
    }

    private func setUp() {
        guard player == nil else { return }
        guard let url = AudioCatalog.testTone(duration: 20) else {
            errorText = "Could not create the test tone."
            return
        }
        loader.load(url: url)
        do {
            let engine = try AVAudioEnginePlayer(url: url, bandCount: 16)
            viewport = WaveformViewport(duration: engine.duration)
            player = engine
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func togglePlayback() {
        guard let player else { return }
        player.isPlaying ? player.pause() : player.play()
    }

    private func zoomBy(_ ratio: Double) {
        let target = min(zoom.maxZoomFactor, max(1, viewport.zoomFactor * ratio))
        viewport.zoom(to: target, anchor: 0.5, minSpan: zoom.minVisibleDuration)
    }
}
