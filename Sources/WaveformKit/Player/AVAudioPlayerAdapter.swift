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
    @ObservationIgnored
    private var timer: Timer?

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
        timer?.invalidate()
        let interval = 1.0 / max(1, rate)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = self.player.currentTime
                self.isPlaying = self.player.isPlaying
                self.duration = self.player.duration
            }
        }
    }

    deinit {
        timer?.invalidate()
    }
}
