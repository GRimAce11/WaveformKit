import Foundation
import AVFoundation
import MediaToolbox
import Accelerate
import Observation
import os

/// Thread-safe storage shared between the audio render thread (writer) and the main-thread poll
/// (reader). Holds the latest single-RMS amplitude and the latest FFT band magnitudes.
final class AmplitudeTapStorage: @unchecked Sendable {
    private var lock = os_unfair_lock_s()
    private var amplitude: Float = 0
    private var bands: [Float]
    let analyzer: FFTAnalyzer

    init(bandCount: Int, sampleRate: Float) {
        self.bands = [Float](repeating: 0, count: bandCount)
        self.analyzer = FFTAnalyzer(fftSize: 1024, bandCount: bandCount, sampleRate: sampleRate)
    }

    /// Called from audio render thread. `incomingBands` length must equal `bands.count`.
    func update(amplitude newAmplitude: Float, withBands incomingBands: [Float]) {
        os_unfair_lock_lock(&lock)
        amplitude = newAmplitude
        if bands.count == incomingBands.count {
            for i in 0..<bands.count { bands[i] = incomingBands[i] }
        }
        os_unfair_lock_unlock(&lock)
    }

    func snapshot() -> (amplitude: Float, bands: [Float]) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return (amplitude, bands)
    }
}

@Observable
@MainActor
public final class AVPlayerAmplitudeTap: AmplitudeTap {
    public private(set) var currentAmplitude: Float = 0
    public private(set) var bands: [Float]

    @ObservationIgnored private let storage: AmplitudeTapStorage
    @ObservationIgnored private var tap: MTAudioProcessingTap?
    @ObservationIgnored private weak var item: AVPlayerItem?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var amplitudeEnvelope = AmplitudeEnvelope()
    @ObservationIgnored private var bandEnvelopes: [AmplitudeEnvelope]
    @ObservationIgnored private let pollInterval: TimeInterval

    public init(player: AVPlayer, bandCount: Int = 32, pollRate: Double = 30) {
        self.pollInterval = 1.0 / max(1, pollRate)
        self.storage = AmplitudeTapStorage(bandCount: bandCount, sampleRate: 44100)
        self.bands = [Float](repeating: 0, count: bandCount)
        self.bandEnvelopes = Array(repeating: AmplitudeEnvelope(), count: bandCount)
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
                self?.tick()
            }
        }
    }

    private func tick() {
        let (rawAmp, rawBands) = storage.snapshot()
        currentAmplitude = amplitudeEnvelope.step(target: rawAmp, dt: Float(pollInterval))
        let n = min(rawBands.count, bands.count, bandEnvelopes.count)
        for i in 0..<n {
            bands[i] = bandEnvelopes[i].step(target: rawBands[i], dt: Float(pollInterval))
        }
    }

    deinit {
        timer?.invalidate()
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

    // RMS across all buffers + push the first (or downmixed) channel's samples into the FFT ring.
    var sumSquares: Float = 0
    var totalCount: Float = 0
    var firstChannelReady = false

    for buf in abl {
        guard let data = buf.mData, buf.mDataByteSize > 0 else { continue }
        let floatCount = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
        guard floatCount > 0 else { continue }
        let ptr = data.assumingMemoryBound(to: Float.self)

        var rms: Float = 0
        vDSP_rmsqv(ptr, 1, &rms, vDSP_Length(floatCount))
        sumSquares += rms * rms * Float(floatCount)
        totalCount += Float(floatCount)

        if !firstChannelReady {
            // Push as many samples as fit; FFTAnalyzer is a ring, so excess simply overwrites.
            _ = storage.analyzer.push(samples: ptr, count: floatCount)
            firstChannelReady = true
        }
    }

    let amplitude = totalCount > 0 ? sqrt(sumSquares / totalCount) : 0
    var bandOut = [Float](repeating: 0, count: storage.analyzer.bandCount)
    storage.analyzer.computeBands(out: &bandOut)
    storage.update(amplitude: min(1, max(0, amplitude)), withBands: bandOut)
}
