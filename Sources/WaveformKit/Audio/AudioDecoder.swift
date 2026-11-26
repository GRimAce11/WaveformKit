import Foundation
import AVFoundation
import Accelerate

public enum AudioDecoderError: Error, Sendable {
    case noAudioTrack
    case readerInitFailed
    case readFailed
}

public enum AudioDecoder {
    /// Decodes an audio file and returns a normalized amplitude summary.
    ///
    /// - Parameters:
    ///   - url: Local file URL of the audio asset.
    ///   - targetBars: Number of amplitude bins to produce. Larger = more detail, more memory.
    ///   - pyramidResolution: Base-level bin count for `WaveformSummary.pyramid`, which is what
    ///                 gives zoomed views real detail.  Computed in the same pass as the bars, so
    ///                 it adds no extra file read.  Pass `0` to skip it.  Bins are never made
    ///                 shorter than 64 frames (about 1.5 ms at 44.1 kHz), so short files get
    ///                 fewer; when that leaves no more bins than `targetBars`, no pyramid is built.
    ///   - onProgress: Optional callback fired on every decoded bar with an estimated
    ///                 progress in [0, 1].  Called from the decoder's execution context
    ///                 (not necessarily the main thread); dispatch to MainActor if needed.
    public static func summarize(
        url: URL,
        targetBars: Int = 200,
        pyramidResolution: Int = WaveformSummaryPyramid.defaultResolution,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> WaveformSummary {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else { throw AudioDecoderError.noAudioTrack }

        let formatDescriptions = try await track.load(.formatDescriptions)
        var sampleRate: Double = 44100
        var channelCount: Int = 1
        if let formatDesc = formatDescriptions.first,
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee {
            sampleRate = asbd.mSampleRate
            channelCount = Int(asbd.mChannelsPerFrame)
        }

        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: asset) }
        catch { throw AudioDecoderError.readerInitFailed }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw AudioDecoderError.readerInitFailed }
        reader.add(output)
        guard reader.startReading() else { throw AudioDecoderError.readFailed }

        let totalFrames = max(1, Int(duration * sampleRate))
        let channels = max(1, channelCount)
        let framesPerBar = max(1, totalFrames / max(1, targetBars))
        let elementsPerBar = framesPerBar * channels

        // Pyramid base bins.  Only worth building when they are finer than the bars.
        let framesPerFine = pyramidResolution > 0
            ? max(minimumFramesPerPyramidBin, totalFrames / pyramidResolution)
            : 0
        let buildsPyramid = framesPerFine > 0 && framesPerFine < framesPerBar
            && totalFrames / framesPerFine > targetBars
        let elementsPerFine = framesPerFine * channels

        var amplitudes: [Float] = []
        amplitudes.reserveCapacity(targetBars)
        var fine: [Float] = []
        if buildsPyramid { fine.reserveCapacity(totalFrames / framesPerFine + 1) }

        var buffer: [Float] = []
        // Two read heads over the same buffer: one per bar, one per pyramid bin.  They advance
        // at different rates, so the buffer is trimmed only up to the slower of the two.
        var consumed = 0
        var fineConsumed = 0

        while let sampleBuffer = output.copyNextSampleBuffer() {
            // Check for Swift Task cancellation on every decoded chunk.  For a 90-minute
            // podcast this loop runs ~1 000 times; without this check, navigating away while
            // decoding burns a CPU core for several seconds after the Task is cancelled.
            try Task.checkCancellation()

            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            guard length > 0 else { continue }
            let floatCount = length / MemoryLayout<Float>.size

            var chunk = [Float](repeating: 0, count: floatCount)
            chunk.withUnsafeMutableBytes { ptr in
                _ = CMBlockBufferCopyDataBytes(
                    blockBuffer,
                    atOffset: 0,
                    dataLength: length,
                    destination: ptr.baseAddress!
                )
            }
            buffer.append(contentsOf: chunk)

            while buffer.count - consumed >= elementsPerBar {
                amplitudes.append(rms(buffer[consumed..<(consumed + elementsPerBar)]))
                consumed += elementsPerBar
                // Estimated progress: bars decoded / target.  Cap at 0.99 so the caller
                // knows 1.0 is reserved for the final "all done" signal below.
                onProgress?(min(0.99, Double(amplitudes.count) / Double(targetBars)))
            }

            if buildsPyramid {
                while buffer.count - fineConsumed >= elementsPerFine {
                    fine.append(rms(buffer[fineConsumed..<(fineConsumed + elementsPerFine)]))
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

        // Final cancellation check before we build and return the summary.
        // Prevents returning a partially-decoded summary if cancellation arrived
        // between the last copyNextSampleBuffer() returning nil and this point.
        try Task.checkCancellation()

        if buffer.count > consumed {
            amplitudes.append(rms(buffer[consumed..<buffer.count]))
        }
        if buildsPyramid, buffer.count > fineConsumed {
            // The leftover can be a handful of samples, and an RMS over a few samples of a sine
            // can land anywhere up to its crest — enough to become the normalisation peak and
            // shrink every other bin.  Measure the tail over a full bin's width instead,
            // overlapping the previous bin.
            let from = max(0, buffer.count - elementsPerFine)
            fine.append(rms(buffer[from..<buffer.count]))
        }
        onProgress?(1.0)   // signal decode complete

        if reader.status == .failed {
            throw AudioDecoderError.readFailed
        }

        normaliseToUnitPeak(&amplitudes)
        normaliseToUnitPeak(&fine)
        let pyramid = fine.count > amplitudes.count ? WaveformSummaryPyramid(amplitudes: fine) : nil

        return WaveformSummary(
            amplitudes: amplitudes,
            duration: duration,
            sampleRate: sampleRate,
            channelCount: channelCount,
            pyramid: pyramid
        )
    }

    /// Shortest pyramid bin, in frames.  An RMS over fewer samples than this mostly measures
    /// where in the waveform's cycle the window happened to start, not how loud the audio is.
    static let minimumFramesPerPyramidBin = 64

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
