import SwiftUI

/// A standalone Apple Watch app for checking WaveformKit on watchOS:
/// decoding with `AVAudioFile`, Digital Crown zoom, the crown inside a list, and recording.
@main
struct WatchDemoApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List {
                    NavigationLink("Play and zoom") { WatchPlaybackScreen() }
                    NavigationLink("Waveforms in a list") { WatchListScreen() }
                    NavigationLink("Record") { WatchRecorderScreen() }
                }
                .navigationTitle("WaveformKit")
            }
        }
    }
}
