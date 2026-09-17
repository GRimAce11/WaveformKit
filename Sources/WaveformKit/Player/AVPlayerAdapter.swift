import Foundation
import AVFoundation
import Observation

@Observable
@MainActor
public final class AVPlayerAdapter: WaveformPlayerAdapter {
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var isPlaying: Bool = false

    @ObservationIgnored
    private let player: AVPlayer
    /// Holds the periodic time-observer token.  The token is non-Sendable, so a `@MainActor`
    /// class cannot release it from its own nonisolated `deinit` under Swift 6.
    @ObservationIgnored
    private let teardown = AudioTeardown()
    @ObservationIgnored
    private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored
    private var rateObservation: NSKeyValueObservation?

    public init(player: AVPlayer, tickRate: Double = 30) {
        self.player = player
        installObservers(rate: tickRate)
        refreshDuration()
    }

    public func seek(to time: TimeInterval) {
        let clamped = max(0, min(duration > 0 ? duration : .greatestFiniteMagnitude, time))
        let cmTime = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
    }

    public func play() {
        player.play()
        isPlaying = true
    }

    public func pause() {
        player.pause()
        isPlaying = false
    }

    private func installObservers(rate: Double) {
        let interval = CMTime(seconds: 1.0 / max(1, rate), preferredTimescale: 600)
        let timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] cmTime in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentTime = cmTime.seconds.isFinite ? cmTime.seconds : 0
                if self.duration == 0 { self.refreshDuration() }
            }
        }
        // Capture the player and token only — never `self`.
        teardown.onDeinit = { [player] in player.removeTimeObserver(timeObserver) }

        rateObservation = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            MainActor.assumeIsolated {
                self?.isPlaying = player.rate != 0
            }
        }
        statusObservation = player.observe(\.currentItem?.status, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.refreshDuration()
            }
        }
    }

    private func refreshDuration() {
        guard let item = player.currentItem else { return }
        let d = item.duration.seconds
        if d.isFinite, d > 0 { duration = d }
    }

    deinit {
        // `NSKeyValueObservation` is Sendable, so these are fine here; the time-observer token
        // is not, which is why it lives on `teardown`.
        statusObservation?.invalidate()
        rateObservation?.invalidate()
    }
}
