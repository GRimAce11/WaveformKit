# Getting Started

Draw your first waveform, then wire it to a player.

## Overview

A waveform needs two things: a ``WaveformSummary`` describing the audio, and a current playback
time to draw the playhead at.

### Without an audio file

``WaveformSummary/demo(duration:bars:sampleRate:seed:)`` generates a deterministic,
envelope-shaped summary. It is the fastest way to see something on screen, and it makes previews
and unit tests independent of any bundled media.

```swift
WaveformView(summary: .demo(duration: 30), currentTime: 12, style: .bars(count: 120))
    .frame(height: 80)
```

### From a real file

``WaveformLoader`` is an `@Observable @MainActor` class that owns the decode. Its single
``WaveformLoader/state`` property moves through ``WaveformState`` — `.idle`, `.loading(progress:)`,
`.loaded`, `.failed` — so progress and failure are states you render rather than callbacks you
manage.

```swift
@State private var loader = WaveformLoader()

var body: some View {
    WaveformView(loader: loader, currentTime: adapter.currentTime, onSeek: { adapter.seek(to: $0) })
        .waveformStateOverlay(loader.state)
        .frame(height: 80)
        .task { loader.load(url: url) }
}
```

`WaveformView(loader:)` renders a shimmer placeholder until the summary arrives, so the layout
never jumps. The `waveformStateOverlay(_:)` view modifier adds a progress bar while decoding and
an error view if it fails.

Decoding is cached on disk by file identity, so the second open of the same file resolves
immediately with no progress ticks at all.

### Choosing a player

Three adapters cover the common cases. All conform to ``WaveformPlayerAdapter``:

| Adapter | Local files | Streaming | FFT bands |
|---|---|---|---|
| ``AVPlayerAdapter`` | yes | yes | via ``AVPlayerAmplitudeTap`` |
| ``AVAudioPlayerAdapter`` | yes | no | no |
| ``AVAudioEnginePlayer`` | yes | no | built in |

``AVAudioEnginePlayer`` conforms to both ``WaveformPlayerAdapter`` and ``AmplitudeTap``, so one
object drives the whole view when you want local playback plus a live spectrum.

### Reacting to the audio

Pass an amplitude and frequency bands, then pick a movement mode that uses them:

```swift
WaveformView(
    summary:     summary,
    currentTime: player.currentTime,
    amplitude:   player.currentAmplitude,
    bands:       player.bands,
    style:       .dancingBars(count: 32),
    movement:    .reactive(boost: 1.4)
)
```

## See Also

- <doc:ZoomAndPan>
- <doc:RealtimeSafety>
