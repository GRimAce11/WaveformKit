import Foundation

/// Describes the currently-visible time window of a waveform.
///
/// A viewport with `zoomFactor == 1` shows the entire duration — this is the default and is
/// equivalent to no viewport being set at all.  When `zoomFactor > 1` the waveform is zoomed in
/// and `WaveformView` renders only the amplitude bars inside `visibleRange`.
///
/// Phase 2 ships the data model and rendering arithmetic.
/// Zoom/pan gestures are wired in Phase 3.
///
/// ```swift
/// @State private var viewport = WaveformViewport(duration: summary.duration)
///
/// WaveformView(
///     summary: summary,
///     currentTime: player.currentTime,
///     viewport: $viewport,
///     onSeek: { player.seek(to: $0) }
/// )
/// ```
public struct WaveformViewport: Sendable, Equatable {

    /// Currently visible time range within [0, `duration`].
    public var visibleRange: ClosedRange<TimeInterval>

    /// Total audio duration.  Immutable for a given asset.
    public let duration: TimeInterval

    /// Initialise a viewport that shows the full duration (zoom factor = 1).
    public init(duration: TimeInterval) {
        let d = max(0, duration)
        self.duration = d
        self.visibleRange = 0...d
    }

    // MARK: - Derived geometry

    /// How many times the waveform is magnified relative to its natural width.
    /// Returns 1.0 when the entire duration is visible.
    public var zoomFactor: Double {
        let span = visibleRange.upperBound - visibleRange.lowerBound
        guard span > 0, duration > 0 else { return 1 }
        return duration / span
    }

    /// `true` when the waveform is zoomed in enough to show a subset of its bars.
    public var isZoomed: Bool { zoomFactor > 1.001 }

    /// `visibleRange` expressed as a fraction of `duration`, in [0, 1].
    public var normalizedRange: ClosedRange<Double> {
        guard duration > 0 else { return 0...1 }
        return (visibleRange.lowerBound / duration)...(visibleRange.upperBound / duration)
    }

    // MARK: - Mutations

    /// Zoom to the given absolute factor, anchored at a normalised position within the
    /// current visible range.
    ///
    /// - Parameters:
    ///   - factor: Desired zoom factor. Clamped to [1, ∞).
    ///   - anchor: Normalised anchor position in [0, 1] within the *current* visible span.
    ///             0 = left edge, 0.5 = centre, 1 = right edge.  Defaults to centre.
    ///   - minSpan: Minimum visible time span in seconds.  Prevents over-zooming.
    public mutating func zoom(to factor: Double, anchor: Double = 0.5, minSpan: TimeInterval = 1.0) {
        let clampedFactor  = max(1, factor)
        let currentSpan    = visibleRange.upperBound - visibleRange.lowerBound
        let newSpan        = max(minSpan, duration / clampedFactor)
        let clampedAnchor  = min(1, max(0, anchor))
        let anchorTime     = visibleRange.lowerBound + currentSpan * clampedAnchor
        let rawLower       = anchorTime - newSpan * clampedAnchor
        let newLower       = max(0, min(duration - newSpan, rawLower))
        visibleRange       = newLower...min(duration, newLower + newSpan)
    }

    /// Shift the visible range by `deltaTime` seconds, clamped to stay within [0, duration].
    public mutating func pan(by deltaTime: TimeInterval) {
        let span     = visibleRange.upperBound - visibleRange.lowerBound
        let newLower = max(0, min(duration - span, visibleRange.lowerBound + deltaTime))
        visibleRange = newLower...(newLower + span)
    }

    /// Reset to the full-duration view (zoom factor = 1).
    public mutating func resetZoom() {
        visibleRange = 0...duration
    }

    // MARK: - Rendering helpers

    /// The range of bar indices (into a `src` array of length `totalBars`) that fall inside
    /// the visible range.  Returns the full range when the viewport is not zoomed.
    public func visibleIndices(totalBars: Int) -> Range<Int> {
        guard totalBars > 0 else { return 0..<0 }
        if !isZoomed { return 0..<totalBars }
        let norm     = normalizedRange
        let start    = Int((norm.lowerBound * Double(totalBars)).rounded(.down))
        let end      = Int((norm.upperBound * Double(totalBars)).rounded(.up))
        let lo       = max(0, start)
        let hi       = min(totalBars, max(lo + 1, end))
        return lo..<hi
    }

    /// Convert a normalised position [0, 1] within the *visible range* to an absolute time.
    public func time(forVisibleProgress p: Double) -> TimeInterval {
        let span = visibleRange.upperBound - visibleRange.lowerBound
        return visibleRange.lowerBound + min(1, max(0, p)) * span
    }

    /// Convert an absolute time to a normalised position [0, 1] within the *visible range*.
    /// Returns `nil` when the time is outside the visible range.
    public func visibleProgress(for time: TimeInterval) -> Double? {
        let span = visibleRange.upperBound - visibleRange.lowerBound
        guard span > 0 else { return nil }
        let p = (time - visibleRange.lowerBound) / span
        guard (0...1).contains(p) else { return nil }
        return p
    }
}
