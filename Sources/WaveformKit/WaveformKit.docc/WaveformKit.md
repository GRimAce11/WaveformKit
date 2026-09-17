# ``WaveformKit``

Interactive audio waveforms for SwiftUI — decoding, caching, FFT analysis, and rendering in one
package, with no external dependencies.

## Overview

WaveformKit covers the whole path from an audio file to a waveform your users can scrub, zoom,
and annotate. The pieces fit together in three layers:

- **Decoding** — ``AudioDecoder`` reads a file once and reduces it to a ``WaveformSummary``:
  a few hundred amplitude values instead of millions of samples. ``WaveformCache`` persists that
  summary so the second open is instant.
- **Rendering** — ``WaveformView`` draws the summary in one of six built-in styles, or any style
  you supply through ``WaveformRenderer``. Seeking, markers, zoom, and VoiceOver come with it.
- **Live audio** — ``AmplitudeTap`` implementations run an FFT on the audio render thread with no
  heap allocation, so reactive styles bounce in time with the sound.

The recommended entry point is ``WaveformLoader`` paired with ``WaveformView``, which gives you
the loading, progress, and error states for free:

```swift
@State private var loader = WaveformLoader()

WaveformView(loader: loader, currentTime: player.currentTime, onSeek: { player.seek(to: $0) })
    .waveformStateOverlay(loader.state)
    .frame(height: 80)
    .task { loader.load(url: url) }
```

## Topics

### Essentials

- <doc:GettingStarted>
- ``WaveformView``
- ``WaveformLoader``
- ``WaveformState``
- ``WaveformSummary``

### Appearance

- ``WaveformStyle``
- ``WaveformMovement``
- ``WaveformColors``
- ``WaveformResampleMode``
- ``WaveformRenderer``

### Zoom and Pan

- <doc:ZoomAndPan>
- ``WaveformViewport``
- ``WaveformZoomOptions``

### Markers

- ``WaveformMarker``

### Decoding and Caching

- ``AudioDecoder``
- ``AudioSource``
- ``WaveformCache``
- ``AudioDecoderError``

### Playback

- ``WaveformPlayerAdapter``
- ``AVPlayerAdapter``
- ``AVAudioPlayerAdapter``
- ``AVAudioEnginePlayer``
- ``AVAudioEnginePlayerError``

### Live Audio

- <doc:RealtimeSafety>
- ``AmplitudeTap``
- ``AVPlayerAmplitudeTap``
- ``AVAudioPlayerAmplitudeTap``
- ``MicrophoneRecorder``
- ``MicrophoneRecorderError``
- ``AudioInterruption``
