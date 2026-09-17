# Changelog

All notable changes to WaveformKit are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.6.0] - 2026-09-17

Phase 3 in full: the viewport gets gestures, the package moves to the Swift 6 language mode, and
the adoption surface (docs, decoder tests, visionOS) is filled in. Three groups of changes are
worth reading before upgrading: the **toolchain floor** rises to Swift 6.0 / Xcode 16, waveform
**rendering changes appearance** by default, and tap-to-seek now resolves on touch-up.

### Added

**Zoom and pan gestures** — completes the Phase 3 Tier 1 deliverable. `WaveformViewport` shipped
in 0.5.0 with complete arithmetic but no gestures; it is now driven by touch.

- `WaveformZoomOptions` — configures the pinch/pan/double-tap gestures on a `WaveformView`.
  `dragBehavior` (`.seek` / `.panWhenZoomed`), `maxZoomFactor`, `minVisibleDuration`,
  `resetsOnDoubleTap`, `yieldsToVerticalScroll`, `scrollIntentThreshold`, plus the
  `.disabled` / `.editor` / `.inScrollView` presets.
- `WaveformView` gains `zoom: WaveformZoomOptions = WaveformZoomOptions()` on both the
  `summary:` and `loader:` initialisers. Gestures are inert without a `viewport` binding, so
  existing call sites are unaffected.
- Pinch zooms anchored at the gesture centroid via `MagnifyGesture` (compiled out on tvOS).
  Drag pans under `.panWhenZoomed`. Double-tap resets to the full duration.
- `WaveformZoomOptions.zoomTarget(base:magnification:)` and
  `WaveformZoomOptions.panSeconds(deltaPoints:visibleSpan:width:)` are public pure functions, so
  the gesture arithmetic is testable without a running view hierarchy.

**Disk cache eviction**

- `WaveformCache.Configuration` with a `maximumBytes` budget; `.default` (32 MB) and
  `.unbounded` (pre-0.6.0 behaviour).
- `WaveformCache.configuration` — assigning a smaller budget evicts immediately.
- `WaveformCache.evictIfNeeded()` and `WaveformCache.currentByteSize` for on-demand reclamation
  and settings UI.
- Cache reads now stamp the entry's modification date, so eviction is driven by last *access*
  rather than last write.

**`AudioSource` is now a real code path**

- `WaveformLoader.load(source:targetBars:useCache:)` — instance and static. `.file` decodes as
  before; `.precomputed` resolves to `.loaded` synchronously.
- `AudioSource.url` and `AudioSource.summary` accessors.

### Changed

- `ResampleCache` is now a fixed-capacity LRU (16 entries by default) on top of its existing
  evict-on-new-summary policy. Its key includes the visible slice, so a live pinch minted a new
  permanent entry every frame — unbounded growth that only became reachable once zoom gestures
  existed.
- Tap-to-seek now resolves on touch-up rather than touch-down, so the second tap of a double-tap
  can reset the zoom instead of seeking. Scrubbing is unchanged: once a drag passes the 4 pt
  threshold, seeks fire continuously as before.

### Fixed

- `WaveformCache` no longer grows without bound. Previously it was documented as a known
  limitation and only `clear()` reclaimed space.

**Swift 6 language mode**

- `Package.swift` moves to `swift-tools-version: 6.0` with `swiftLanguageModes: [.v6, .v5]`.
  The package builds under the Swift 6 language mode with complete concurrency checking and
  zero warnings.
- Nonisolated-`deinit` isolation fixed across every player and recorder. A `@MainActor` class's
  `deinit` is nonisolated and cannot touch non-Sendable main-actor state, which affected
  `AVAudioEnginePlayer`, `AVAudioPlayerAdapter`, `AVAudioPlayerAmplitudeTap`, `AVPlayerAdapter`,
  `AVPlayerAmplitudeTap`, and `MicrophoneRecorder`.
- New internal `AudioTeardown` owns notification observers, engine shutdown, and `AVPlayer`
  time-observer tokens, so that cleanup runs from a `deinit` that is allowed to do it.
- The pure static helpers on `WaveformView` (`markerAccessibilityLabel(for:)` and friends) are
  now `nonisolated`. `View` is a `@MainActor` protocol, so they previously could not be called
  from a synchronous non-main context. This is a relaxation, not a breaking change.
- Audio-session notifications now extract their Sendable primitives (interruption type, options,
  route-change reason) inside the notification closure rather than sending the whole
  `[AnyHashable: Any]` `userInfo` across to the main actor. This code is inside
  `#if os(iOS) || os(tvOS) || os(visionOS)`, so it is invisible to a macOS `swift build` — the
  iOS build job is what catches it.
- CI gains a job that builds with `-warnings-as-errors`.

**Resample modes**

- New `WaveformResampleMode` (`.peak` / `.mean`) and a `resampleMode:` parameter on both
  `WaveformView` initialisers and on `WaveformView.snapshot(...)`.
- `resampleAmplitudes` gains a `mode:` parameter; peak pooling uses `vDSP_maxv`.
- `ResampleCache.Key` includes the mode, so switching modes cannot return a stale array.

### Changed (visual)

- **Resampling now defaults to `.peak` instead of mean pooling.** When a view asks for fewer
  bars than the summary has bins, each bar is the loudest bin it covers rather than the average.
  Waveforms gain contrast and keep their transients; a busy track no longer flattens toward a
  uniform block as the bar count drops. Pass `resampleMode: .mean` to restore the old look.
- Polling `Timer`s became `Task`s throughout. Besides the concurrency fix, this means playhead
  and amplitude updates no longer stall during scroll tracking — a default-mode `Timer` does not
  fire while a scroll view is tracking, which froze the playhead mid-scroll.

### Removed

- Support for Swift 5.9 and 5.10 **toolchains**. `swift-tools-version: 6.0` cannot be parsed by
  Xcode 15. The language *mode* is still selectable via `swiftLanguageModes`; the toolchain
  floor is not. Requirements are now Swift 6.0+ / Xcode 16+.

**Documentation and platforms**

- DocC catalog at `Sources/WaveformKit/WaveformKit.docc` — a curated landing page plus
  `GettingStarted`, `ZoomAndPan`, and `RealtimeSafety` articles. Builds with zero DocC warnings.
- `.spi.yml` so Swift Package Index hosts the documentation and shows a platform compatibility
  matrix. Deliberately **no** `swift-docc-plugin` dependency: Swift Package Index builds DocC on
  its own infrastructure, so the package keeps its zero-dependency promise.
- visionOS 1.0 added to `Package.swift` platforms. The library type-checks clean against the
  visionOS SDK under the Swift 6 language mode.
- `AVAudioSession.CategoryOptions.allowBluetooth` was renamed to `.allowBluetoothHFP` in the
  iOS 26 / visionOS 26 SDKs. Naming either spelling directly breaks a build against the other
  SDK, so the option is now built from its raw value, which compiles warning-free against both.
- CI gains an iOS/visionOS build matrix and a documentation job that fails on unresolved DocC
  symbol links.

**Tests**

- `AudioDecoder` gains end-to-end coverage — it previously had none, despite being the path
  every caller takes. Tests synthesize a WAV with `AVAudioFile` at test time rather than
  committing a binary fixture, and cover bar count, duration and format reporting, peak
  normalisation, envelope tracking, monotonic progress reporting, cancellation, and both failure
  modes.
- Added decoder/cache/loader integration tests covering a real decode, the disk round-trip, and
  `useCache: false`.

### Not done

- **tvOS was evaluated and rejected for this release.** SwiftUI marks `DragGesture` unavailable
  on tvOS, so seeking, panning, marker taps, and double-tap-to-reset cannot compile. A tvOS
  type-check reports that as the *only* error — everything else in the package is tvOS-clean —
  but the interaction path is not optional. Real support needs a focus-engine model and is now
  tracked in Phase 5.

**Tests: 129 total (+45 from 0.5.0)**


## [0.5.0] - 2026-05-19

### Added

**Async loading lifecycle**
- `WaveformState` enum — `.idle`, `.loading(progress: Double)`, `.loaded(WaveformSummary)`,
  `.failed(Error)` — with typed accessors (`summary`, `isLoading`, `loadingProgress`, `error`).
- `WaveformLoader` replaces the old `enum WaveformLoader`. Now an `@Observable @MainActor`
  class with `load(url:targetBars:useCache:)`, `cancel()`, `retry()`, and `set(_:)`.
  The static `WaveformLoader.load(url:targetBars:useCache:)` method is preserved on the class
  for source compatibility with existing callers.
- `AudioDecoder.summarize` gains `onProgress: (@Sendable (Double) -> Void)?`, fired per decoded
  bar (0…0.99) and once at 1.0 on completion.
- `WaveformView.init(loader:)` — convenience init that shows an `.idle` shimmer while decoding
  and transitions to the real waveform on `.loaded`.
- `View.waveformStateOverlay(_:)` — modifier that adds a progress bar for `.loading` and a
  system error view for `.failed`.

**Renderer extensibility**
- `WaveformRenderer` — `Sendable` drawing protocol for custom styles.
- `WaveformStyle.custom(renderer: any WaveformRenderer, barCount: Int)` — seventh style case.
- `WaveformStyle.Equatable` is now manual. Built-in cases compare structurally (no behaviour
  change); `.custom` cases are never equal.

**Viewport infrastructure**
- `WaveformViewport` — `visibleRange`, `zoomFactor`, `isZoomed`, `normalizedRange`,
  `zoom(to:anchor:minSpan:)`, `pan(by:)`, `resetZoom()`, `visibleIndices(totalBars:)`,
  `time(forVisibleProgress:)`, `visibleProgress(for:)`.
- `WaveformView` gains `viewport: Binding<WaveformViewport>? = nil`. Defaults to `nil` —
  fully backward-compatible. Gesture wiring (pinch-to-zoom, pan) ships in Phase 3.

**Resample caching**
- `ResampleCache` caches resampled amplitude arrays by `(summaryID, barCount, visibleSlice)`,
  held in `@State` in `WaveformView`. Eliminates per-frame `[Float]` allocations under
  reactive and dancing-bars movement modes (30–60 Hz body evaluations).
- `resampleAmplitudes` uses `vDSP_sve` (vectorised sum) instead of `reduce(0,+)`.
- `WaveformSummary` gains `id: UUID` for cache keying, excluded from `Equatable` and `Codable`.

**Realtime audio pipeline hardening** *(internal — no public API changes)*
- Pre-allocated `bandScratch` in `AmplitudeTapStorage` eliminates heap allocation inside
  `amplitudeTapProcess`, `AVAudioEnginePlayer.processBuffer`, and `MicrophoneRecorder.processBuffer`.
- `FFTAnalyzer.push` — scalar loop + modulo replaced with two block copies + bitmask wrap.
- `FFTAnalyzer.computeBands` — scalar ring-linearisation replaced with two block copies +
  single `vDSP_vmul` fused inside nested `withUnsafeBufferPointer`.
- Int16 audio path — all vDSP calls now happen inside the single exclusive borrow of
  `conversionScratch`, eliminating an `UnsafePointer` escape.
- `AudioDecoder.summarize` — `Task.checkCancellation()` added inside the decode loop.

**Tests: 84 total (+29 from 0.4.1)**

### Migration notes

**`WaveformLoader` type change** — `WaveformLoader` was a static-only `enum`; it is now a
`final class`. `WaveformLoader.load(url:)` call sites compile unchanged. No enum cases or
stored properties existed, so no real code breaks.

**`WaveformSummary.id`** — additive. Existing code compiles unchanged. Cached JSON is
backward-compatible (`id` is not encoded; decoded summaries get a fresh `UUID`).

**`WaveformStyle.Equatable`** — behaviour for all six built-in cases is identical to the
previous synthesised implementation. `.custom` cases compare unequal (only sensible default).

## [0.4.1] - 2026-05-19

### Added
- **Per-marker VoiceOver focus** — each `WaveformMarker` is exposed as its own accessibility
  element via `accessibilityChildren`. VoiceOver users can swipe between markers and double-tap
  to fire `onMarkerTap`. Label phrasing: `"Intro, at 0:12"` (point) or `"Verse, 0:48 to 1:10"`
  (region). `WaveformView.markerAccessibilityLabel(for:)` exposed for custom wrappers.
- **`AudioInterruption`** shared enum (previously `MicrophoneInterruption`) covering both player
  and recorder interruption events. `MicrophoneInterruption` remains as a typealias for source
  compatibility.
- **AVAudioEnginePlayer interruption handling** — installs/removes observers across
  `play()` / `stop()`, auto-pauses on `.began`, auto-resumes on `.ended(shouldResume: true)` when
  `autoResumeAfterInterruption` is `true` (default), and reports route changes via the same
  `onInterruption` callback the recorder already had.

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
