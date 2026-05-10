import Foundation
import Accelerate

/// Real-input FFT with logarithmic band grouping. Intended to be called from the audio render
/// thread inside a tap. Pre-allocates everything; `process(samples:count:)` does no allocations.
///
/// Output bands are normalized 0...1 with a log-magnitude compression for visual punch.
final class FFTAnalyzer: @unchecked Sendable {
    let fftSize: Int
    let bandCount: Int
    private let log2N: vDSP_Length
    private let setup: FFTSetup
    private var window: [Float]

    // Ring buffer of the most recent fftSize samples.
    private var ring: [Float]
    private var writePos: Int = 0
    private var fillCount: Int = 0

    // Scratch for FFT.
    private var workReal: [Float]
    private var workImag: [Float]
    private var windowed: [Float]
    private var magnitudes: [Float]

    /// Inclusive start indices of each band into the magnitude bin array. Size = bandCount + 1.
    private let bandEdges: [Int]

    init(fftSize: Int = 1024, bandCount: Int = 32, sampleRate: Float = 44100) {
        precondition((fftSize & (fftSize - 1)) == 0, "fftSize must be a power of two")
        self.fftSize = fftSize
        self.bandCount = bandCount
        self.log2N = vDSP_Length(log2(Double(fftSize)))
        self.setup = vDSP_create_fftsetup(log2N, FFTRadix(kFFTRadix2))!

        var win = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&win, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        self.window = win

        self.ring = [Float](repeating: 0, count: fftSize)
        let half = fftSize / 2
        self.workReal = [Float](repeating: 0, count: half)
        self.workImag = [Float](repeating: 0, count: half)
        self.windowed = [Float](repeating: 0, count: fftSize)
        self.magnitudes = [Float](repeating: 0, count: half)

        // Logarithmic band edges between 40 Hz and Nyquist (capped at 16 kHz).
        let minFreq: Float = 40
        let maxFreq: Float = min(sampleRate / 2, 16000)
        let binsPerHz = Float(fftSize) / sampleRate
        var edges: [Int] = []
        edges.reserveCapacity(bandCount + 1)
        for i in 0...bandCount {
            let frac = Float(i) / Float(bandCount)
            let f = minFreq * pow(maxFreq / minFreq, frac)
            let bin = Int((f * binsPerHz).rounded())
            edges.append(min(half - 1, max(1, bin)))
        }
        self.bandEdges = edges
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    /// Push new samples into the ring; returns true if there's enough data for an FFT.
    func push(samples: UnsafePointer<Float>, count: Int) -> Bool {
        for i in 0..<count {
            ring[writePos] = samples[i]
            writePos = (writePos + 1) % fftSize
        }
        fillCount = min(fftSize, fillCount + count)
        return fillCount >= fftSize
    }

    /// Run FFT over the current ring contents and write `bandCount` band values into `out`.
    /// `out` must have at least `bandCount` elements. No allocations.
    func computeBands(out: inout [Float]) {
        // Linearize ring into `windowed` (in order from oldest to newest), applying Hann window.
        for i in 0..<fftSize {
            let src = ring[(writePos + i) % fftSize]
            windowed[i] = src * window[i]
        }

        // Pack real input into split-complex format for vDSP_fft_zrip.
        workReal.withUnsafeMutableBufferPointer { realPtr in
            workImag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                windowed.withUnsafeBufferPointer { wPtr in
                    wPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(fftSize / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2N, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }

        // Group magnitudes into log-spaced bands (mean over bins) + log compression.
        let denom = Float(fftSize)
        for i in 0..<bandCount {
            let start = bandEdges[i]
            let end = max(start + 1, bandEdges[i + 1])
            var sum: Float = 0
            magnitudes.withUnsafeBufferPointer { ptr in
                vDSP_sve(ptr.baseAddress!.advanced(by: start), 1, &sum, vDSP_Length(end - start))
            }
            let mean = sum / Float(end - start) / denom
            // log compress and normalize roughly to 0...1
            let compressed = log10f(max(1e-10, mean) * 1e6 + 1)
            out[i] = min(1, max(0, compressed * 0.18))
        }
    }
}
