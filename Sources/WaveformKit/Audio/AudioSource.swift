import Foundation

/// Where a `WaveformSummary` comes from.
///
/// Lets a view accept "some audio" without caring whether it still needs decoding.  A feed that
/// mixes freshly-imported files with summaries already fetched from a server can hand both to
/// the same loader:
///
/// ```swift
/// let source: AudioSource = item.cachedSummary.map(AudioSource.precomputed)
///                        ?? .file(item.localURL)
/// loader.load(source: source)
/// ```
public enum AudioSource: Sendable {
    /// A local audio file that still needs decoding.  Goes through the disk cache.
    case file(URL)
    /// An already-decoded summary — from a server, a previous session, or a test fixture.
    /// Resolves to `.loaded` immediately, with no decode and no cache write.
    case precomputed(WaveformSummary)

    /// The underlying file URL, or `nil` for a precomputed summary.
    public var url: URL? {
        if case .file(let url) = self { return url }
        return nil
    }

    /// The summary this source already holds, or `nil` if it has to be decoded first.
    public var summary: WaveformSummary? {
        if case .precomputed(let summary) = self { return summary }
        return nil
    }
}
