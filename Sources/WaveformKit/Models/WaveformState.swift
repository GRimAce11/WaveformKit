import Foundation

/// The loading lifecycle of a `WaveformSummary`.
///
/// State transitions:
/// ```
/// .idle ──load()──► .loading(0.0)
///                       │
///                  progress updates
///                       │
///             ┌─── .loading(p) ───┐
///             │                   │
///         .loaded(summary)    .failed(error)
///             │                   │
///         retry()────────────────►│  (no-op from .loaded)
///         cancel()──► .idle       │
/// ```
///
/// State is always set on the main thread by `WaveformLoader`.
public enum WaveformState: Sendable {
    case idle
    case loading(progress: Double)
    case loaded(WaveformSummary)
    case failed(Error)

    // MARK: - Convenience accessors

    /// The loaded summary, or `nil` if not yet loaded.
    public var summary: WaveformSummary? {
        guard case .loaded(let s) = self else { return nil }
        return s
    }

    /// `true` while a decode is in progress.
    public var isLoading: Bool {
        guard case .loading = self else { return false }
        return true
    }

    /// The decode progress in [0, 1], or `nil` if not currently loading.
    public var loadingProgress: Double? {
        guard case .loading(let p) = self else { return nil }
        return p
    }

    /// The error from a failed decode, or `nil` otherwise.
    public var error: Error? {
        guard case .failed(let e) = self else { return nil }
        return e
    }
}
