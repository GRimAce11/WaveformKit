import SwiftUI
import AVFoundation
import WaveformKit

/// Live microphone demo: start/stop/pause recording, watch the waveform grow in real time,
/// then play back the captured file with a second WaveformView.
struct MicrophoneScreen: View {

    @State private var model = RecorderModel()

    // Playback of the finished recording
    @State private var playbackLoader = WaveformLoader()
    @State private var playbackAdapter: AVAudioPlayerAdapter?
    @State private var playbackTap: AVAudioPlayerAmplitudeTap?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                liveSection
                controlsSection
                errorView
                interruptionView
                playbackSection
            }
            .padding()
        }
        .navigationTitle("Microphone")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            if model.recorder.isRecording { model.recorder.stop() }
            playbackAdapter?.pause()
        }
    }

    // MARK: - Live capture

    private var liveSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Live", systemImage: model.recorder.isRecording ? "record.circle.fill" : "waveform")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(model.recorder.isRecording ? .red : .secondary)
                Spacer()
                Text(timeString(model.recorder.currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let cap = model.recorder.maximumDuration {
                    Text("/ \(timeString(cap))").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                }
            }

            WaveformView(
                summary: model.recorder.summary,
                currentTime: model.recorder.currentTime,
                amplitude: model.recorder.currentAmplitude,
                bands: model.recorder.bands,
                style: .mirroredBars(count: 80),
                movement: model.recorder.isRecording ? .reactive(boost: 1.6) : .idle,
                colors: WaveformColors(
                    played: .red,
                    unplayed: .gray.opacity(0.2),
                    playedGradient: Gradient(colors: [.red, .orange])
                )
            )
            .frame(height: 90)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Record controls

    private var controlsSection: some View {
        HStack(spacing: 12) {
            // Record / Stop
            Button {
                if model.recorder.isRecording {
                    model.recorder.stop()
                    preparePlayback()
                } else {
                    Task { await model.startRecording() }
                }
            } label: {
                Label(
                    model.recorder.isRecording ? "Stop" : "Record",
                    systemImage: model.recorder.isRecording ? "stop.fill" : "record.circle"
                )
                .frame(minWidth: 90)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.recorder.isRecording ? .gray : .red)

            // Pause / Resume
            if model.recorder.isRecording {
                Button {
                    model.recorder.isPaused ? model.recorder.resume() : model.recorder.pause()
                } label: {
                    Label(
                        model.recorder.isPaused ? "Resume" : "Pause",
                        systemImage: model.recorder.isPaused ? "play.fill" : "pause.fill"
                    )
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            // Reset
            Button(role: .destructive) {
                model.recorder.reset()
                playbackLoader = WaveformLoader()
                playbackAdapter?.pause()
                playbackAdapter = nil
                playbackTap = nil
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            .disabled(model.recorder.isRecording)
        }
    }

    // MARK: - Errors / interruptions

    @ViewBuilder
    private var errorView: some View {
        if let err = model.startError {
            Label(err, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var interruptionView: some View {
        if let event = model.interruptionEvent {
            Label(event, systemImage: "bell.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Playback

    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Label("Playback", systemImage: "play.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if model.recorder.recordedFileURL != nil && !model.recorder.isRecording {
                WaveformView(
                    loader: playbackLoader,
                    currentTime: playbackAdapter?.currentTime ?? 0,
                    amplitude: playbackTap?.currentAmplitude ?? 0,
                    bands: playbackTap?.bands ?? [],
                    style: .bars(count: 120),
                    movement: .progress,
                    colors: WaveformColors(played: .indigo, unplayed: .indigo.opacity(0.2)),
                    onSeek: { playbackAdapter?.seek(to: $0) }
                )
                .frame(height: 70)
                .waveformStateOverlay(playbackLoader.state)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

                HStack(spacing: 12) {
                    Button {
                        guard let adapter = playbackAdapter else { return }
                        adapter.isPlaying ? adapter.pause() : adapter.play()
                    } label: {
                        Image(systemName: (playbackAdapter?.isPlaying ?? false) ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(playbackAdapter == nil)

                    Text(timeString(playbackAdapter?.currentTime ?? 0))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Record something to enable playback.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Helpers

    private func preparePlayback() {
        guard let url = model.recorder.recordedFileURL else { return }
        playbackLoader.load(url: url, targetBars: 200, useCache: false)
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            playbackAdapter = AVAudioPlayerAdapter(player: player)
            playbackTap = AVAudioPlayerAmplitudeTap(player: player)
        } catch {
            // Playback is optional; failure is non-fatal for the demo
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - RecorderModel

/// Owns MicrophoneRecorder and surfaces its interruption callback to SwiftUI.
@Observable
@MainActor
final class RecorderModel {
    var interruptionEvent: String?
    var startError: String?
    let recorder: MicrophoneRecorder

    init() {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("wkdemo-mic.caf")
        try? FileManager.default.removeItem(at: outputURL)

        var captured: RecorderModel?
        let rec = MicrophoneRecorder(
            bandCount: 32,
            binsPerSecond: 20,
            maximumDuration: 60,
            outputURL: outputURL,
            autoResumeAfterInterruption: true,
            onInterruption: { event in
                captured?.interruptionEvent = Self.describeInterruption(event)
            }
        )
        self.recorder = rec
        captured = self
    }

    func startRecording() async {
        startError = nil
        interruptionEvent = nil
        do {
            try await recorder.start()
        } catch let e as MicrophoneRecorderError {
            startError = Self.describeError(e)
        } catch {
            startError = error.localizedDescription
        }
    }

    private static func describeInterruption(_ event: AudioInterruption) -> String {
        switch event {
        case .began:                              return "Interruption began (paused)"
        case .ended(let r):                       return "Interruption ended (resume=\(r))"
        case .audioRouteChanged(let reason):
            switch reason {
            case .oldDeviceUnavailable: return "Route: device disconnected"
            case .newDeviceAvailable:   return "Route: new device connected"
            case .other:                return "Route: changed"
            }
        }
    }

    private static func describeError(_ error: MicrophoneRecorderError) -> String {
        switch error {
        case .permissionDenied:           return "Microphone permission denied — enable in Settings."
        case .alreadyRecording:           return "Already recording."
        case .engineStartFailed(let e):   return "Engine failed: \(e.localizedDescription)"
        case .audioSessionFailed(let e):  return "Audio session failed: \(e.localizedDescription)"
        case .fileCreationFailed(let e):  return "File creation failed: \(e.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack { MicrophoneScreen() }
}
