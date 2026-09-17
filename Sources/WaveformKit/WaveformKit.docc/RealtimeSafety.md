# Realtime Audio Safety

Why the FFT path allocates nothing, and what that buys you.

## Overview

Reactive waveform styles are driven by the audio itself. Getting that data means running code on
the **audio render thread**, which has a hard deadline: at 44.1 kHz with 1024-frame buffers the
callback fires roughly every 23 ms, and missing it produces an audible click rather than a
dropped frame.

Anything with unbounded latency is therefore off-limits inside that callback — heap allocation,
locks held across work, Objective-C message sends, Swift runtime calls that might allocate.
WaveformKit's audio path is written to that constraint.

### What the rules are

- **No heap allocation.** Every buffer the FFT needs is allocated once, when the tap is created.
  The per-callback work writes into that pre-allocated scratch space.
- **No unbounded lock.** A single `os_unfair_lock` is held only long enough to copy the finished
  band values into shared storage — `O(bandCount)` scalar stores, on the order of 20 ns for 32
  bands.
- **Vectorised throughout.** Windowing and magnitude work go through vDSP; ring-buffer moves are
  block copies that compile to `memmove` rather than element loops.
- **No Objective-C** in the process callback.

### What it costs

Measured on Apple Silicon in release, averaged over 10 000 iterations:

| Operation | Measured | Budget |
|---|---|---|
| 1024-point FFT to 32 bands | 6.4 µs | < 200 µs |
| Pushing 512 frames into the ring | 0.20 µs | < 20 µs |

That is under 0.03% of the render-thread budget. The test suite asserts these budgets, so a
regression fails CI rather than showing up as crackle in someone's app.

### Where the data surfaces

The audio thread only ever writes; the main thread only ever reads. ``AmplitudeTap`` exposes the
result as two observable properties — `currentAmplitude` and `bands` — polled at the display
rate with attack/decay smoothing, so the bars move smoothly instead of strobing.

Three types implement it: ``AVPlayerAmplitudeTap`` (streaming or local, via
`MTAudioProcessingTap`), ``AVAudioEnginePlayer`` (local files, tap installed on the player node),
and ``MicrophoneRecorder`` (live capture).

``AVAudioPlayerAmplitudeTap`` is the exception: `AVAudioPlayer` exposes average power per channel
but no PCM, so it reports an amplitude and leaves `bands` empty. Use ``AVAudioEnginePlayer`` when
you need a local file *and* a spectrum.

### Memory during long captures

``MicrophoneRecorder`` bounds its own growth. When the amplitude array passes `maxBins`, adjacent
pairs are averaged in place, halving the array and doubling the time each bar covers. A
twenty-four-hour recording stays under 16 KB — at the cost of temporal resolution in the oldest
portions, which degrades with each halving.

## See Also

- ``AmplitudeTap``
- ``MicrophoneRecorder``
