import SwiftUI
import AVFoundation

@main
struct WaveformKitDemoApp: App {
    init() {
        // Default session for all playback screens.
        // MicrophoneScreen overrides to .playAndRecord before recording starts.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            HomeScreen()
        }
    }
}
