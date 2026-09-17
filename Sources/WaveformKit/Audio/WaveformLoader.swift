import Foundation
import Observation

/// Observable controller that manages the async lifecycle of decoding a `WaveformSummary`
/// from an audio file URL.
///
/// Bind this to your view and drive `WaveformView` from `loader.state`:
///
/// ```swift
/// @State private var loader = WaveformLoader()
///
/// .task {
///     loader.load(url: fileURL)
/// }
///
/// WaveformView(loader: loader, currentTime: player.currentTime, ...)
///     .waveformStateOverlay(loader.state)
/// ```
///
/// ## State machine
///
/// ```
/// .idle ──load()──► .loading(0) ──progress──► .loading(p) ──► .loaded(summary)
///                        │                                             │
///                    cancel()                                      retry() ← no-op
///                        ▼                                             │
///                      .idle                                    .failed(error) ──retry()──► .loading(0)
/// ```
///
/// ## Backward compatibility
///
/// The static `WaveformLoader.load(url:targetBars:useCache:)` method from the previous
/// `enum`-based API is preserved on this class with an identical signature.
@Observable
@MainActor
public final class WaveformLoader {

    /// Current loading state.  Always mutated on the main actor.
    public private(set) var state: WaveformState = .idle

    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var lastURL: URL?
    @ObservationIgnored private var lastTargetBars: Int = 200
    @ObservationIgnored private var lastUseCache: Bool = true

    public init() {}

    // MARK: - Instance API

    /// Begin decoding the audio file at `url`.
    ///
    /// Any in-progress decode is cancelled before the new one starts.
    /// The disk cache is checked first; a cache hit resolves immediately with no progress events.
    public func load(url: URL, targetBars: Int = 200, useCache: Bool = true) {
        cancel()
        lastURL        = url
        lastTargetBars = targetBars
        lastUseCache   = useCache
        state          = .loading(progress: 0)

        loadTask = Task { [weak self] in
            guard let self else { return }

            // ── Cache hit — instant, no progress ticks ────────────────────────────────
            if useCache, let cached = WaveformCache.load(url: url, targetBars: targetBars) {
                guard !Task.isCancelled else { return }
                self.state = .loaded(cached)
                return
            }

            // ── Background decode with progress reporting ─────────────────────────────
            do {
                let summary = try await AudioDecoder.summarize(
                    url: url,
                    targetBars: targetBars,
                    onProgress: { [weak self] p in
                        // Progress callback fires on the decoder's background executor.
                        // Hop to MainActor to update observable state.
                        Task { @MainActor [weak self] in
                            guard let self, case .loading = self.state else { return }
                            self.state = .loading(progress: p)
                        }
                    }
                )
                guard !Task.isCancelled else { return }
                if useCache { WaveformCache.save(summary, url: url, targetBars: targetBars) }
                self.state = .loaded(summary)
            } catch is CancellationError {
                // Task was cancelled via cancel() — reset to idle without surfacing an error.
                self.state = .idle
            } catch {
                self.state = .failed(error)
            }
        }
    }

    /// Begin loading from an `AudioSource`.
    ///
    /// `.file` decodes exactly as `load(url:targetBars:useCache:)` does.  `.precomputed`
    /// resolves to `.loaded` immediately — no decode, no cache write, no progress ticks — so
    /// callers holding a server-supplied summary can use the same code path as callers holding
    /// a file.
    public func load(source: AudioSource, targetBars: Int = 200, useCache: Bool = true) {
        switch source {
        case .file(let url):
            load(url: url, targetBars: targetBars, useCache: useCache)
        case .precomputed(let summary):
            set(summary)
        }
    }

    /// Cancel the current decode, if any.  State returns to `.idle`.
    public func cancel() {
        loadTask?.cancel()
        loadTask = nil
        if case .loading = state { state = .idle }
    }

    /// Retry after a failure.  Safe to call from `.failed`; no-op from any other state.
    public func retry() {
        guard case .failed = state, let url = lastURL else { return }
        load(url: url, targetBars: lastTargetBars, useCache: lastUseCache)
    }

    /// Directly inject a pre-computed summary — skips decoding entirely.
    /// This is what `load(source:)` calls for `AudioSource.precomputed`; call it directly when
    /// you already hold a summary and have no `AudioSource` to wrap it in.
    public func set(_ summary: WaveformSummary) {
        cancel()
        state = .loaded(summary)
    }

    deinit {
        loadTask?.cancel()
    }

    // MARK: - Backward-compatible static API

    /// One-shot async loader that hits the disk cache before decoding.
    ///
    /// This is the same signature as the previous `enum WaveformLoader` API, preserved for
    /// source compatibility.  Prefer the instance API for production UI code because it
    /// exposes progress and cancellation.
    public static func load(
        url: URL,
        targetBars: Int = 200,
        useCache: Bool = true
    ) async throws -> WaveformSummary {
        if useCache, let cached = WaveformCache.load(url: url, targetBars: targetBars) {
            return cached
        }
        let summary = try await AudioDecoder.summarize(url: url, targetBars: targetBars)
        if useCache { WaveformCache.save(summary, url: url, targetBars: targetBars) }
        return summary
    }

    /// One-shot async loader for an `AudioSource`.  A `.precomputed` source returns its summary
    /// without touching the disk or the decoder.
    public static func load(
        source: AudioSource,
        targetBars: Int = 200,
        useCache: Bool = true
    ) async throws -> WaveformSummary {
        switch source {
        case .file(let url):
            return try await load(url: url, targetBars: targetBars, useCache: useCache)
        case .precomputed(let summary):
            return summary
        }
    }
}
