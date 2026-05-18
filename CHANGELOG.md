# Changelog

All notable changes to WaveformKit are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.4.0] - 2026-05-17

### Added
- **`AVAudioEnginePlayer`** — `@Observable @MainActor` local-file player that conforms to both
  `WaveformPlayerAdapter` and `AmplitudeTap`. Plays via `AVAudioEngine` + `AVAudioPlayerNode`,
  installs a render-thread tap to drive real FFT spectrum bands. Unblocks "local file + FFT" use
  cases that `AVAudioPlayer` could never serve and `AVPlayer` was overkill for.
- **VoiceOver support** on `WaveformView` — adjustable trait, formatted "X:XX of Y:YY" value,
  swipe-up/down scrubs by 5 % of duration, marker count announced in the label.
- **`WaveformView.snapshot(...)`** — `ImageRenderer`-backed static method returning a `CGImage`
  for share-sheet thumbnails, cell-list previews, and App Store screenshots.
- **`WaveformSummary.demo(duration:bars:seed:)`** — deterministic synthetic summary so devs can
  preview `WaveformView` without wiring an audio file.
- **`#Preview` gallery** for every style + an idle/markers showcase, so Xcode previews show
  realistic output immediately.
- **Circular markers** — `MarkersOverlay` now renders point markers as radial ticks + dot and
  region markers as colored arcs on `.circular`. `WaveformView.hitTestMarker` gained an arc-length
  hit-test that wraps correctly across 12-o'clock.
- **Bounded recording memory** — `MicrophoneRecorder` gains `maxBins:` (default `4000`). When the
  in-progress amplitude array exceeds the cap it is halved in place by averaging adjacent pairs,
  bounding memory regardless of recording length. `summary` republishes are throttled to ~4 Hz so
  long captures stop reallocating 20 times per second.

### Fixed
- `MicrophoneRecorder` previously rebuilt `WaveformSummary` on every bin (20 Hz), causing
  quadratic copy work over long recordings. Now throttled.

## [0.3.1] - 2026-05-15

### Added
- `MicrophoneInterruption` enum and `onInterruption:` / `autoResumeAfterInterruption:` parameters
  on `MicrophoneRecorder`. The recorder now observes `AVAudioSession.interruptionNotification` and
  `routeChangeNotification`, syncs `isPaused` when the system pauses capture for a phone call or
  Siri, fires the callback for every event, and auto-resumes when iOS hints `shouldResume`.

### Fixed
- `AVPlayerAmplitudeTap` now installs `MTAudioProcessingTap` prepare/unprepare callbacks. FFT band
  edges are now mapped to the **actual** source sample rate instead of a hard-coded 44.1 kHz, so
  48 / 96 kHz tracks line up with the right frequencies. Int16 PCM sources are converted to
  Float32 via a pre-allocated scratch (no audio-thread allocations); unsupported formats are
  skipped cleanly instead of garbling the visualization.
- `FFTAnalyzer.updateSampleRate(_:)` recomputes band edges in place. Band-edge math factored into
  the testable static `FFTAnalyzer.computeBandEdges`.

## [0.3.0] - 2026-05-14

### Added
- **Markers & regions overlay** — pass `markers: [WaveformMarker]` to `WaveformView` to render
  point markers (line + dot + optional label) or region markers (translucent band + edge stripe +
  optional label) over any linear style. New `onMarkerTap` callback fires when a marker is tapped
  without dragging, distinct from `onSeek`. Hit-test geometry is exposed via the testable static
  `WaveformView.hitTestMarker`.

### Notes
- Tap on empty waveform still triggers `onSeek` immediately; markers only intercept their own
  hit area when `onMarkerTap` is set.
- Markers are linear-only in this release — `.circular` skips them.

## [0.2.0] - 2026-05-13

### Added
- `MicrophoneRecorder` — live mic capture via `AVAudioEngine` that drives the same `WaveformView`
  API as the file adapters. Exposes `currentAmplitude`, `bands` (FFT), and a growing `summary` so
  bars/mirroredBars/dots render the recording as it accrues.
  - Requests mic permission on iOS 17+ (`AVAudioApplication`) and macOS (`AVCaptureDevice`).
  - Configures the iOS audio session (`.playAndRecord` / `.measurement`) and tears it down on `stop()`.
  - Optional `outputURL:` writes captured audio to disk during recording.
  - `pause()` / `resume()` / `reset()` plus optional `maximumDuration:` cap.
  - Surfaces failures via `MicrophoneRecorderError` and `lastError`.
- `.idle` movement now renders a smooth ping-pong shimmer (played color sweeps left↔right on a
  2.5 s cycle). Works on every style and renders a placeholder waveform if `summary` is empty —
  usable as a loading skeleton before audio is decoded.

### Notes
- Apps using `MicrophoneRecorder` must add `NSMicrophoneUsageDescription` to Info.plist.

## [0.1.0] - 2026-05-12

Initial public release.

### Added
- `WaveformView` SwiftUI host that doubles as a seek control (drag for linear styles, angular drag for circular).
- Six wave styles: `.bars`, `.mirroredBars`, `.dancingBars`, `.line`, `.dots`, `.circular`.
- Four movement modes: `.progress`, `.reactive(boost:)`, `.combined(boost:)`, `.idle`.
- `WaveformColors` with played / unplayed split and optional gradients.
- `AVAudioPlayerAdapter` and `AVPlayerAdapter` for time-driven UI updates, both `@Observable`.
- `AVAudioPlayerAmplitudeTap` (polled `averagePower`) and `AVPlayerAmplitudeTap` (`MTAudioProcessingTap` + vDSP RMS).
- `FFTAnalyzer` with 1024-point Hann-windowed FFT and log-spaced frequency bands.
- `WaveformCache` and `WaveformLoader` for instant repeat opens.
- AVAssetReader-based decoder with `vDSP_rmsqv` per-bar RMS reduction.

### Known limitations
- `AVAudioPlayer` cannot expose FFT bands (no PCM access on that API).
- `MTAudioProcessingTap` assumes Float32 PCM; exotic codecs not yet handled via `prepare` callback.
- `.idle` movement is reserved but currently behaves like `.progress`.
