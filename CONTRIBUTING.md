# Contributing to WaveformKit

Bug reports, feature requests, and pull requests are welcome.

## Filing an issue

Use the issue templates and include:

- iOS / macOS version
- Xcode and Swift versions
- Steps to reproduce
- Expected vs actual behaviour
- Audio format if relevant (mp3, m4a, wav, …)
- For FFT / amplitude issues: player path (`AVPlayer`, `AVAudioEnginePlayer`, `AVAudioPlayer`)

## Pull requests

- Keep PRs focused — one concern per PR.
- `swift build` and `swift test` must pass before opening.
- Match the existing code style. Comments explain the *why*, not restate what the code does.
- Add or update tests when adding behaviour.
- Update `CHANGELOG.md` — add your change under `[Unreleased]`.
- Public API additions require doc comments. Follow the existing style: one-sentence summary,
  then parameter/return documentation where non-obvious.

## Code organisation

```
Sources/WaveformKit/
├── Audio/
│   ├── AmplitudeTap.swift          AmplitudeTap protocol + AmplitudeEnvelope
│   ├── AudioDecoder.swift          AVAssetReader → WaveformSummary
│   ├── AudioSource.swift           AudioSource enum (.file / .precomputed)
│   ├── FFTAnalyzer.swift           1024-pt Hann FFT, ring buffer, log bands
│   ├── ResampleCache.swift         Per-view amplitude cache + resampleAmplitudes()
│   ├── WaveformCache.swift         Disk cache (Caches/WaveformKit/)
│   └── WaveformLoader.swift        @Observable async loading controller
├── Models/
│   ├── WaveformColors.swift        Played/unplayed colours + gradients
│   ├── WaveformMarker.swift        Point and region marker value type
│   ├── WaveformState.swift         .idle / .loading / .loaded / .failed
│   ├── WaveformStyle.swift         6 built-in styles + .custom(WaveformRenderer)
│   ├── WaveformSummary.swift       Amplitude array + metadata + cache identity (id: UUID)
│   └── WaveformViewport.swift      Visible time range + zoom/pan coordinate math
├── Player/
│   ├── AudioInterruption.swift     Shared interruption / route-change enum
│   ├── AVAudioEnginePlayer.swift   Local-file player + FFT in one object
│   ├── AVAudioPlayerAdapter.swift
│   ├── AVAudioPlayerAmplitudeTap.swift
│   ├── AVPlayerAdapter.swift
│   ├── AVPlayerAmplitudeTap.swift  MTAudioProcessingTap + AmplitudeTapStorage
│   ├── MicrophoneRecorder.swift    AVAudioEngine mic capture
│   └── WaveformPlayerAdapter.swift Protocol
└── View/
    ├── WaveformRenderer.swift      WaveformRenderer protocol + CustomRendererView
    ├── WaveformView.swift          SwiftUI host, seek, accessibility, loader init
    └── Renderers/
        ├── BarsRenderer.swift
        ├── CircularBarsRenderer.swift
        ├── DancingBarsRenderer.swift
        ├── DotsRenderer.swift
        ├── LineRenderer.swift
        └── MarkersOverlay.swift
```

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
