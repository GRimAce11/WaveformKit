# WaveformKit Demo

An Xcode project that demonstrates every major WaveformKit capability: an iPhone and iPad app with a
screen per feature, plus small Apple Watch and Apple TV apps for the platform-specific interaction.

## Screens

| Screen | What it shows |
|---|---|
| **Style Gallery** | All 6 built-in waveform styles with colour/movement controls |
| **Playback** | Full player: seeking, markers, `AVPlayer` + `WaveformLoader` |
| **Async Loading** | `WaveformState` lifecycle — progress bar, cancel, retry, error |
| **Microphone** | Live FFT, recording, interruption handling, playback of captured file |
| **Custom Renderer** | Three `WaveformRenderer` implementations: oscilloscope, mirror fill, level meter |
| **Viewport** | Pinch / pan / double-tap gestures plus the programmatic `WaveformViewport` API |
| **Selection** | Region selection: both activation modes, edge dragging, snapping, zoom to selection, right-to-left layout toggle |

## Apple Watch and Apple TV

| Target | Screens |
|---|---|
| **Watch Demo** (watchOS 10+, standalone) | **Play and zoom**: decodes the test tone with `AVAudioFile`, plays it with live bands, zooms with the Digital Crown (tap the waveform first) or the − / + buttons. **Waveforms in a list**: `.inScrollView` rows, where the crown should keep scrolling the list. **Record**: `MicrophoneRecorder` on the watch. |
| **TV Demo** (tvOS 17+) | One screen: focus the waveform and press left or right on the Siri Remote to seek. Buttons above and below check that focus still moves out of the waveform; others zoom, flip right-to-left time and switch to the Metal backend. |

## Requirements

| Target | Runs on |
|---|---|
| Test Waveform | iOS / iPadOS 26.4+ (the project's deployment target; the package itself supports iOS 17+) |
| Watch Demo | watchOS 10+ |
| TV Demo | tvOS 17+ |

Xcode 16+ is required, since WaveformKit needs a Swift 6 toolchain.

The only dependency is **WaveformKit**, referenced by local path (`..`), so the demo always builds
against the checkout it sits in — no SPM fetch, and changes to the package show up immediately.

## Running

1. Open `Test Waveform.xcodeproj`
2. Pick a scheme — **Test Waveform**, **Watch Demo** or **TV Demo** — and a matching simulator or device
3. Build & Run

All three use your signing team from the project; change **Signing & Capabilities** if you build with another team.

The app generates a test tone locally on first launch — no audio files need to be bundled or downloaded.

The **Microphone** and watch **Record** screens need a physical device and microphone permission.

## Audio

Demo audio is generated on-device using `AVAudioFile` (a swept-frequency tone with a rhythmic envelope). All screens work immediately without network access or external audio files.

To try WaveformKit with your own audio, use the **Pick File** button on the Playback screen.

## Project structure

```
Shared/
└── AudioCatalog.swift              Test tone generator + file cache (used by all three apps)

Watch Demo/
├── WatchDemoApp.swift              @main entry point and screen list
├── WatchPlaybackScreen.swift       AVAudioFile decoding, playback, Digital Crown zoom
├── WatchListScreen.swift           Waveform rows in a List (.inScrollView)
└── WatchRecorderScreen.swift       Recording on the watch

TV Demo/
├── TVDemoApp.swift                 @main entry point
└── TVPlaybackScreen.swift          Siri Remote seeking, focus, zoom, RTL, Metal

Test Waveform/
├── Test_WaveformApp.swift          @main entry point
├── ContentView.swift               Navigation home screen
├── StyleGalleryScreen.swift        All 6 styles with live controls
├── PlaybackScreen.swift            Full playback demo
├── AsyncLoadingScreen.swift        WaveformState lifecycle
├── MicrophoneRecorderScreen.swift  Live recording + playback
├── CustomRendererScreen.swift      WaveformRenderer protocol examples
├── ViewportScreen.swift            WaveformViewport gestures + programmatic zoom/pan
└── SelectionScreen.swift           Region selection gestures, options, and actions
```

## License

MIT — same as WaveformKit.

## Recording README media

Both screens used for the README GIFs can be opened directly with launch arguments, so a
capture is deterministic instead of depending on simulated taps landing on the right row:

```bash
xcrun simctl launch <device> com.sam.metro.Test-Waveform \
    -demoScreen "Style Gallery" -demoMovement reactive
```

`-demoScreen` takes any row title from the home list. `-demoMovement` accepts
`progress`, `reactive`, `combined`, or `idle`, and applies to the Style Gallery.

Pair it with `xcrun simctl status_bar <device> override --time 9:41 ...` for a clean
status bar before recording with `xcrun simctl io <device> recordVideo`.
