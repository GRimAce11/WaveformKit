# Contributing to WaveformKit

Bug reports, feature requests, and pull requests are welcome.

## Filing an issue

Use the issue templates and include:

- Platform and OS version (iOS, iPadOS, macOS, visionOS, watchOS or tvOS), and device or simulator
- Xcode and Swift versions
- Steps to reproduce
- Expected vs actual behaviour
- Audio format if relevant (mp3, m4a, wav, …)
- For FFT / amplitude issues: player path (`AVPlayer`, `AVAudioEnginePlayer`, `AVAudioPlayer`)
- For rendering issues: style, bar count, and whether `waveformRenderingBackend` is `.canvas` or `.metal`
- For interaction issues: whether a `viewport` or `selection` binding is set, and the layout direction

## Pull requests

- Keep PRs focused — one concern per PR.
- `swift build` and `swift test` must pass before opening. CI also builds for the iOS, tvOS,
  visionOS and watchOS simulators, because code inside `#if os(...)` blocks is invisible to a
  macOS build — check those jobs on your PR.
- Match the existing code style. Comments explain the *why*, not restate what the code does.
- Add or update tests when adding behaviour.
- Update `CHANGELOG.md` — add your change under `[Unreleased]`.
- Public API additions require doc comments. Follow the existing style: one-sentence summary,
  then parameter/return documentation where non-obvious.

## Code organisation

```
Sources/WaveformKit/
├── Audio/
│   ├── AmplitudeAccumulator.swift  Bins interleaved PCM into bar + pyramid RMS values
│   ├── AmplitudeTap.swift          AmplitudeTap protocol + AmplitudeEnvelope
│   ├── AudioDecoder.swift          File → WaveformSummary (AVAssetReader; AVAudioFile on watchOS)
│   ├── AudioSource.swift           AudioSource enum (.file / .precomputed)
│   ├── FFTAnalyzer.swift           1024-pt Hann FFT, ring buffer, log bands
│   ├── ResampleCache.swift         Per-view amplitude cache + resampleAmplitudes()
│   ├── WaveformCache.swift         Disk cache (Caches/WaveformKit/) with an LRU byte budget
│   └── WaveformLoader.swift        @Observable async loading controller
├── Models/
│   ├── WaveformColors.swift        Played/unplayed colours + gradients
│   ├── WaveformMarker.swift        Point and region marker value type
│   ├── WaveformRenderingBackend.swift  .canvas / .metal / .automatic
│   ├── WaveformResampleMode.swift  .peak / .mean pooling
│   ├── WaveformSelectionOptions.swift  Region-selection behaviour + pure helpers
│   ├── WaveformState.swift         .idle / .loading / .loaded / .failed
│   ├── WaveformStyle.swift         6 built-in styles + .custom(WaveformRenderer)
│   ├── WaveformSummary.swift       Amplitudes + metadata + optional pyramid
│   ├── WaveformSummaryPyramid.swift  Multi-resolution amplitudes for zoom
│   ├── WaveformTimelineDirection.swift  Left-to-right / right-to-left time
│   ├── WaveformViewport.swift      Visible time range + zoom/pan coordinate math
│   └── WaveformZoomOptions.swift   Gesture behaviour + pure gesture and crown arithmetic
├── Player/
│   ├── AmplitudeTapStorage.swift   Lock-protected audio-thread → main-thread hand-off
│   ├── AudioInterruption.swift     Shared interruption / route-change enum
│   ├── AudioTeardown.swift         Engine/observer cleanup run from a nonisolated deinit
│   ├── AVAudioEnginePlayer.swift   Local-file player + FFT in one object
│   ├── AVAudioPlayerAdapter.swift
│   ├── AVAudioPlayerAmplitudeTap.swift
│   ├── AVPlayerAdapter.swift
│   ├── AVPlayerAmplitudeTap.swift  MTAudioProcessingTap (not on watchOS)
│   ├── MicrophoneRecorder.swift    AVAudioEngine mic capture
│   └── WaveformPlayerAdapter.swift Protocol
└── View/
    ├── WaveformRemoteControl.swift Siri Remote seeking on tvOS + its pure arithmetic
    ├── WaveformRenderer.swift      WaveformRenderer protocol + CustomRendererView
    ├── WaveformTimeline.swift      Time ↔ x through the viewport and timeline direction
    ├── WaveformView.swift          SwiftUI host: gestures, crown zoom, accessibility, loader init
    ├── Metal/                      Opt-in Metal bars (not on watchOS)
    │   ├── MetalBarsPipeline.swift Shared device, queue and runtime-compiled pipeline
    │   ├── MetalBarsShader.swift   MSL source as a string + GPU data layout
    │   └── MetalBarsView.swift     MTKView host
    └── Renderers/
        ├── BarLayout.swift         Bar geometry shared by Canvas and Metal
        ├── BarsRenderer.swift
        ├── BarsView.swift          Picks Canvas or Metal for bar styles
        ├── CircularBarsRenderer.swift
        ├── DancingBarsRenderer.swift
        ├── DotsRenderer.swift
        ├── LineRenderer.swift
        ├── MarkersOverlay.swift
        └── SelectionOverlay.swift
```

The demo apps live in `Demo/` — see [Demo/README.md](Demo/README.md).

## Realtime audio thread rules

Code inside an audio render callback (`MTAudioProcessingTap` process callback or
`AVAudioEngine installTap` closure) must follow these rules. Violations cause audio glitches
under memory pressure and are difficult to reproduce in development.

**Never inside an audio callback:**
- Allocate heap memory (`[T](repeating:)`, `String`, `AnyObject` creation, array growth)
- Call Swift runtime for `Any` boxing
- Hold `os_unfair_lock` for more than a few scalar stores
- Call Objective-C methods that may allocate (`NSString`, `NSDictionary`, etc.)
- Call `os_log` on the formatting path
- Trigger Swift exclusivity checks on class properties from the audio thread

**Always:**
- Use pre-allocated buffers (`AmplitudeTapStorage.bandScratch`, `conversionScratch`)
- Use `vDSP` for vector math
- Keep lock windows to scalar copies only

If you touch an audio callback, add a comment citing why your change is realtime-safe.

## Building locally

```sh
swift build
swift test
```

The test suite includes performance budget tests for FFT throughput. If `testComputeBandsPerformanceBudget` or `testPushPerformanceBudget` fails, profile the regression before opening a PR.

## Releasing

1. Update `CHANGELOG.md` — move items from `[Unreleased]` into the new version section with
   the release date. Include migration notes for behaviour changes.
2. Update the `from:` version in the README SPM snippet.
3. Commit: `git commit -m "Release X.Y.Z"`.
4. Tag: `git tag -a X.Y.Z -m "X.Y.Z"`.
5. Push: `git push origin X.Y.Z`.
6. Draft a GitHub release referencing the changelog section.
