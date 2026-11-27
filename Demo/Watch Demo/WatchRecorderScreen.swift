import SwiftUI
import WaveformKit

/// Live recording from the watch microphone: permission prompt, session setup, and the
/// waveform growing as audio comes in.
struct WatchRecorderScreen: View {
    @State private var recorder = MicrophoneRecorder(bandCount: 16, maximumDuration: 30)
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 8) {
            WaveformView(
                summary:     recorder.summary,
                currentTime: recorder.currentTime,
                amplitude:   recorder.currentAmplitude,
                bands:       recorder.bands,
                style:       .mirroredBars(count: 30, spacing: 2, cornerRadius: 1.5),
                movement:    .reactive(boost: 1.4)
            )
            .frame(height: 56)

            Text(String(format: "%.1f s", recorder.currentTime))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)

            Button(recorder.isRecording ? "Stop" : "Record") {
                if recorder.isRecording {
                    recorder.stop()
                } else {
                    Task {
                        do {
                            errorText = nil
                            try await recorder.start()
                        } catch {
                            errorText = error.localizedDescription
                        }
                    }
                }
            }
            .tint(recorder.isRecording ? .red : .accentColor)

            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(.red)
            }
        }
        .navigationTitle("Record")
        .onDisappear { recorder.stop() }
    }
}
