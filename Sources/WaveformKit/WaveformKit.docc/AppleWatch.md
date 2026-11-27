# Apple Watch

Use WaveformKit in a watchOS 10 app, with the Digital Crown for zoom.

## Overview

The package builds for watchOS 10 and later. ``WaveformView``, ``WaveformLoader``,
``WaveformCache``, ``AVAudioEnginePlayer``, ``AVAudioPlayerAdapter``, ``AVPlayerAdapter`` and
``MicrophoneRecorder`` are the same code as on iOS. A few things differ because watchOS lacks
the frameworks they rely on, or the input they expect.

## Zooming with the Digital Crown

A watch has no pinch, so ``WaveformView`` zooms with the Digital Crown instead. Tap the waveform
to give it focus, then turn the crown: each step doubles or halves the zoom about the centre of
the visible range, up to ``WaveformZoomOptions/maxZoomFactor``, with the system's crown haptics.
Double-tap still resets, and drags still seek or pan as ``WaveformZoomOptions/dragBehavior`` says.

```swift
WaveformView(summary: summary, currentTime: player.currentTime,
             viewport: $viewport, zoom: .editor,
             onSeek: { player.seek(to: $0) })
```

Since watchOS 10 the crown is the main way to scroll and navigate, so with
``WaveformZoomOptions/inScrollView`` (``WaveformZoomOptions/yieldsToVerticalScroll``) the waveform
leaves the crown to the list. Apple's guidelines also ask that crown interactions have a touch
equivalent: if zooming in matters to your app, add buttons that change the `viewport` binding
with ``WaveformViewport/zoom(to:anchor:minSpan:)``.

## Decoding

`AVAssetReader` does not exist on watchOS, so ``AudioDecoder`` reads with `AVAudioFile` there.
Audio files — WAV, AIFF, CAF, M4A, MP3 and the like — decode to the same bars and
``WaveformSummaryPyramid`` as on iOS. The audio track of a movie file cannot be read and throws
``AudioDecoderError/readerInitFailed``.

## What is not available

- ``AVPlayerAmplitudeTap`` needs `MTAudioProcessingTap` from MediaToolbox, which watchOS does not
  have. For FFT bands on the watch, play local files with ``AVAudioEnginePlayer``.
- The Metal backend needs MetalKit. Bars always draw with `Canvas`, and
  ``WaveformRenderingBackend/metal`` has no effect.

## Recording

``MicrophoneRecorder`` asks for record permission and sets up a `.playAndRecord` session, as on
iOS, but with the system's default routing: `.defaultToSpeaker` is unavailable on watchOS. Add
`NSMicrophoneUsageDescription` to the watch app's Info.plist.
