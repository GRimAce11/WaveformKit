import Foundation

@MainActor
public protocol WaveformPlayerAdapter: AnyObject {
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    var isPlaying: Bool { get }
    func seek(to time: TimeInterval)
}
