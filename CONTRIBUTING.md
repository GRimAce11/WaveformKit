# Contributing to WaveformKit

Bug reports, feature requests, and pull requests are welcome.

## Filing an issue

Please use the issue templates and include:

- iOS / macOS version
- Xcode and Swift versions
- Steps to reproduce
- Expected vs actual behavior
- Audio format if relevant (mp3, m4a, wav, …)

## Pull requests

- Keep PRs focused — one concern per PR.
- `swift build` and `swift test` must pass before opening.
- Match the existing code style. Comments should explain the *why*, not what the code already says.
- Add or update tests when adding behavior.

## Code organization

```
Sources/WaveformKit/
├── Models/         value types (WaveformSummary, WaveformStyle, WaveformColors)
├── Audio/          decoding, caching, FFT, AmplitudeTap protocol
├── Player/         concrete adapter + tap implementations per player
└── View/           SwiftUI host + per-style renderers
```

## Building locally

```sh
swift build
swift test
```

## Releasing

1. Update `CHANGELOG.md` — move items from `[Unreleased]` into the new version section.
2. Commit and tag: `git tag -a 0.x.0 -m "0.x.0"`.
3. Push the tag: `git push origin 0.x.0`.
4. Draft a GitHub release referencing the changelog.
