import SwiftUI
import WaveformKit

/// Focus the waveform and press left or right on the clickpad to seek. The buttons above and
/// below are there to check that up and down still move focus out of the waveform.
struct TVPlaybackScreen: View {
    @State private var loader = WaveformLoader()
    @State private var player: AVAudioEnginePlayer?
    @State private var viewport = WaveformViewport(duration: 1)
    @State private var rightToLeft = false
    @State private var usesMetal = false
    @State private var errorText: String?

    private let zoom = WaveformZoomOptions()

    private let markers = [
        WaveformMarker(time: 4, color: .yellow, label: "Intro"),
        WaveformMarker(time: 10, duration: 6, color: .orange, label: "Verse"),
        WaveformMarker(time: 22, color: .pink, label: "Drop"),
    ]

    var body: some View {
        VStack(spacing: 48) {
            Text("WaveformKit on Apple TV")
                .font(.title2)

            HStack(spacing: 32) {
                Button(player?.isPlaying == true ? "Pause" : "Play") { togglePlayback() }
                Button("Zoom in") { zoomBy(2) }
                Button("Zoom out") { zoomBy(0.5) }
                Button(rightToLeft ? "Right to left: on" : "Right to left: off") { rightToLeft.toggle() }
                Button(usesMetal ? "Metal: on" : "Metal: off") { usesMetal.toggle() }
            }

            WaveformView(
                loader:      loader,
                currentTime: player?.currentTime ?? 0,
                amplitude:   player?.currentAmplitude ?? 0,
                bands:       player?.bands ?? [],
                style:       .bars(count: 160, spacing: 2, cornerRadius: 2),
                movement:    .combined(boost: 1.2),
                markers:     markers,
                viewport:    $viewport,
                zoom:        zoom,
                onSeek:      { player?.seek(to: $0) }
            )
            .waveformStateOverlay(loader.state)
            .waveformRenderingBackend(usesMetal ? .metal : .canvas)
            .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)
            .frame(height: 220)
            .padding(.horizontal, 80)

            Text(statusText)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)

            Button("A control below the waveform") {}

            if let errorText {
                Text(errorText).foregroundStyle(.red)
            }
        }
        .padding(60)
        .task { setUp() }
        .onDisappear { player?.stop() }
    }

    private var statusText: String {
        let time = player?.currentTime ?? 0
        let duration = player?.duration ?? 0
        return String(format: "%.1f s of %.1f s · %.1f× zoom · focus the waveform, then press left or right",
                      time, duration, viewport.zoomFactor)
    }

    private func setUp() {
        guard player == nil else { return }
        guard let url = AudioCatalog.testTone(duration: 30) else {
            errorText = "Could not create the test tone."
            return
        }
        loader.load(url: url)
        do {
            let engine = try AVAudioEnginePlayer(url: url, bandCount: 32)
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
