import SwiftUI

/// A timeline annotation overlaid on the waveform. Use point markers for chapter starts /
/// bookmarks / comments, and region markers for chorus/segment/clip overlays.
public struct WaveformMarker: Identifiable, Sendable, Equatable {
    public let id: UUID
    /// Start time on the recording timeline, in seconds.
    public let time: TimeInterval
    /// Length of the marker region. `0` = point marker (rendered as a line + dot);
    /// `> 0` = region marker (rendered as a translucent band).
    public let duration: TimeInterval
    public let color: Color
    /// Optional caption rendered above the marker. Pass `nil` to render the marker only.
    public let label: String?

    public init(
        id: UUID = UUID(),
        time: TimeInterval,
        duration: TimeInterval = 0,
        color: Color,
        label: String? = nil
    ) {
        self.id = id
        self.time = time
        self.duration = max(0, duration)
        self.color = color
        self.label = label
    }

    public var isRegion: Bool { duration > 0 }
}
