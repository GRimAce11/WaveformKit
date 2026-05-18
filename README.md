# WaveformKit

A SwiftUI waveform component for music players — six built-in styles, live amplitude reactivity, FFT spectrum bands, and a built-in seek control. Works with both `AVPlayer` and `AVAudioPlayer`.

![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017%20%7C%20macOS%2014-blue)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

- **Six wave styles** — bars, mirrored bars, dancing bars, line, dots, circular
- **Built-in seek control** — drag-anywhere on linear styles, angular scrubbing on circular
- **Reactive to playback** — bars dance with live amplitude or real FFT bands
- **Markers & regions** — overlay chapters / comments / clip regions with tap-to-jump callbacks (works on all six styles, including `.circular`)
- **Live mic recording** — `MicrophoneRecorder` drives the same view API for voice-memo UIs
- **Three player paths** — `AVPlayer` (streaming + local), `AVAudioPlayer` (local, simple), `AVAudioEnginePlayer` (local + FFT bands)
- **Accessibility** — VoiceOver swipe-to-scrub with formatted time announcement
- **Snapshot to image** — render any waveform configuration to a `CGImage` for thumbnails / share sheets
- **Loading skeleton** — `.idle` movement animates a shimmer (with a placeholder shape if no summary loaded)
- **Color customization** — solid colors or gradients, played / unplayed split
- **Disk cache** — repeat opens of the same file are instant
- **SwiftUI native** — `@Observable`, `Canvas` + `TimelineView`, no UIKit dependency
- **Zero external dependencies** — pure Swift + Apple frameworks (AVFoundation, MediaToolbox, Accelerate)

## Requirements

- iOS 17.0+ / macOS 14.0+
- Swift 5.9+
- Xcode 15+

## Installation

### Swift Package Manager

In Xcode: **File → Add Package Dependencies →** enter

```
https://github.com/GRimAce11/WaveformKit.git
```

Or in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/GRimAce11/WaveformKit.git", from: "0.1.0")
]
```

## Quick start

```swift
import SwiftUI
import AVFoundation
import WaveformKit

struct PlayerView: View {
    let url: URL

    @State private var summary: WaveformSummary = .empty
    @State private var adapter: AVPlayerAdapter?
    @State private var tap: AVPlayerAmplitudeTap?

    var body: some View {
        WaveformView(
            summary: summary,
            currentTime: adapter?.currentTime ?? 0,
            amplitude: tap?.currentAmplitude ?? 0,
            bands: tap?.bands ?? [],
            style: .dancingBars(count: 32),
            movement: .reactive(boost: 1.4),
            colors: WaveformColors(
                played: .pink,
                playedGradient: Gradient(colors: [.pink, .purple])
            ),
            onSeek: { adapter?.seek(to: $0) }
        )
        .frame(height: 100)
        .task {
            summary = (try? await WaveformLoader.load(url: url)) ?? .empty
            let player = AVPlayer(url: url)
            adapter = AVPlayerAdapter(player: player)
            tap = AVPlayerAmplitudeTap(player: player)
        }
    }
}
```

## Wave styles

| Style | Look | Use case |
|---|---|---|
| `.bars` | Vertical bars from bottom | SoundCloud / podcast seeker |
| `.mirroredBars` | Bars centered on midline | WhatsApp / iMessage voice notes |
| `.dancingBars` | Bouncing equalizer | "Now Playing" widgets |
| `.line` | Filled mirrored curve | Minimal / elegant |
| `.dots` | Capsule dots on midline | Voice-note minimal |
| `.circular` | Radial bars around a center | Album-art overlay, AirPods-style |

```swift
// Static bars seeker
WaveformView(summary: summary, currentTime: t, style: .bars())

// Voice-note look
WaveformView(summary: summary, currentTime: t, style: .mirroredBars())

// Live equalizer
WaveformView(summary: summary, currentTime: t, amplitude: a, bands: b,
             style: .dancingBars(count: 32), movement: .reactive())

// Filled curve
WaveformView(summary: summary, currentTime: t, style: .line(thickness: 2))

// Dots
WaveformView(summary: summary, currentTime: t, style: .dots(count: 60))

// Circular — view should be square
WaveformView(summary: summary, currentTime: t, style: .circular(count: 64))
    .aspectRatio(1, contentMode: .fit)
```

## Movement modes

| Mode | Behavior |
|---|---|
| `.progress` | Static waveform; played portion colored differently |
| `.reactive(boost:)` | Bars scale by `1 + boost * amplitude`; no progress fill |
| `.combined(boost:)` | Progress fill **and** amplitude scaling on the played portion |
| `.idle` | Ping-pong shimmer (played color sweeps across) — for loading skeletons or "loaded but not playing" states. Renders a placeholder shape if `summary` is empty. |

### Loading skeleton

```swift
// While the summary is decoding, show an animated shimmer of the same dimensions.
WaveformView(
    summary: summary,                       // .empty is fine — placeholder renders
    currentTime: 0,
    style: .bars(count: 80),
    movement: .idle,
    colors: WaveformColors(played: .accentColor, unplayed: .gray.opacity(0.2))
)
.frame(height: 60)
```

## Players

WaveformKit ships adapters for both Apple players. Same API, swap the adapter:

```swift
// AVAudioPlayer — for local files, simpler API
let player = try AVAudioPlayer(contentsOf: url)
player.prepareToPlay()
let adapter = AVAudioPlayerAdapter(player: player)
let tap = AVAudioPlayerAmplitudeTap(player: player)

// AVPlayer — streaming, local, or remote
let player = AVPlayer(url: url)
let adapter = AVPlayerAdapter(player: player)
let tap = AVPlayerAmplitudeTap(player: player, bandCount: 32)
```

Both adapters are `@Observable` — reading `adapter.currentTime` in your view body automatically re-renders on every playback tick.

## Markers & regions

Annotate the waveform with point markers (chapters, bookmarks, comments) or region overlays
(chorus segments, voiceover ranges, edit clips). Both ride on top of any linear style without
changing the renderer, and tapping a marker fires a typed callback distinct from `onSeek`.

```swift
let chapters: [WaveformMarker] = [
    WaveformMarker(time: 12,                color: .yellow,            label: "Intro"),
    WaveformMarker(time: 48, duration: 22,  color: .orange,            label: "Verse 1"),
    WaveformMarker(time: 95,                color: .pink,              label: "Drop"),
]

WaveformView(
    summary: summary,
    currentTime: t,
    style: .mirroredBars(count: 120),
    markers: chapters,
    onSeek:      { player.seek(to: $0) },
    onMarkerTap: { marker in player.seek(to: marker.time) }
)
```

**Behavior**

- **Point markers** (`duration: 0`) render as a vertical line + filled dot at the top. Tap → fire `onMarkerTap` with that marker.
- **Region markers** (`duration > 0`) render as a translucent tinted band with an edge stripe. Tap inside or near the edge → fire `onMarkerTap`.
- **Tap on empty waveform** → seeks to that position (the existing immediate-scrub gesture is preserved).
- **Drag** → always seeks; the marker tap only fires when the user releases without dragging.
- **`onMarkerTap` is optional** — leave it `nil` and markers behave as decoration; the seek gesture treats them as ordinary waveform pixels.

Markers render on all six styles. For `.circular`, point markers become radial ticks + dots near
the outer edge and region markers become colored arcs along the bar layer. Hit-testing uses arc
length so the same `hitRadius` feels consistent between linear and circular.

## Recording from the microphone

`MicrophoneRecorder` captures from `AVAudioEngine.inputNode` and drives the same `WaveformView`
inputs as the file adapters — so a voice-memo recording UI is the same view code as a player UI.

```swift
import WaveformKit

@State private var recorder = MicrophoneRecorder(
    bandCount: 32,
    binsPerSecond: 20,                                // waveform resolution while recording
    maximumDuration: 60,                              // auto-stop after 60s (optional)
    outputURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("memo.caf")           // omit to keep recording in-memory only
)

var body: some View {
    VStack {
        WaveformView(
            summary: recorder.summary,                // grows as the recording progresses
            currentTime: recorder.currentTime,
            amplitude: recorder.currentAmplitude,
            bands: recorder.bands,
            style: .mirroredBars(count: 80),
            movement: .reactive(boost: 1.4),
            colors: WaveformColors(played: .red)
        )
        .frame(height: 60)

        HStack {
            Button(recorder.isRecording ? "Stop" : "Record") {
                if recorder.isRecording {
                    recorder.stop()
                } else {
                    Task { try? await recorder.start() }
                }
            }
            if recorder.isRecording {
                Button(recorder.isPaused ? "Resume" : "Pause") {
                    recorder.isPaused ? recorder.resume() : recorder.pause()
                }
            }
        }
    }
}
```

After `stop()`, `recorder.recordedFileURL` points at the captured file (if `outputURL` was set),
and `recorder.summary` holds the final amplitude bins for playback-time scrubbing.

### Setup checklist

- **Info.plist** — add `NSMicrophoneUsageDescription` with a user-facing reason. Without it, iOS
  will reject the permission prompt and `start()` throws `.permissionDenied`.
- **iOS audio session** — `start()` configures `.playAndRecord` / `.measurement` with
  `.defaultToSpeaker` and `.allowBluetooth`. `stop()` deactivates the session. If your app already
  manages `AVAudioSession` globally, configure it before calling `start()` and the recorder will
  reuse the running configuration.
- **macOS entitlements** — sandboxed macOS apps need the Audio Input entitlement
  (`com.apple.security.device.audio-input`).
- **Background recording** — for capture that continues when the screen locks or the app is
  backgrounded, add the `audio` value to your `UIBackgroundModes` array in Info.plist. Without
  it, iOS suspends the engine on lock and `MicrophoneRecorder.isRecording` stays true while no
  samples flow — a silent failure.

### Error handling

```swift
do {
    try await recorder.start()
} catch MicrophoneRecorderError.permissionDenied {
    // Show "Enable microphone in Settings"
} catch MicrophoneRecorderError.engineStartFailed(let err) {
    // Hardware unavailable, route conflict, etc.
} catch {
    // .audioSessionFailed, .fileCreationFailed, .alreadyRecording
}
```

`recorder.lastError` carries the most recent failure for observation-driven UIs.

### Interruptions & route changes

Phone calls, Siri, alarms, and headphone changes are handled automatically. The recorder syncs
`isPaused` when the OS pauses capture, fires `onInterruption` with the event, and (by default)
auto-resumes if iOS hints `shouldResume`.

```swift
let recorder = MicrophoneRecorder(
    autoResumeAfterInterruption: true,           // default; flip to keep paused after the call
    onInterruption: { event in
        switch event {
        case .began:
            // UI: show "Paused — interrupted by phone call"
        case .ended(let shouldResume):
            // The recorder already auto-resumed if shouldResume && autoResumeAfterInterruption.
            break
        case .audioRouteChanged(let reason):
            if reason == .oldDeviceUnavailable {
                // Headphones unplugged — many voice apps pause here.
                recorder.pause()
            }
        }
    }
)
```

## Local-file playback with FFT — `AVAudioEnginePlayer`

`AVAudioPlayer` can't expose PCM so it can't produce FFT spectrum bands. `AVPlayer` works but is
heavy and streaming-oriented. For the common case — a local audio file with live spectrum bars —
use `AVAudioEnginePlayer`, which conforms to **both** `WaveformPlayerAdapter` (time/seek/play)
and `AmplitudeTap` (amplitude/bands) so one object drives the view:

```swift
let player = try AVAudioEnginePlayer(url: url, bandCount: 32)
player.play()

WaveformView(
    summary: summary,
    currentTime: player.currentTime,
    amplitude: player.currentAmplitude,
    bands: player.bands,
    style: .dancingBars(count: 32),
    movement: .reactive(),
    onSeek: { player.seek(to: $0) }
)
```

Seek works by stopping the player node, scheduling a segment from the new frame, and resuming —
the same pattern any `AVAudioEngine`-based player uses.

## Snapshot to image

```swift
if let cgImage = WaveformView.snapshot(
    summary: summary,
    size: CGSize(width: 300, height: 60),
    style: .mirroredBars(count: 80),
    colors: WaveformColors(played: .accentColor)
) {
    let uiImage = UIImage(cgImage: cgImage)            // iOS / tvOS / visionOS
    // let nsImage = NSImage(cgImage: cgImage, size: CGSize(width: 300, height: 60))  // macOS
}
```

Useful for voice-memo thumbnails, cell-list previews (avoid running a live `Canvas` per row), and
share-sheet images.

## Accessibility

`WaveformView` is a single adjustable element for VoiceOver. The value is announced as
`"0:42 of 3:14"`; swipe up/down moves by 5 % of duration and routes through `onSeek`. Marker count
is appended to the label when markers are present. Nothing to wire — it's on by default.

## Loading skeleton & previews

```swift
#Preview {
    WaveformView(
        summary: .demo(duration: 30),
        currentTime: 12,
        style: .bars(count: 120)
    )
    .frame(height: 80)
    .padding()
}
```

`WaveformSummary.demo(duration:bars:seed:)` produces an envelope-shaped sample summary so previews
and screenshots render meaningful content without a real audio file.

## FFT spectrum bands

`AVPlayerAmplitudeTap` runs a real-time FFT (vDSP, 1024-point, Hann-windowed) on the audio render thread and exposes logarithmically-spaced frequency bands.

```swift
let tap = AVPlayerAmplitudeTap(player: player, bandCount: 32)

WaveformView(
    // …
    bands: tap.bands,
    style: .dancingBars(count: 32)
)
```

When `bands.count >= count`, `.dancingBars` becomes a true spectrum analyzer — each bar reflects its own frequency range.

> **Limitation:** `AVAudioPlayerAmplitudeTap.bands` is always empty. `AVAudioPlayer` only reports per-channel power, not PCM, so an FFT isn't possible from that path. The dancing bars renderer falls back to phase-offset amplitude wobble — still visually convincing.

## Disk cache

`WaveformLoader.load(url:)` checks the on-disk cache before decoding, so repeat opens of the same file are instant.

```swift
let summary = try await WaveformLoader.load(url: url, targetBars: 200)
```

Cache key = filename + size + mtime + bar count + format version. Stored in `Caches/WaveformKit/`. No content hashing — fast lookup, scoped to a single file revision.

```swift
WaveformCache.clear()                                  // nuke all
WaveformCache.remove(url: url, targetBars: 200)        // single entry
```

## Color customization

```swift
WaveformColors(
    played: .pink,
    unplayed: .gray.opacity(0.3),
    playedGradient: Gradient(colors: [.pink, .purple])
)
```

`playedGradient` overrides `played` when set. Same for `unplayedGradient`.

## Architecture

```
AudioSource ──┐
              ▼
        AudioDecoder ──► WaveformSummary ──┐
              │ (cached via WaveformCache)   │
                                            ▼
                                      WaveformView
                                            ▲
                                            │
              PlayerAdapter ─► currentTime ─┤
                                            │
              AmplitudeTap  ─► amplitude  ──┤
                              + bands ──────┘
                                (FFT, AVPlayer path only)
```

- Decoder: `AVAssetReader` + `vDSP_rmsqv` for per-bar RMS reduction.
- AVPlayer amplitude tap: `MTAudioProcessingTap` on the audio render thread; `vDSP_fft_zrip` for spectrum.
- AVAudioPlayer amplitude tap: `isMeteringEnabled` + `averagePower(forChannel:)` polled at 30 Hz.
- Visuals: SwiftUI `Canvas` for all six renderers, `TimelineView` for `.dancingBars` 60 fps updates. No Metal, no `UIViewRepresentable`.

## Known limitations

- `AVAudioPlayer` cannot produce FFT bands (Apple limitation). Use `AVAudioEnginePlayer` for the
  local-file + FFT combination.
- `AVPlayerAmplitudeTap` falls back gracefully on `Float32` and `Int16` PCM. Less common sample
  formats (Int24, Int32, big-endian variants) are skipped — bands/amplitude will read 0.
- iOS 17+ / macOS 14+ floor (the `@Observable` macro). An iOS 16 backport is on the roadmap.
- Long recordings: `MicrophoneRecorder` halves the bar array when it exceeds `maxBins` (default
  4000). Memory is bounded; temporal resolution on older parts of the recording degrades after
  each halving cycle.

## License

[MIT](LICENSE).
