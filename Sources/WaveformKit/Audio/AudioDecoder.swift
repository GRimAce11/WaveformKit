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
    public static func summarize(
        url: URL,
        targetBars: Int = 200
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
        let framesPerBar = max(1, totalFrames / max(1, targetBars))
        let elementsPerBar = framesPerBar * max(1, channelCount)

        var amplitudes: [Float] = []
        amplitudes.reserveCapacity(targetBars)

        var buffer: [Float] = []
        var consumed = 0

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
                let slice = buffer[consumed..<(consumed + elementsPerBar)]
                let rms = slice.withContiguousStorageIfAvailable { ptr -> Float in
                    var r: Float = 0
                    vDSP_rmsqv(ptr.baseAddress!, 1, &r, vDSP_Length(ptr.count))
                    return r
                } ?? 0
                amplitudes.append(rms)
                consumed += elementsPerBar
            }

            if consumed > elementsPerBar * 8 {
                buffer.removeFirst(consumed)
                consumed = 0
            }
        }

        // Final cancellation check before we build and return the summary.
        // Prevents returning a partially-decoded summary if cancellation arrived
        // between the last copyNextSampleBuffer() returning nil and this point.
        try Task.checkCancellation()

        if buffer.count > consumed {
            let slice = buffer[consumed..<buffer.count]
            let rms = slice.withContiguousStorageIfAvailable { ptr -> Float in
                var r: Float = 0
                vDSP_rmsqv(ptr.baseAddress!, 1, &r, vDSP_Length(ptr.count))
                return r
            } ?? 0
            amplitudes.append(rms)
        }

        if reader.status == .failed {
            throw AudioDecoderError.readFailed
        }

        if let peak = amplitudes.max(), peak > 0 {
            amplitudes = amplitudes.map { $0 / peak }
        }

        return WaveformSummary(
            amplitudes: amplitudes,
            duration: duration,
            sampleRate: sampleRate,
            channelCount: channelCount
        )
    }
}
