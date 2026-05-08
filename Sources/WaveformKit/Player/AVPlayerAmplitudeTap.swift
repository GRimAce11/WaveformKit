import Foundation
import AVFoundation
import MediaToolbox
import Accelerate
import Observation
import os

/// Thread-safe storage shared between the audio-render-thread tap callback and the main-thread poll.
final class AmplitudeTapStorage: @unchecked Sendable {
    private var lock = os_unfair_lock_s()
    private var amplitude: Float = 0

    func set(_ value: Float) {
        os_unfair_lock_lock(&lock)
        amplitude = value
        os_unfair_lock_unlock(&lock)
    }

    func get() -> Float {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return amplitude
    }
}

@Observable
@MainActor
public final class AVPlayerAmplitudeTap: AmplitudeTap {
    public private(set) var currentAmplitude: Float = 0

    @ObservationIgnored private let storage = AmplitudeTapStorage()
    @ObservationIgnored private var tap: MTAudioProcessingTap?
    @ObservationIgnored private weak var item: AVPlayerItem?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var envelope = AmplitudeEnvelope()
    @ObservationIgnored private let pollInterval: TimeInterval

    public init(player: AVPlayer, pollRate: Double = 30) {
        self.pollInterval = 1.0 / max(1, pollRate)
        startPolling()
        Task { [weak self] in
            await self?.attach(to: player)
        }
    }

    private func attach(to player: AVPlayer) async {
        guard let item = player.currentItem else { return }
        let asset = item.asset
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            return
        }
        guard let track = tracks.first else { return }

        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passRetained(storage).toOpaque(),
            init: amplitudeTapInit,
            finalize: amplitudeTapFinalize,
            prepare: nil,
            unprepare: nil,
            process: amplitudeTapProcess
        )

        var tapOut: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects,
            &tapOut
        )
        guard status == noErr, let createdTap = tapOut else {
            Unmanaged.passUnretained(storage).release()
            return
        }
        self.tap = createdTap
        self.item = item

        let inputParams = AVMutableAudioMixInputParameters(track: track)
        inputParams.audioTapProcessor = createdTap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [inputParams]
        item.audioMix = mix
    }

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let raw = self.storage.get()
                self.currentAmplitude = self.envelope.step(target: raw, dt: Float(self.pollInterval))
            }
        }
    }

    deinit {
        timer?.invalidate()
        // Detach the tap from the player item so the audio engine releases it.
        // Storage is released via the tap's finalize callback.
        Task { @MainActor [weak item] in
            item?.audioMix = nil
        }
    }
}

private let amplitudeTapInit: MTAudioProcessingTapInitCallback = { _, clientInfo, tapStorageOut in
    tapStorageOut.pointee = clientInfo
}

private let amplitudeTapFinalize: MTAudioProcessingTapFinalizeCallback = { tap in
    let storagePtr = MTAudioProcessingTapGetStorage(tap)
    Unmanaged<AmplitudeTapStorage>.fromOpaque(storagePtr).release()
}

private let amplitudeTapProcess: MTAudioProcessingTapProcessCallback = {
    tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in

    let status = MTAudioProcessingTapGetSourceAudio(
        tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut
    )
    guard status == noErr else { return }

    let storagePtr = MTAudioProcessingTapGetStorage(tap)
    let storage = Unmanaged<AmplitudeTapStorage>.fromOpaque(storagePtr).takeUnretainedValue()

    let abl = UnsafeMutableAudioBufferListPointer(bufferListInOut)
    var sumSquares: Float = 0
    var totalCount: Float = 0
    for buf in abl {
        guard let data = buf.mData, buf.mDataByteSize > 0 else { continue }
        let floatCount = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
        guard floatCount > 0 else { continue }
        let ptr = data.assumingMemoryBound(to: Float.self)
        var rms: Float = 0
        vDSP_rmsqv(ptr, 1, &rms, vDSP_Length(floatCount))
        sumSquares += rms * rms * Float(floatCount)
        totalCount += Float(floatCount)
    }
    let amplitude = totalCount > 0 ? sqrt(sumSquares / totalCount) : 0
    storage.set(min(1, max(0, amplitude)))
}
