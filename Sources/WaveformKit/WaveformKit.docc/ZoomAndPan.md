# Zoom and Pan

Let people pinch into a waveform, and decide what a one-finger drag means.

## Overview

Pass a ``WaveformViewport`` binding and the view becomes zoomable: pinch to zoom, drag to pan,
double-tap to reset. Without a binding there is no zoom state to drive, and the gestures stay
inert — so adding zoom is opt-in and changes nothing for views that do not want it.

```swift
@State private var viewport = WaveformViewport(duration: summary.duration)

WaveformView(
    summary:     summary,
    currentTime: player.currentTime,
    viewport:    $viewport,
    onSeek:      { player.seek(to: $0) }
)
```

A pinch is anchored at the gesture centroid, so the audio under your fingers stays put. Zoom is
clamped by ``WaveformZoomOptions/maxZoomFactor`` and ``WaveformZoomOptions/minVisibleDuration``,
whichever binds first.

### What should a drag do?

Pinch always zooms. The ambiguous input is the one-finger drag — it could mean "scrub" or
"scroll the timeline" — so ``WaveformZoomOptions/DragBehavior`` decides:

- ``WaveformZoomOptions/DragBehavior/seek`` (default): a drag always seeks. Right for players,
  where scrubbing is the primary interaction. Panning is still reachable by pinching off-centre.
- ``WaveformZoomOptions/DragBehavior/panWhenZoomed``: a drag pans while zoomed in and seeks at
  1x. Right for editors, where the waveform reads as a timeline.

Three presets cover most apps:

```swift
.disabled      // no gestures; drive the viewport in code only
.editor        // dragBehavior = .panWhenZoomed
.inScrollView  // vertical drags scroll the enclosing list instead of seeking
```

### Inside a scroll view

A waveform row in a list has a real conflict: a zero-distance drag claims the touch immediately
and the list stops scrolling. ``WaveformZoomOptions/inScrollView`` resolves it by attaching the
gesture simultaneously rather than exclusively, and by withholding any seek or pan until the
touch has travelled ``WaveformZoomOptions/scrollIntentThreshold`` points — at which point a drag
taller than it is wide is abandoned for the rest of the gesture. Taps still seek.

### Double-tap

Double-tapping resets to the full duration. The first tap of the pair still seeks: on a waveform
a tap means "play from here", and suppressing it would mean delaying every tap by the double-tap
interval. Set ``WaveformZoomOptions/resetsOnDoubleTap`` to `false` to turn it off.

### Driving it from code

``WaveformViewport`` is an ordinary value type, so gestures and code move the same state:

```swift
viewport.visibleRange = 95...125                 // jump to a region
viewport.zoom(to: 4, anchor: 0.5)                // 4x, centred
viewport.pan(by: 10)                             // forward ten seconds
viewport.resetZoom()
```

> Note: At high zoom factors the view resamples a slice of the same summary, so detail is bounded
> by the bar count chosen at decode time. Multi-resolution summaries are planned.

## See Also

- ``WaveformViewport``
- ``WaveformZoomOptions``
