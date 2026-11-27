import Foundation
import AVFoundation
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

    /// Called from the main-thread poll task. Returns a snapshot of the latest values.
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
