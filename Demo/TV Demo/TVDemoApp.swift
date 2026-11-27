import SwiftUI

/// An Apple TV app for checking WaveformKit on tvOS: Siri Remote seeking, focus moving in and
/// out of the waveform, zoom from buttons, right-to-left time, and the Metal backend.
@main
struct TVDemoApp: App {
    var body: some Scene {
        WindowGroup {
            TVPlaybackScreen()
        }
    }
}
