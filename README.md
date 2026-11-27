# WaveformKit

**Interactive audio waveforms for SwiftUI.** Point it at an audio file and get a waveform your
users can play, scrub, zoom, mark up and select from — on iPhone, iPad, Mac, Apple Vision Pro,
Apple Watch and Apple TV. Decoding, caching, live FFT and rendering are all included, with zero
external dependencies.

<p align="center">
  <img src=".github/media/waveform-hero.gif" alt="A mirrored-bars waveform reacting to live audio" width="100%" />
</p>

![Swift](https://img.shields.io/badge/Swift-6.0+-orange?logo=swift)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017%20%7C%20macOS%2014%20%7C%20tvOS%2017%20%7C%20visionOS%201%20%7C%20watchOS%2010-blue)
![License](https://img.shields.io/badge/License-MIT-green)
![Tests](https://img.shields.io/badge/Tests-196%20passing-brightgreen)

```swift
@State private var loader = WaveformLoader()

WaveformView(loader: loader, currentTime: player.currentTime, onSeek: { player.seek(to: $0) })
    .waveformStateOverlay(loader.state)
    .frame(height: 80)
    .task { loader.load(url: audioURL) }
```

That is a complete, scrubbable waveform: it decodes the file in the background, shows a shimmer
and progress bar while it works, caches the result on disk, and draws the played portion as
playback moves.

---

## Contents

- [What you get](#what-you-get)
- [Installation](#installation)
- [Getting started](#getting-started)
- [Recipes](#recipes) — voice note · podcast list · live recording · editor timeline
- [Guide](#guide)
  - [Loading audio](#loading-audio)
  - [Styles and colours](#styles-and-colours)
  - [Playback and live audio](#playback-and-live-audio)
  - [Seeking and markers](#seeking-and-markers)
  - [Zoom and pan](#zoom-and-pan)
  - [Region selection](#region-selection)
  - [Recording from the microphone](#recording-from-the-microphone)
  - [Custom renderers](#custom-renderers)
  - [Metal rendering](#metal-rendering)
  - [Disk cache](#disk-cache)
  - [Snapshots and previews](#snapshots-and-previews)
- [Platforms](#platforms) — Apple Watch · Apple TV · right-to-left languages
- [Accessibility](#accessibility)
- [Troubleshooting](#troubleshooting)
- [Known limitations](#known-limitations)
- [How it works](#how-it-works)
- [Roadmap](#roadmap) · [Contributing](#contributing) · [License](#license)

---

## What you get

| | |
|---|---|
| **Six styles** | Bars, mirrored bars, dancing (equalizer) bars, line, dots, circular — or draw your own |
| **Loading built in** | `WaveformLoader` decodes off the main thread with progress, cancel, retry and errors |
| **Interaction** | Tap or drag to seek, pinch to zoom, drag to pan, double-tap to reset — safe inside a `ScrollView` |
| **Editing** | Markers and regions with tap callbacks; a draggable, snappable range selection |
| **Live audio** | Real FFT spectrum bands from `AVPlayer` or `AVAudioEngine`, and a live microphone recorder |
| **Detail when zoomed** | A multi-resolution summary, so zooming in shows real transients instead of stretched blocks |
| **Fast** | Disk cache, resample cache, a realtime-safe audio thread, and an opt-in Metal backend for thousands of bars |
| **Accessible** | VoiceOver seeking, markers and selection editing; right-to-left languages handled |
| **Every Apple platform** | Including Digital Crown zoom on Apple Watch and Siri Remote seeking on Apple TV |
| **No dependencies** | AVFoundation, Accelerate and (outside watchOS) MediaToolbox only. Swift 6 clean |

### Platform support

| | iOS / iPadOS | macOS | visionOS | watchOS | tvOS |
|---|:-:|:-:|:-:|:-:|:-:|
| Decode, cache and draw | ✅ | ✅ | ✅ | ✅ | ✅ |
| Tap and drag to seek | ✅ | ✅ | ✅ | ✅ | Siri Remote |
| Zoom | Pinch | Pinch | Pinch | Digital Crown | Your own controls |
| Markers and selection | ✅ | ✅ | ✅ | ✅ | Display only |
| FFT bands from `AVPlayer` | ✅ | ✅ | ✅ | — | ✅ |
| FFT bands from `AVAudioEngine` | ✅ | ✅ | ✅ | ✅ | ✅ |
| Microphone recording | ✅ | ✅ | ✅ | ✅ | untested |
| Metal backend | ✅ | ✅ | ✅ | — | ✅ |

---

## Installation

**Requirements:** iOS 17 / macOS 14 / tvOS 17 / visionOS 1 / watchOS 10, and Xcode 16 or later
(Swift 6 toolchain).

**In Xcode:** File → Add Package Dependencies… → paste `https://github.com/GRimAce11/WaveformKit.git`.

**In `Package.swift`:**

```swift
dependencies: [
    .package(url: "https://github.com/GRimAce11/WaveformKit.git", from: "0.8.0")
]
```

The package builds cleanly under the Swift 6 language mode. It also declares Swift 5 mode, so it
still compiles if your project pins one — but the toolchain itself must be Swift 6.0 or newer.

**Try the demo first.** Open [`Demo/Test Waveform.xcodeproj`](Demo/) and run it — it uses the
package from this folder, generates its own test tone, and needs no network. It has a screen for
each major feature: style gallery, playback with markers, async loading, microphone, custom
renderers, zoom and pan, and selection (with a right-to-left toggle). The same project has small
**Watch Demo** and **TV Demo** apps for Digital Crown zoom and Siri Remote seeking.

---

## Getting started

### 1. Show a waveform

No audio file yet? `WaveformSummary.demo(...)` makes a realistic one, which is also handy in
previews:

```swift
import SwiftUI
import WaveformKit

struct ContentView: View {
    var body: some View {
        WaveformView(summary: .demo(duration: 30), currentTime: 12)
            .frame(height: 80)
            .padding()
    }
}
```

### 2. Load a real file and play it

`WaveformLoader` decodes the file; `AVPlayerAdapter` publishes the player's position; the
optional `AVPlayerAmplitudeTap` adds live spectrum bands for reactive styles.

```swift
import AVFoundation
import SwiftUI
import WaveformKit

struct PlayerView: View {
    let url: URL

    @State private var loader  = WaveformLoader()
    @State private var adapter = AVPlayerAdapter(player: AVPlayer())
    @State private var tap: AVPlayerAmplitudeTap?

    var body: some View {
        WaveformView(
            loader:      loader,
            currentTime: adapter.currentTime,
            amplitude:   tap?.currentAmplitude ?? 0,
            bands:       tap?.bands ?? [],
            style:       .dancingBars(count: 32),
            movement:    .reactive(boost: 1.4),
            colors:      WaveformColors(played: .accentColor, unplayed: .secondary.opacity(0.25)),
            onSeek:      { adapter.seek(to: $0) }
        )
        .waveformStateOverlay(loader.state)
        .frame(height: 80)
        .task {
            let player = AVPlayer(url: url)
            adapter = AVPlayerAdapter(player: player)
            tap     = AVPlayerAmplitudeTap(player: player, bandCount: 32)
            loader.load(url: url)
            player.play()
        }
    }
}
```

While the file decodes, the view shows a shimmer and `.waveformStateOverlay` adds a progress bar
(and an error view if decoding fails). The second time the same file opens, it comes straight
from the disk cache.

### 3. Make it yours

Change `style:` and `colors:`, add `markers:`, pass a `viewport:` binding to enable zoom, or a
`selection:` binding to let people pick a range. Each is covered in the [Guide](#guide).

---

## Recipes

### Voice note bubble

```swift
WaveformView(
    summary:     note.summary,
    currentTime: player.currentTime,
    style:       .mirroredBars(count: 40, spacing: 2, cornerRadius: 1.5),
    colors:      WaveformColors(played: .white, unplayed: .white.opacity(0.4)),
    onSeek:      { player.seek(to: $0) }
)
.frame(width: 180, height: 32)
```

### Podcast episodes in a list

`.inScrollView` lets vertical drags scroll the list while taps and horizontal drags still seek.
For long lists of rows that never play, a [snapshot](#snapshots-and-previews) is cheaper still.

```swift
List(episodes) { episode in
    WaveformView(
        summary:     episode.summary,
        currentTime: episode.position,
        zoom:        .inScrollView,
        onSeek:      { seek(episode, to: $0) }
    )
    .frame(height: 44)
}
```

### Live recording meter

```swift
@State private var recorder = MicrophoneRecorder(maximumDuration: 60)

WaveformView(
    summary:     recorder.summary,
    currentTime: recorder.currentTime,
    amplitude:   recorder.currentAmplitude,
    bands:       recorder.bands,
    style:       .mirroredBars(count: 80),
    movement:    .reactive(boost: 1.4)
)
.frame(height: 60)
.task { try? await recorder.start() }
```

Add `NSMicrophoneUsageDescription` to your Info.plist. See
[Recording from the microphone](#recording-from-the-microphone).

### Editor timeline: zoom, pan, markers and a selection

```swift
@State private var viewport  = WaveformViewport(duration: summary.duration)
@State private var selection: ClosedRange<TimeInterval>?

WaveformView(
    summary:          summary,
    currentTime:      player.currentTime,
    style:            .bars(count: 300, spacing: 1),
    markers:          chapters,
    viewport:         $viewport,
    zoom:             .editor,          // drag pans while zoomed
    selection:        $selection,
    selectionOptions: .editor,          // drag selects; taps still seek
    onSeek:           { player.seek(to: $0) },
    onMarkerTap:      { player.seek(to: $0.time) }
)
.frame(height: 120)

Button("Trim to selection") { trim(to: selection!) }
    .disabled(selection == nil)
```

---

## Guide

### Loading audio

`WaveformLoader` is an `@Observable` class that runs the decode and exposes one `state`
property for your UI:

```swift
public enum WaveformState {
    case idle
    case loading(progress: Double)   // 0.0 ... 1.0
    case loaded(WaveformSummary)
    case failed(Error)
}
```

`WaveformView(loader:)` and `.waveformStateOverlay(_:)` handle every state for you. To build your
own UI instead, switch on it:

```swift
switch loader.state {
case .idle:                Text("No file selected")
case .loading(let p):      ProgressView(value: p)
case .loaded(let summary): WaveformView(summary: summary, currentTime: 0)
case .failed(let error):   Label(error.localizedDescription, systemImage: "xmark.circle")
}
```

**Controlling a load**

```swift
loader.load(url: fileURL, targetBars: 200, useCache: true)  // cancels any load in progress
loader.cancel()                                             // state → .idle
loader.retry()                                              // after a failure
```

**Summaries you already have** — say, fetched from your server or saved last session — skip
decoding entirely:

```swift
loader.set(savedSummary)

// Or mix decoded and precomputed items through one call:
let source: AudioSource = item.cachedSummary.map(AudioSource.precomputed) ?? .file(item.localURL)
loader.load(source: source)
```

`WaveformSummary` is `Codable`, so it is easy to store or send. For a one-off decode without a
loader: `let summary = try await WaveformLoader.load(url: url, targetBars: 200)`.

### Styles and colours

<p align="center">
  <img src=".github/media/styles.gif" alt="bars, mirroredBars and dancingBars animating under reactive movement" width="660" />
</p>

<p align="center"><em>From the demo app — <code>.bars</code>, <code>.mirroredBars</code> and <code>.dancingBars</code> under <code>.reactive</code> movement.</em></p>

| Style | Looks like | Good for |
|---|---|---|
| `.bars` | Vertical bars rising from the bottom | Podcast and music seek bars |
| `.mirroredBars` | Bars centred on the midline | Voice notes |
| `.dancingBars` | Bouncing equalizer bars | "Now playing" and live audio |
| `.line` | A smooth filled mirrored curve | Minimal, editorial layouts |
| `.dots` | Capsules along the midline | Minimal voice notes |
| `.circular` | Radial bars around a centre | Album-art overlays |

```swift
WaveformView(summary: s, currentTime: t, style: .bars(count: 120))
WaveformView(summary: s, currentTime: t, style: .line(thickness: 1.5))
WaveformView(summary: s, currentTime: t, style: .circular(count: 64))
    .aspectRatio(1, contentMode: .fit)
```

**Movement** — how the bars animate:

| Mode | What it does |
|---|---|
| `.progress` *(default)* | Static waveform with a played / unplayed colour split |
| `.reactive(boost:)` | Bars move with the live amplitude (pass `amplitude:` and `bands:`) |
| `.combined(boost:)` | Progress split *and* live movement on the played part |
| `.idle` | A gentle shimmer, for loading or paused states |

**Colours** — solid or gradient, separately for the played and unplayed parts:

```swift
WaveformColors(
    played:           .pink,
    unplayed:         .gray.opacity(0.25),
    playedGradient:   Gradient(colors: [.pink, .purple]),   // overrides `played`
    unplayedGradient: nil
)
```

Gradients run horizontally on linear styles and around the circle on `.circular`.

**Resample mode** — when a summary has more points than you have bars, each bar stands for
several of them. `.peak` *(default)* keeps the loudest, so drum hits and edits stay visible;
`.mean` averages them for a smoother, flatter look:

```swift
WaveformView(summary: s, currentTime: t, style: .bars(count: 60), resampleMode: .mean)
```

### Playback and live audio

Three adapters publish a player's position for `currentTime:`. Pick by what you play:

| You play… | Use | Live FFT bands |
|---|---|---|
| Streams or local files with `AVPlayer` | `AVPlayerAdapter` + `AVPlayerAmplitudeTap` | ✅ (not on watchOS) |
| Local files, with a spectrum | `AVAudioEnginePlayer` (adapter and tap in one) | ✅ |
| Local files, simply | `AVAudioPlayerAdapter` + `AVAudioPlayerAmplitudeTap` | — amplitude only |

```swift
// AVAudioEnginePlayer drives everything from one object
let player = try AVAudioEnginePlayer(url: url, bandCount: 32)
player.play()

WaveformView(
    summary:     summary,
    currentTime: player.currentTime,
    amplitude:   player.currentAmplitude,
    bands:       player.bands,
    style:       .dancingBars(count: 32),
    movement:    .reactive(),
    onSeek:      { player.seek(to: $0) }
)
```

```swift
// AVPlayer, for streaming
let player  = AVPlayer(url: url)
let adapter = AVPlayerAdapter(player: player)
let tap     = AVPlayerAmplitudeTap(player: player, bandCount: 32)
```

The FFT is a 1024-point, Hann-windowed transform on the audio render thread, with bands spaced
logarithmically from 40 Hz to 16 kHz. `bands` holds `bandCount` values in `0...1`;
`currentAmplitude` is the smoothed level. When there are at least as many bands as bars,
`.dancingBars` drives each bar from its own frequency range.

### Seeking and markers

Pass `onSeek:` and the waveform becomes a seek bar: tap to jump, drag to scrub. Linear styles
seek along the width; `.circular` seeks by angle.

Markers label points or regions of the audio:

```swift
let markers: [WaveformMarker] = [
    WaveformMarker(time: 12,               color: .yellow, label: "Intro"),
    WaveformMarker(time: 48, duration: 22, color: .orange, label: "Verse 1"),
    WaveformMarker(time: 95,               color: .pink,   label: "Drop"),
]

WaveformView(
    summary:     summary,
    currentTime: t,
    markers:     markers,
    onSeek:      { player.seek(to: $0) },
    onMarkerTap: { marker in player.seek(to: marker.time) }
)
```

- A **point marker** (`duration: 0`) draws a line and a dot; a **region** draws a translucent band.
- A tap on a marker calls `onMarkerTap`; a drag always seeks.
- Every style supports markers, and they follow the view when zoomed.

### Zoom and pan

Give the view a `WaveformViewport` binding and it becomes zoomable: pinch to zoom, drag to pan,
double-tap to reset. Without a binding, nothing changes.

```swift
@State private var viewport = WaveformViewport(duration: summary.duration)

WaveformView(summary: summary, currentTime: t, viewport: $viewport, onSeek: { player.seek(to: $0) })
```

The pinch is anchored under your fingers, and zoom stops at `maxZoomFactor` or
`minVisibleDuration`, whichever comes first.

**What should a one-finger drag do?** That depends on your app:

| `zoom:` | Drag at 1× | Drag while zoomed | Best for |
|---|---|---|---|
| default (`.seek`) | seeks | seeks | Players — scrubbing is the point |
| `.editor` (`.panWhenZoomed`) | seeks | pans | Editors — the waveform is a timeline |
| `.inScrollView` | seeks | seeks | Rows in a `List` or `ScrollView` |
| `.disabled` | — | — | Driving the viewport from code only |

Or configure it yourself:

```swift
WaveformZoomOptions(
    dragBehavior:           .panWhenZoomed,
    maxZoomFactor:          20,
    minVisibleDuration:     0.5,
    resetsOnDoubleTap:      true,
    yieldsToVerticalScroll: false
)
```

**Inside a scroll view**, `.inScrollView` waits until a touch has moved a few points: if it is
mostly vertical, the list scrolls; otherwise it seeks. Taps always seek.

**Double-tap** resets to the full view. The first tap of the pair still seeks — delaying every tap
to wait for a possible second one would make the seek bar feel slow.

**From code**, the viewport is a plain value you can change directly:

```swift
viewport.visibleRange = 95...125                                    // show a region (seconds)
viewport.zoom(to: 4, anchor: player.currentTime / summary.duration) // 4×, around the playhead
viewport.pan(by: 10)                                                // forward 10 seconds
viewport.resetZoom()
```

**Detail at high zoom.** A summary normally holds about 200 points — plenty for a full-width bar,
but only ten are left at 20× zoom. So the decoder also builds a `WaveformSummaryPyramid` with
16 384 points (and coarser levels) in the same pass over the file, and the view picks the right
level for every zoom. There is nothing to turn on. To tune it:

```swift
loader.load(url: fileURL, pyramidResolution: 65_536)   // more detail for long files
loader.load(url: fileURL, pyramidResolution: 0)        // no pyramid; smaller cache entries
```

The pyramid adds about 44 KB per file to the disk cache.

### Region selection

Pass a `selection` binding to let people pick a range — to trim a voice note, loop a section or
export a clip. The range is a plain `ClosedRange<TimeInterval>?` that you own.

```swift
@State private var selection: ClosedRange<TimeInterval>?

WaveformView(
    summary:          summary,
    currentTime:      player.currentTime,
    selection:        $selection,
    selectionOptions: .editor,
    onSeek:           { player.seek(to: $0) }
)
```

| Gesture | Result |
|---|---|
| Hold, then drag *(default)* | Creates a selection; a plain drag still seeks |
| Drag *(with `.editor`)* | Creates a selection; taps still seek |
| Drag an edge | Moves that edge (a 44 pt touch target); crossing the other edge swaps them |
| Tap outside | Clears the selection and seeks |

```swift
WaveformSelectionOptions(
    activation:           .longPress(holdDuration: 0.4),   // or .drag
    minimumLength:        0.1,      // shorter drags are discarded
    snapInterval:         0.5,      // snap edges to a 0.5 s grid; nil = free
    clearsOnTapOutside:   true,
    updatesWhileDragging: false,    // write the binding once, on release
    tint:                 .orange   // nil = the played colour
)
```

Use `updatesWhileDragging: false` when a new selection triggers expensive work, such as
restarting a loop. Selection works while zoomed; `.circular` does not support it.

### Recording from the microphone

```swift
@State private var recorder = MicrophoneRecorder(
    bandCount:       32,
    binsPerSecond:   20,
    maximumDuration: 60,
    outputURL:       FileManager.default.temporaryDirectory.appendingPathComponent("memo.caf")
)
```

Call `start()` (it asks for permission), then `pause()`, `resume()` and `stop()`. Bind
`recorder.summary`, `currentTime`, `currentAmplitude` and `bands` to a `WaveformView` as in the
[recipe](#live-recording-meter). With `outputURL` set, the audio is also written to that file.

- Add `NSMicrophoneUsageDescription` to your Info.plist.
- Phone calls and route changes are handled. Pass `autoResumeAfterInterruption: false` to stay
  paused afterwards, or `onInterruption:` to react yourself.
- Memory stays bounded: past `maxBins` (default 4 000) points, neighbouring points are merged, so
  even a 24-hour recording stays under 16 KB.

### Custom renderers

Conform to `WaveformRenderer` to draw anything:

```swift
struct OscilloscopeRenderer: WaveformRenderer {
    func draw(
        context: inout GraphicsContext,
        size: CGSize,
        amplitudes: [Float],
        progress: Double,
        amplitudeScale: CGFloat,
        showsProgress: Bool,
        colors: WaveformColors
    ) {
        guard amplitudes.count > 1 else { return }
        let midY = size.height / 2
        var path = Path()
        path.move(to: CGPoint(x: 0, y: midY))
        for (i, amp) in amplitudes.enumerated() {
            let x = size.width * CGFloat(i) / CGFloat(amplitudes.count - 1)
            let y = midY - CGFloat(amp) * amplitudeScale * midY
            path.addLine(to: CGPoint(x: x, y: y))
        }
        context.stroke(path, with: .color(colors.played), lineWidth: 1.5)
    }
}

WaveformView(summary: summary, currentTime: t,
             style: .custom(renderer: OscilloscopeRenderer(), barCount: 200))
```

Renderers must be `Sendable`. A stateless struct, like this one, is the easy way.

### Metal rendering

`Canvas` is ideal for a seek bar of a hundred bars. An editor timeline showing thousands can opt
into Metal, which draws every bar in one GPU call:

```swift
WaveformView(summary: summary, currentTime: t, style: .bars(count: 2_000, spacing: 0))
    .waveformRenderingBackend(.automatic())   // Metal at 512+ bars, Canvas below
```

| Backend | `.bars` and `.mirroredBars` draw with |
|---|---|
| `.canvas` *(default)* | `Canvas` |
| `.metal` | Metal, at any bar count |
| `.automatic(minimumBarCount: 512)` | Metal at or above the threshold |

Other styles always use `Canvas`. If Metal is unavailable — or for the first few milliseconds
while its shader compiles — the view quietly uses `Canvas`, so it is never blank. Your project
needs no Metal toolchain. At very high bar counts, pass `spacing: 0` so the bars fit.

### Disk cache

`WaveformLoader` caches every decode in `~/Library/Caches/WaveformKit/`, keyed by the file's name,
size and modification date plus the decode settings. Change the file and it decodes again.

```swift
WaveformCache.remove(url: url, targetBars: 200)   // forget one file
WaveformCache.clear()                             // forget everything

WaveformCache.configuration = WaveformCache.Configuration(maximumBytes: 4 * 1024 * 1024)
let bytes = WaveformCache.currentByteSize        // for a "Clear cache (12.4 MB)" row
```

The default budget is 32 MB — about 700 files. The least recently used entries go first, and a
file you open often outlives a one-off import. `.unbounded` turns eviction off.

### Snapshots and previews

Render a waveform to an image for thumbnails, share sheets or long lists:

```swift
if let cg = WaveformView.snapshot(
    summary: summary,
    size:    CGSize(width: 300, height: 60),
    style:   .mirroredBars(count: 80),
    colors:  WaveformColors(played: .accentColor)
) {
    let image = UIImage(cgImage: cg)   // NSImage(cgImage:size:) on macOS
}
```

In Xcode previews, `.demo(duration:bars:seed:)` gives you a deterministic waveform with no audio
file:

```swift
#Preview {
    WaveformView(summary: .demo(duration: 30, bars: 120), currentTime: 12)
        .frame(height: 80)
        .padding()
}
```

---

## Platforms

### Apple Watch

Everything above works on watchOS 10 and later, with these differences:

- **Zoom with the Digital Crown.** Tap the waveform to focus it, then turn the crown: each step
  doubles or halves the zoom, with the usual crown haptics. Double-tap still resets. In a list
  (`zoom: .inScrollView`) the crown keeps scrolling the list instead. Apple asks that crown
  actions also have a touch equivalent, so add zoom buttons that change the `viewport` if zooming
  matters in your app.
- **Audio files decode; movies don't.** WAV, AIFF, CAF, M4A, MP3 and similar files decode as on
  iPhone. The audio track inside a movie file throws `AudioDecoderError.readerInitFailed`.
- **No `AVPlayerAmplitudeTap`.** For spectrum bands, play local files with `AVAudioEnginePlayer`.
- **No Metal.** Bars always draw with `Canvas`.
- **Recording** needs `NSMicrophoneUsageDescription` in the watch app's Info.plist.

### Apple TV

On tvOS 17 and later there is no touch screen, so the waveform becomes a focusable control for the
Siri Remote:

- It takes focus with the system highlight effect — but only when you pass `onSeek:`, so a
  display-only waveform never traps focus.
- **Left and right** on the clickpad seek by a twentieth of what is on screen — about 9 seconds
  across a 3-minute track, and finer when zoomed. A zoomed view pans to keep the playhead in sight.
- **Up, down, Play/Pause and Back** are left to the system, as Apple's guidelines ask.
- Drag scrubbing, pinch, drag-to-pan, marker taps and selection need touch, so they are not
  available. Markers and selections still draw, and your own buttons can zoom and pan the
  `viewport`.

### Right-to-left languages

In Arabic, Hebrew and other right-to-left layouts, time runs from right to left by default — the
way Apple's guidelines ask progress controls such as sliders to flip. Bars, colours, seeking,
panning, the pinch anchor, markers, selection and VoiceOver positions all flip together. Text and
digits are never mirrored, and `.circular` always runs clockwise.

To keep time left to right in every language — a DAW-style editor, say:

```swift
WaveformView(summary: summary, currentTime: t)
    .waveformTimelineDirection(.leftToRight)   // .automatic (default) / .leftToRight / .rightToLeft
```

`WaveformView.snapshot` has no environment to read, so pass `layoutDirection: .rightToLeft` when
rendering one for a right-to-left UI.

---

## Accessibility

- **VoiceOver** reads the waveform as one adjustable element — *"0:42 of 3:14"* — and swiping up
  or down seeks by 5 % through `onSeek`.
- **Markers** are their own elements: *"Intro, at 0:12"*, *"Verse, 0:48 to 1:10"*. Reuse the
  phrasing with `WaveformView.markerAccessibilityLabel(for:)`.
- **Selection** can be made and edited without sight: a *Select from playhead* action, adjustable
  *Selection start* and *Selection end* elements, and *Clear selection*.
- **Right-to-left** layouts are handled for you (see above), and VoiceOver always visits markers
  in time order.

---

## Troubleshooting

**The waveform stays a flat shimmer.** The loader has not reached `.loaded`. Check
`loader.state` — a `.failed` error tells you why. The decoder and cache expect a local file URL,
so download remote audio first and load the downloaded file.

**The playhead doesn't move.** `currentTime:` must change as playback moves. Use one of the
[adapters](#playback-and-live-audio) — a raw `AVPlayer.currentTime()` is not observable.

**Dancing bars barely move.** They need live data: pass `amplitude:` and `bands:` from an
amplitude tap or `AVAudioEnginePlayer`, and use `.reactive` or `.combined` movement.
`AVAudioPlayerAmplitudeTap` gives amplitude only, never bands.

**My list won't scroll over the waveforms.** Use `zoom: .inScrollView` on the rows.

**Bars look different after upgrading to 0.7.0.** Summaries now include the high-zoom pyramid,
which changes 1× bars slightly. Load with `pyramidResolution: 0` for the 0.6.0 look.

**Recording fails straight away.** Add `NSMicrophoneUsageDescription` to Info.plist, and check
`recorder.lastError`.

---

## Known limitations

- **`AVAudioPlayer` has no spectrum** — `AVAudioPlayerAmplitudeTap.bands` is always empty. Use
  `AVAudioEnginePlayer` for local files with bands.
- **Unusual PCM formats** — the live taps read `Float32` and `Int16` audio. `Int24`, `Int32` and
  big-endian streams read as silence.
- **iOS 17 / macOS 14 minimum** — the package uses `@Observable`. An iOS 16 backport is not
  scheduled.
- **Swift 6 toolchain required** — Xcode 15 cannot resolve the package. The language *mode* is
  still your choice.
- **watchOS and tvOS differ** — see [Apple Watch](#apple-watch) and [Apple TV](#apple-tv).
- **Very long recordings lose old detail** — `MicrophoneRecorder` merges points past `maxBins`,
  so the oldest parts of a long take get coarser.
- **Zoom detail has a ceiling** — past about 80× (for 200 bars at the default pyramid), bars repeat
  rather than showing more. Raise `pyramidResolution` for long files you zoom deeply. Summaries
  without a pyramid (recordings, `demo(...)`, server JSON that omits it) stretch instead.
- **Metal covers bar styles only** — other styles always use `Canvas`. Display P3 colours render
  as their nearest sRGB value on the Metal path.
- **Custom renderers flip as a whole in right-to-left layouts** — any text they draw reads
  backwards. Draw labels in an overlay, or pin `.waveformTimelineDirection(.leftToRight)`.
- **Selection does not auto-scroll** — while zoomed, an edge stops at the edge of the view. Pan
  or zoom out to go further.
- **Pinch on `.circular`** anchors horizontally, which is arbitrary on a circle. It works, but it
  is not the intended pairing.

---

## How it works

```
┌───────────────────────────────────────────────────────────────────┐
│  Decoding + Caching                                               │
│                                                                   │
│  AudioDecoder (AVAssetReader, or AVAudioFile on watchOS)          │
│      └──► WaveformSummary (amplitudes + pyramid, duration, …)     │
│               └──► WaveformCache (disk, file-identity key)        │
│                         │                                         │
│                  WaveformLoader (@Observable, async, cancellable) │
│                         └──► WaveformState                        │
└─────────────────────────────────┬─────────────────────────────────┘
                                  │
┌─────────────────────────────────▼─────────────────────────────────┐
│  Rendering                                                        │
│                                                                   │
│  WaveformView                                                     │
│      ◄── WaveformSummary                                          │
│      ◄── PlayerAdapter.currentTime  (30 Hz, @Observable)          │
│      ◄── AmplitudeTap.currentAmplitude + .bands                   │
│      ◄── WaveformViewport? (visible time range)                   │
│                                                                   │
│  ResampleCache (keyed by summary + bar count + visible slice)     │
│  WaveformRenderer → 6 built-in styles + .custom · Canvas or Metal │
└─────────────────────────────────┬─────────────────────────────────┘
                                  │
┌─────────────────────────────────▼─────────────────────────────────┐
│  Realtime Audio Pipeline                                          │
│                                                                   │
│  MTAudioProcessingTap / AVAudioEngine installTap (render thread)  │
│      └──► FFTAnalyzer (1024-pt vDSP, ring buffer, zero allocs)    │
│               └──► AmplitudeTapStorage                            │
│                     ├── bandScratch (audio thread only)           │
│                     └── os_unfair_lock → bands (main thread)      │
└───────────────────────────────────────────────────────────────────┘
```

- **Decoding** reads the file once, computing RMS levels with `vDSP_rmsqv` for the bars and the
  pyramid in the same pass, then caches the result. Later opens skip decoding.
- **Rendering** resamples once per summary, bar count and visible slice, and caches it, so the
  30–60 Hz redraws of reactive styles are a dictionary lookup.
- **The audio thread** never allocates. FFT buffers are allocated up front, copies use
  `memmove`-level pointer operations, and the only lock is held for a copy of the band values
  (about 20 ns for 32 bands).

Measured on Apple Silicon (macOS 14, Release, 10 000 iterations), and checked by the test suite:

| Operation | Measured | Budget |
|---|---|---|
| `FFTAnalyzer.computeBands` (1024-pt, 32 bands) | **6.4 µs** | < 200 µs |
| `FFTAnalyzer.push` (512 frames) | **0.20 µs** | < 20 µs |

At 44.1 kHz with 1024-frame buffers, that is under 0.03 % of the audio thread's time.

---

## Roadmap

- ✅ **Phase 3 — 0.6.0:** zoom and pan gestures, Swift 6 language mode, LRU caches, DocC, visionOS.
- ✅ **Phase 4 — 0.7.0:** multi-resolution pyramid for detail at high zoom; opt-in Metal backend.
  Deferred: a Metal spectrogram and 120 Hz `.dancingBars`.
- ✅ **Phase 5 — 0.7.0 and 0.8.0:** editor-grade tooling and every Apple platform
  - ✅ Region selection, with markers that follow the zoomed view
  - ✅ Right-to-left timelines
  - ✅ watchOS, with Digital Crown zoom
  - ✅ tvOS, with Siri Remote seeking
  - Not scheduled: an iOS 16 backport (`ObservableObject`)

Release-by-release detail is in the [changelog](CHANGELOG.md).

---

## Contributing

Bug reports, ideas and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). Full API
documentation is hosted on the Swift Package Index.

## License

[MIT](LICENSE)
