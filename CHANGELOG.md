# Changelog

All notable changes to WaveformKit are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
