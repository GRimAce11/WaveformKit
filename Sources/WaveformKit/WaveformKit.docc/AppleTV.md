# Apple TV

Use WaveformKit on tvOS 17, seeking with the Siri Remote.

## Overview

tvOS has no touch screen, and SwiftUI's `DragGesture` does not exist there. ``WaveformView``
becomes a focusable control instead, following Apple's guidance to rely on system focus effects
and standard remote behaviour.

```swift
WaveformView(summary: summary, currentTime: player.currentTime,
             onSeek: { player.seek(to: $0) })
    .frame(height: 120)
```

## Seeking

The waveform is focusable only when it has an `onSeek` handler, and it uses the system's
highlight focus effect. While it has focus:

- **Left and right** presses on the clickpad seek by a twentieth of the visible span. Across a
  3-minute track that is about 9 seconds; zoomed in, each press is finer. In right-to-left
  layouts (see <doc:RightToLeft>) left moves later.
- **While zoomed**, the viewport pans just far enough to keep the new playhead position visible.
- **Up and down** are left to the focus engine, so focus can move to the controls above and below.
- **Play/Pause and Back** are never handled: Play/Pause belongs to your player, and Back returns
  to the previous screen.

## What is not available

Scrubbing by drag, pinch zoom, drag-to-pan, marker taps, and region selection all need touch and
are not available on tvOS. Markers and a bound selection still draw. A ``WaveformViewport``
binding can still be zoomed and panned by your own controls with
``WaveformViewport/zoom(to:anchor:minSpan:)`` and ``WaveformViewport/pan(by:)``. VoiceOver's
adjustable seek works as on iOS.

The players, ``AudioDecoder``, ``WaveformCache``, ``AVPlayerAmplitudeTap``, and the Metal backend
work as they do on iOS.
