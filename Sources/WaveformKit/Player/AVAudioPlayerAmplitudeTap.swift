import Foundation
import AVFoundation
import Observation

@Observable
@MainActor
public final class AVAudioPlayerAmplitudeTap: AmplitudeTap {
    public private(set) var currentAmplitude: Float = 0

    @ObservationIgnored private let player: AVAudioPlayer
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var envelope = AmplitudeEnvelope()
    @ObservationIgnored private let pollInterval: TimeInterval

    public init(player: AVAudioPlayer, pollRate: Double = 30) {
        self.player = player
        self.pollInterval = 1.0 / max(1, pollRate)
        player.isMeteringEnabled = true
        startPolling()
    }

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        guard player.isPlaying else {
            currentAmplitude = envelope.step(target: 0, dt: Float(pollInterval))
            return
        }
        player.updateMeters()
        let channelCount = player.numberOfChannels
        var sumLinear: Float = 0
        for c in 0..<channelCount {
            let dB = player.averagePower(forChannel: c)
            sumLinear += pow(10, dB / 20)
        }
        let avg = channelCount > 0 ? sumLinear / Float(channelCount) : 0
        let target = max(0, min(1, avg))
        currentAmplitude = envelope.step(target: target, dt: Float(pollInterval))
    }

    deinit {
        timer?.invalidate()
    }
}
