# Right-to-Left Languages

Run time from right to left in Arabic, Hebrew, and other right-to-left layouts.

## Overview

Apple's Human Interface Guidelines ask apps to flip controls that show progress from one value to
another in right-to-left languages, as sliders and progress indicators do. A waveform seek bar is
one of those controls, so by default ``WaveformView`` follows the layout direction: in a
right-to-left layout the audio starts at the right edge and plays towards the left.

No code is needed for that. ``WaveformTimelineDirection/automatic`` is the default.

## What flips

Everything that maps time to a horizontal position flips together:

- the bars, with their played colouring and any gradient;
- tap and drag to seek;
- drag to pan — the audio still follows the finger;
- the pinch-to-zoom anchor;
- markers and region markers, and their hit-testing;
- the selection and its edge handles;
- the on-screen positions of VoiceOver elements.

Marker labels move to the other side of their marker but are never mirrored. VoiceOver visits
markers and selection edges in time order, whichever way time runs on screen. Digits in time
labels are never reversed.

## What does not

The `.circular` style always runs clockwise from the top. The guidelines treat clock faces as the
same in every language, and a progress ring reads as one.

A custom ``WaveformRenderer`` is mirrored as a whole, so any text it draws would read backwards.
Draw text in an overlay instead.

## Choosing a direction

Pin the direction for a subtree with the `waveformTimelineDirection(_:)` modifier — for example,
an audio editor that keeps time left to right in every language:

```swift
WaveformView(summary: summary, currentTime: t)
    .waveformTimelineDirection(.leftToRight)
```

`WaveformView.snapshot` renders outside your app's environment, so pass
`layoutDirection: .rightToLeft` when you need a right-to-left image.

## See Also

- ``WaveformTimelineDirection``
- <doc:RegionSelection>
