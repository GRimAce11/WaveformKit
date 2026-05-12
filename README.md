# WaveformKit

A SwiftUI waveform component for music players — six built-in styles, live amplitude reactivity, FFT spectrum bands, and a built-in seek control. Works with both `AVPlayer` and `AVAudioPlayer`.

![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017%20%7C%20macOS%2014-blue)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

- **Six wave styles** — bars, mirrored bars, dancing bars, line, dots, circular
- **Built-in seek control** — drag-anywhere on linear styles, angular scrubbing on circular
- **Reactive to playback** — bars dance with live amplitude or real FFT bands
- **Works with both players** — `AVPlayer` (streaming + local) and `AVAudioPlayer` (local) via adapters
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
| `.idle` | Reserved for shimmer effects (currently behaves like `.progress`) |

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

- `MTAudioProcessingTap` assumes Float32 PCM. Exotic codecs may need a `prepare` callback to negotiate format (planned).
- `.idle` movement is declared but currently behaves like `.progress`. Shimmer effects are TBD.
- `AVAudioPlayer` cannot produce FFT bands (Apple limitation, not a WaveformKit one).
- No live-mic input mode yet — file playback only. Planned via `AVAudioEngine` tap.

## License

[MIT](LICENSE).
