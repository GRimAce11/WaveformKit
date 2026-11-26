# Selecting a Region

Let people pick a time range on the waveform — to trim, loop, or export it.

## Overview

Give ``WaveformView`` a `selection` binding and it becomes a range picker. The range is a
plain `ClosedRange<TimeInterval>?` you own, so the rest of your UI reads it directly:

```swift
@State private var selection: ClosedRange<TimeInterval>?

WaveformView(
    summary: summary,
    currentTime: player.currentTime,
    selection: $selection,
    selectionOptions: .editor,
    onSeek: { player.seek(to: $0) }
)
```

## Gestures

``WaveformSelectionOptions/activation`` decides what starts a new selection:

- ``WaveformSelectionOptions/Activation/longPress(holdDuration:)`` — the default. Hold, then
  drag. An ordinary drag still seeks, so a player keeps its scrubbing.
- ``WaveformSelectionOptions/Activation/drag`` — any drag selects and taps still seek. Use it
  on trim and edit screens, through the ``WaveformSelectionOptions/editor`` preset.

Either edge of an existing selection can then be dragged. Each has a 44-point touch target, wider
than the handle drawn, and dragging one edge past the other swaps them. A tap outside the
selection clears it when ``WaveformSelectionOptions/clearsOnTapOutside`` is set; the tap
still seeks.

## Shaping the result

- ``WaveformSelectionOptions/snapInterval`` snaps both edges to a grid.
- ``WaveformSelectionOptions/minimumLength`` discards accidental tiny drags on release. An edge
  drag that ends too short restores the previous selection rather than deleting it.
- ``WaveformSelectionOptions/updatesWhileDragging`` set to `false` writes the binding once, when
  the finger lifts — use it when the selection drives something expensive, such as restarting a
  looped playback. The range is drawn live either way.

## Accessibility

With no selection, the waveform offers a **Select from playhead** action. With one, a **Clear
selection** action appears, the waveform's label includes the range, and **Selection start** and
**Selection end** are adjustable elements: swipe up or down to move an edge by
``WaveformSelectionOptions/accessibilityStep(duration:)``.

## Zoom

Selection is drawn and hit-tested through the ``WaveformViewport``, so it stays under the finger
at any zoom factor. An edge cannot be dragged beyond the visible range — the timeline does not
auto-scroll — so zoom out or pan to reach further. The `.circular` style ignores selection.

## See Also

- ``WaveformSelectionOptions``
- <doc:ZoomAndPan>
