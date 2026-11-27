import Foundation
import AVFoundation

public enum AudioDecoderError: Error, Sendable {
    case noAudioTrack
    case readerInitFailed
    case readFailed
}

public enum AudioDecoder {
    /// Decodes an audio file and returns a normalized amplitude summary.
    ///
    /// On watchOS, where `AVAssetReader` is unavailable, the file is read with `AVAudioFile`
    /// instead.  That opens audio files — WAV, AIFF, CAF, M4A, MP3 and the like — but not the
    /// audio track of a movie file, which fails with ``AudioDecoderError/readerInitFailed``.
    /// The bars and pyramid come out the same either way.
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
        #if os(watchOS)
        return try summarizeWithAudioFile(
            url: url, targetBars: targetBars, pyramidResolution: pyramidResolution,
            onProgress: onProgress
        )
        #else
        return try await summarizeWithAssetReader(
            url: url, targetBars: targetBars, pyramidResolution: pyramidResolution,
            onProgress: onProgress
        )
        #endif
    }

    /// Shortest pyramid bin, in frames.  An RMS over fewer samples than this mostly measures
    /// where in the waveform's cycle the window happened to start, not how loud the audio is.
    static let minimumFramesPerPyramidBin = 64

    // MARK: - AVAssetReader (every platform but watchOS)

    #if !os(watchOS)
    private static func summarizeWithAssetReader(
        url: URL,
        targetBars: Int,
        pyramidResolution: Int,
        onProgress: (@Sendable (Double) -> Void)?
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

        var accumulator = AmplitudeAccumulator(
            totalFrames: Int(duration * sampleRate),
            channelCount: channelCount,
            targetBars: targetBars,
            pyramidResolution: pyramidResolution,
            onProgress: onProgress
        )

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
            accumulator.append(chunk)
        }

        // Final cancellation check before we build and return the summary.
        // Prevents returning a partially-decoded summary if cancellation arrived
        // between the last copyNextSampleBuffer() returning nil and this point.
        try Task.checkCancellation()

        if reader.status == .failed {
            throw AudioDecoderError.readFailed
        }

        return accumulator.finish(duration: duration, sampleRate: sampleRate, channelCount: channelCount)
    }
    #endif

    // MARK: - AVAudioFile (watchOS)

    /// Frames read per `AVAudioFile.read(into:)` call.  About 0.37 s at 44.1 kHz: large enough
    /// that the per-call overhead is noise, small enough to keep cancellation responsive.
    static let audioFileChunkFrames: AVAudioFrameCount = 16_384

    /// The decoder used on watchOS.  Compiled on every platform so the test suite can check it
    /// against the `AVAssetReader` path on macOS.
    static func summarizeWithAudioFile(
        url: URL,
        targetBars: Int,
        pyramidResolution: Int,
        onProgress: (@Sendable (Double) -> Void)?
    ) throws -> WaveformSummary {
        let file: AVAudioFile
        do {
            // Interleaved Float32, the same layout the asset-reader path asks for, so the
            // accumulator sees identical sample order from either reader.
            file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: true)
        } catch {
            throw AudioDecoderError.readerInitFailed
        }

        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let channelCount = Int(format.channelCount)
        guard sampleRate > 0, channelCount > 0,
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: audioFileChunkFrames)
        else { throw AudioDecoderError.readerInitFailed }

        var accumulator = AmplitudeAccumulator(
            totalFrames: Int(file.length),
            channelCount: channelCount,
            targetBars: targetBars,
            pyramidResolution: pyramidResolution,
            onProgress: onProgress
        )

        while file.framePosition < file.length {
            try Task.checkCancellation()
            do { try file.read(into: pcm, frameCount: audioFileChunkFrames) }
            catch { throw AudioDecoderError.readFailed }

            let frames = Int(pcm.frameLength)
            // An interleaved buffer exposes all of its channels through the first pointer.
            guard frames > 0, let samples = pcm.floatChannelData?[0] else { break }
            accumulator.append(UnsafeBufferPointer(start: samples, count: frames * channelCount))
        }

        try Task.checkCancellation()

        return accumulator.finish(
            duration: Double(file.length) / sampleRate,
            sampleRate: sampleRate,
            channelCount: channelCount
        )
    }
}
