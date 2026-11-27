import Foundation
import Accelerate

/// Turns a stream of interleaved Float32 PCM into bar and pyramid RMS bins.
///
/// Both decoder paths feed it — `AVAssetReader` everywhere it exists, `AVAudioFile` on watchOS,
/// where `AVAssetReader` is unavailable — so the bins depend only on the samples, never on which
/// reader produced them or how it chunked them.
struct AmplitudeAccumulator {
    private let targetBars: Int
    private let elementsPerBar: Int
    private let buildsPyramid: Bool
    private let elementsPerFine: Int
    private let onProgress: (@Sendable (Double) -> Void)?

    private var amplitudes: [Float] = []
    private var fine: [Float] = []
    private var buffer: [Float] = []
    // Two read heads over the same buffer: one per bar, one per pyramid bin.  They advance
    // at different rates, so the buffer is trimmed only up to the slower of the two.
    private var consumed = 0
    private var fineConsumed = 0

    /// - Parameters:
    ///   - totalFrames: Expected frame count of the whole file; sets the bin widths.
    ///   - channelCount: Interleaved channels per frame.  Bins pool every channel together.
    init(
        totalFrames: Int,
        channelCount: Int,
        targetBars: Int,
        pyramidResolution: Int,
        onProgress: (@Sendable (Double) -> Void)?
    ) {
        let totalFrames = max(1, totalFrames)
        let channels = max(1, channelCount)
        let framesPerBar = max(1, totalFrames / max(1, targetBars))

        // Pyramid base bins.  Only worth building when they are finer than the bars.
        let framesPerFine = pyramidResolution > 0
            ? max(AudioDecoder.minimumFramesPerPyramidBin, totalFrames / pyramidResolution)
            : 0
        let buildsPyramid = framesPerFine > 0 && framesPerFine < framesPerBar
            && totalFrames / framesPerFine > targetBars

        self.targetBars = targetBars
        self.elementsPerBar = framesPerBar * channels
        self.buildsPyramid = buildsPyramid
        self.elementsPerFine = framesPerFine * channels
        self.onProgress = onProgress

        amplitudes.reserveCapacity(targetBars)
        if buildsPyramid { fine.reserveCapacity(totalFrames / framesPerFine + 1) }
    }

    /// Adds the next run of interleaved samples.
    mutating func append<Samples: Collection>(_ samples: Samples) where Samples.Element == Float {
        buffer.append(contentsOf: samples)

        while buffer.count - consumed >= elementsPerBar {
            amplitudes.append(Self.rms(buffer[consumed..<(consumed + elementsPerBar)]))
            consumed += elementsPerBar
            // Estimated progress: bars decoded / target.  Cap at 0.99 so the caller
            // knows 1.0 is reserved for the final "all done" signal in `finish`.
            onProgress?(min(0.99, Double(amplitudes.count) / Double(targetBars)))
        }

        if buildsPyramid {
            while buffer.count - fineConsumed >= elementsPerFine {
                fine.append(Self.rms(buffer[fineConsumed..<(fineConsumed + elementsPerFine)]))
                fineConsumed += elementsPerFine
            }
        }

        let trim = buildsPyramid ? min(consumed, fineConsumed) : consumed
        if trim > elementsPerBar * 8 {
            buffer.removeFirst(trim)
            consumed -= trim
            fineConsumed = buildsPyramid ? fineConsumed - trim : 0
        }
    }

    /// Bins the leftover samples, normalises, reports progress 1.0, and builds the summary.
    mutating func finish(duration: TimeInterval, sampleRate: Double, channelCount: Int) -> WaveformSummary {
        if buffer.count > consumed {
            amplitudes.append(Self.rms(buffer[consumed..<buffer.count]))
        }
        if buildsPyramid, buffer.count > fineConsumed {
            // The leftover can be a handful of samples, and an RMS over a few samples of a sine
            // can land anywhere up to its crest — enough to become the normalisation peak and
            // shrink every other bin.  Measure the tail over a full bin's width instead,
            // overlapping the previous bin.
            let from = max(0, buffer.count - elementsPerFine)
            fine.append(Self.rms(buffer[from..<buffer.count]))
        }
        onProgress?(1.0)   // signal decode complete

        Self.normaliseToUnitPeak(&amplitudes)
        Self.normaliseToUnitPeak(&fine)
        let pyramid = fine.count > amplitudes.count ? WaveformSummaryPyramid(amplitudes: fine) : nil

        return WaveformSummary(
            amplitudes: amplitudes,
            duration: duration,
            sampleRate: sampleRate,
            channelCount: channelCount,
            pyramid: pyramid
        )
    }

    private static func rms(_ slice: ArraySlice<Float>) -> Float {
        slice.withContiguousStorageIfAvailable { ptr -> Float in
            guard let base = ptr.baseAddress, ptr.count > 0 else { return 0 }
            var r: Float = 0
            vDSP_rmsqv(base, 1, &r, vDSP_Length(ptr.count))
            return r
        } ?? 0
    }

    private static func normaliseToUnitPeak(_ values: inout [Float]) {
        guard let peak = values.max(), peak > 0 else { return }
        values = values.map { $0 / peak }
    }
}
