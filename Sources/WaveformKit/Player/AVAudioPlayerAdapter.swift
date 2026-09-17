import Foundation
import AVFoundation
import Observation

@Observable
@MainActor
public final class AVAudioPlayerAdapter: WaveformPlayerAdapter {
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval
    public private(set) var isPlaying: Bool = false

    @ObservationIgnored
    private let player: AVAudioPlayer
    /// Polling ticker.  A `Task` rather than a `Timer` for two reasons: it is `Sendable`, so
    /// `deinit` can cancel it without touching main-actor state, and it keeps ticking during
    /// scroll tracking — a `Timer` scheduled in the default run-loop mode does not, which froze
    /// the playhead whenever the user scrolled a list containing the waveform.
    @ObservationIgnored
    private var tickTask: Task<Void, Never>?

    public init(player: AVAudioPlayer, tickRate: Double = 30) {
        self.player = player
        self.duration = player.duration
        startTicking(rate: tickRate)
    }

    public func seek(to time: TimeInterval) {
        let clamped = max(0, min(player.duration, time))
        player.currentTime = clamped
        currentTime = clamped
    }

    public func play() {
        player.play()
        isPlaying = player.isPlaying
    }

    public func pause() {
        player.pause()
        isPlaying = player.isPlaying
    }

    private func startTicking(rate: Double) {
        tickTask?.cancel()
        let interval = Duration.seconds(1.0 / max(1, rate))
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                self.currentTime = self.player.currentTime
                self.isPlaying   = self.player.isPlaying
                self.duration    = self.player.duration
            }
        }
    }

    deinit {
        // `Task` is Sendable, so cancelling it from a nonisolated deinit is legal under the
        // Swift 6 language mode.  A `Timer?` would not be.
        tickTask?.cancel()
    }
}
