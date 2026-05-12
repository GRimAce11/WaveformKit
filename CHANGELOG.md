# Changelog

All notable changes to WaveformKit are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
