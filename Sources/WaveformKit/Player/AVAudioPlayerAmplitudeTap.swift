import Foundation
import AVFoundation
import Observation

@Observable
@MainActor
public final class AVAudioPlayerAmplitudeTap: AmplitudeTap {
    public private(set) var currentAmplitude: Float = 0
    /// Always empty: `AVAudioPlayer` exposes whole-channel power only, no PCM. Use `AVPlayer` if
    /// you need a spectrum.
    public let bands: [Float] = []

    @ObservationIgnored private let player: AVAudioPlayer
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var envelope = AmplitudeEnvelope()
    @ObservationIgnored private let pollInterval: TimeInterval

    public init(player: AVAudioPlayer, pollRate: Double = 30) {
        self.player = player
        self.pollInterval = 1.0 / max(1, pollRate)
        player.isMeteringEnabled = true
        startPolling()
    }

    private func startPolling() {
        pollTask?.cancel()
        let interval = Duration.seconds(pollInterval)
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
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
        // `Task` is Sendable, so cancelling from a nonisolated deinit is legal under Swift 6.
        pollTask?.cancel()
    }
}
