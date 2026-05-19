import Foundation
import AVFoundation
import MediaToolbox
import Accelerate
import Observation
import os

/// Thread-safe storage shared between the audio render thread (writer) and the main-thread poll
/// (reader). Holds the latest single-RMS amplitude and the latest FFT band magnitudes.
///
/// ## Ownership model
///
/// | Field              | Written by       | Read by          | Synchronisation  |
/// |--------------------|------------------|------------------|------------------|
/// | `amplitude`        | audio thread     | main thread      | `os_unfair_lock` |
/// | `bands`            | audio thread     | main thread      | `os_unfair_lock` |
/// | `bandScratch`      | audio thread     | audio thread     | none (serial)    |
/// | `sourceFormat`     | audio thread     | audio thread     | none (serial)    |
/// | `conversionScratch`| audio thread     | audio thread     | none (serial)    |
///
/// `bandScratch` is the pre-allocated output buffer for `analyzer.computeBands(out:)`.
/// It must NEVER be read from the main thread.  It exists solely to avoid a heap
/// allocation (`[Float](repeating:0,count:bandCount)`) inside the realtime callback.
final class AmplitudeTapStorage: @unchecked Sendable {
    private var lock = os_unfair_lock_s()
    private var amplitude: Float = 0
    private var bands: [Float]

    // ── Audio-thread-only fields ──────────────────────────────────────────────────────────
    // None of the fields below may be read or written on the main thread.

    /// Pre-allocated scratch buffer for FFT band output.  Populated by
    /// `analyzer.computeBands(out: &bandScratch)` and immediately drained by
    /// `writeFromAudioThread(amplitude:)`.  Never accessed from the main thread.
    var bandScratch: [Float]

    /// Set in the MTAudioProcessingTap `prepare` callback; read in `process`.
    var sourceFormat: AudioStreamBasicDescription?

    /// Float32 conversion buffer for Int16 PCM input.  Allocated once in `prepare`;
    /// reused every callback — zero heap allocations in the process path.
    var conversionScratch: [Float] = []

    let analyzer: FFTAnalyzer

    init(bandCount: Int, sampleRate: Float) {
        self.bands       = [Float](repeating: 0, count: bandCount)
        self.bandScratch = [Float](repeating: 0, count: bandCount)
        self.analyzer    = FFTAnalyzer(fftSize: 1024, bandCount: bandCount, sampleRate: sampleRate)
    }

    /// Atomically publish the latest amplitude and band values to the main thread.
    ///
    /// **Must be called only from the audio render thread**, immediately after
    /// `analyzer.computeBands(out: &bandScratch)` has populated `bandScratch`.
    ///
    /// The lock window covers a scalar copy of `bandCount` floats (~20 ns for 32 bands).
    /// `bandScratch` is never accessed by `snapshot()`, so there is no reader contention
    /// on that field.
    func writeFromAudioThread(amplitude newAmplitude: Float) {
        os_unfair_lock_lock(&lock)
        amplitude = newAmplitude
        let n = min(bands.count, bandScratch.count)
        for i in 0..<n { bands[i] = bandScratch[i] }
        os_unfair_lock_unlock(&lock)
    }

    /// Called from the main thread poll timer. Returns a snapshot of the latest values.
    func snapshot() -> (amplitude: Float, bands: [Float]) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return (amplitude, bands)
    }

    /// Called from MTAudioProcessingTap prepare callback (audio thread, once per setup).
    /// Updates the FFT analyzer's sample rate so band edges map to real frequencies, and
    /// preallocates a Float32 conversion buffer if the source isn't already Float32.
    func prepare(maxFrames: Int, format: AudioStreamBasicDescription) {
        sourceFormat = format
        analyzer.updateSampleRate(Float(format.mSampleRate))
        let isFloat = (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        if isFloat {
            conversionScratch = []
        } else {
            conversionScratch = [Float](repeating: 0, count: max(1, maxFrames))
        }
    }

    func unprepare() {
        sourceFormat = nil
        conversionScratch = []
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
            prepare: amplitudeTapPrepare,
            unprepare: amplitudeTapUnprepare,
            process: amplitudeTapProcess
        )

        // Swift's importer toggles MTAudioProcessingTapCreate's out-parameter between
        // `UnsafeMutablePointer<MTAudioProcessingTap?>` (Xcode 26+/Swift 6.2+) and
        // `UnsafeMutablePointer<Unmanaged<MTAudioProcessingTap>?>` (earlier toolchains) depending
        // on SDK header annotations. We compile against whichever the local toolchain expects.
        let createdTap: MTAudioProcessingTap?
        let status: OSStatus
        #if compiler(>=6.2)
        var tapOut: MTAudioProcessingTap?
        status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects,
            &tapOut
        )
        createdTap = (status == noErr) ? tapOut : nil
        #else
        var tapOut: Unmanaged<MTAudioProcessingTap>?
        status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects,
            &tapOut
        )
        createdTap = (status == noErr) ? tapOut?.takeRetainedValue() : nil
        #endif

        guard let createdTap else {
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

private let amplitudeTapPrepare: MTAudioProcessingTapPrepareCallback = { tap, maxFrames, formatPtr in
    let storagePtr = MTAudioProcessingTapGetStorage(tap)
    let storage = Unmanaged<AmplitudeTapStorage>.fromOpaque(storagePtr).takeUnretainedValue()
    storage.prepare(maxFrames: Int(maxFrames), format: formatPtr.pointee)
}

private let amplitudeTapUnprepare: MTAudioProcessingTapUnprepareCallback = { tap in
    let storagePtr = MTAudioProcessingTapGetStorage(tap)
    let storage = Unmanaged<AmplitudeTapStorage>.fromOpaque(storagePtr).takeUnretainedValue()
    storage.unprepare()
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

    let isFloat: Bool
    let isInt16: Bool
    if let fmt = storage.sourceFormat {
        isFloat = (fmt.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        isInt16 = !isFloat
            && (fmt.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0
            && fmt.mBitsPerChannel == 16
    } else {
        // No prepare callback fired yet — assume the historical default of Float32 PCM.
        isFloat = true
        isInt16 = false
    }
    guard isFloat || isInt16 else { return }   // Unsupported integer width — skip cleanly.

    var sumSquares: Float = 0
    var totalCount: Float = 0
    var firstChannelReady = false

    for buf in abl {
        guard let data = buf.mData, buf.mDataByteSize > 0 else { continue }

        if isFloat {
            // ── Float32 path ──────────────────────────────────────────────────────────────
            // `data` is owned by the tap's ABL for the duration of this callback; the pointer
            // is valid here without any closure wrapping.
            let frameCount = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
            guard frameCount > 0 else { continue }
            let floatPtr = data.assumingMemoryBound(to: Float.self)

            var rms: Float = 0
            vDSP_rmsqv(floatPtr, 1, &rms, vDSP_Length(frameCount))
            sumSquares += rms * rms * Float(frameCount)
            totalCount += Float(frameCount)

            if !firstChannelReady {
                storage.analyzer.push(samples: floatPtr, count: frameCount)
                firstChannelReady = true
            }
        } else {
            // ── Int16 path ────────────────────────────────────────────────────────────────
            // Convert Int16 → Float32 in the pre-allocated conversionScratch.  All pointer
            // usage (vDSP calls, FFT push) stays inside the single exclusive borrow of
            // conversionScratch so no pointer escapes the closure.  This eliminates the
            // original bug where `floatPtr` was extracted from withUnsafeBufferPointer and
            // used after the closure's exclusive borrow had ended (undefined behaviour).
            let int16Count = Int(buf.mDataByteSize) / MemoryLayout<Int16>.size
            guard int16Count > 0, int16Count <= storage.conversionScratch.count else { continue }
            let intPtr = data.assumingMemoryBound(to: Int16.self)

            var rms: Float = 0
            let shouldPush = !firstChannelReady   // capture by value before the closure

            storage.conversionScratch.withUnsafeMutableBufferPointer { scratch in
                guard let base = scratch.baseAddress else { return }
                // Int16 → Float32 in [-1, 1]: convert then scale. No heap allocation.
                vDSP_vflt16(intPtr, 1, base, 1, vDSP_Length(int16Count))
                var scale: Float = 1.0 / 32768.0
                vDSP_vsmul(base, 1, &scale, base, 1, vDSP_Length(int16Count))
                // RMS and FFT push happen inside the closure — pointer stays valid.
                vDSP_rmsqv(base, 1, &rms, vDSP_Length(int16Count))
                if shouldPush {
                    storage.analyzer.push(samples: base, count: int16Count)
                }
            }
            sumSquares += rms * rms * Float(int16Count)
            totalCount += Float(int16Count)
            if shouldPush { firstChannelReady = true }
        }
    }

    // ── FFT + publish ─────────────────────────────────────────────────────────────────────
    // computeBands writes into storage.bandScratch (pre-allocated in AmplitudeTapStorage.init).
    // writeFromAudioThread then copies bandScratch → bands under os_unfair_lock.
    // Zero heap allocations in this entire callback.
    let amplitude = totalCount > 0 ? sqrt(sumSquares / totalCount) : 0
    storage.analyzer.computeBands(out: &storage.bandScratch)
    storage.writeFromAudioThread(amplitude: min(1, max(0, amplitude)))
}
