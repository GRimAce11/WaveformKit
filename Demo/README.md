# WaveformKit Demo

An Xcode project that demonstrates every major WaveformKit capability in a single, self-contained app.

## Screens

| Screen | What it shows |
|---|---|
| **Style Gallery** | All 6 built-in waveform styles with colour/movement controls |
| **Playback** | Full player: seeking, markers, `AVPlayer` + `WaveformLoader` |
| **Async Loading** | `WaveformState` lifecycle — progress bar, cancel, retry, error |
| **Microphone** | Live FFT, recording, interruption handling, playback of captured file |
| **Custom Renderer** | Three `WaveformRenderer` implementations: oscilloscope, mirror fill, level meter |
| **Viewport** | `WaveformViewport` programmatic zoom and pan |

## Requirements

- iOS 17.0+
- Xcode 15+
- Swift 5.9+

The only dependency is **WaveformKit** (fetched via SPM from `https://github.com/GRimAce11/WaveformKit`).

## Running

1. Open `Test Waveform.xcodeproj`
2. Select a simulator or device (iOS 17+)
3. Build & Run

The app generates a test tone locally on first launch — no audio files need to be bundled or downloaded.

The **Microphone** screen requires a physical device and microphone permission.

## Audio

Demo audio is generated on-device using `AVAudioFile` (a swept-frequency tone with a rhythmic envelope). All screens work immediately without network access or external audio files.

To try WaveformKit with your own audio, use the **Pick File** button on the Playback screen.

## Project structure

```
Test Waveform/
├── Test_WaveformApp.swift          @main entry point
├── ContentView.swift               Navigation home screen
├── AudioCatalog.swift              Test tone generator + file cache
├── StyleGalleryScreen.swift        All 6 styles with live controls
├── PlaybackScreen.swift            Full playback demo
├── AsyncLoadingScreen.swift        WaveformState lifecycle
├── MicrophoneRecorderScreen.swift  Live recording + playback
├── CustomRendererScreen.swift      WaveformRenderer protocol examples
└── ViewportScreen.swift            WaveformViewport zoom/pan demo
```

## License

MIT — same as WaveformKit.
