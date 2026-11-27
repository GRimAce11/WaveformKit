import Foundation
import AVFoundation

/// Central source of truth for demo audio.
///
/// All demo screens load audio through this catalog so there's one place to
/// control what plays. The test tone is always available without network access.
enum AudioCatalog {

    /// Returns the URL of a locally generated test tone, creating it if needed.
    ///
    /// The tone sweeps frequency from 220 Hz to 2.2 kHz over its duration and
    /// applies a rhythmic beat envelope so the waveform varies visually and the
    /// reactive/dancing bars have something to respond to.
    static func testTone(duration: Double = 30) -> URL? {
        let name = "wkdemo-tone-\(Int(duration))s.caf"
        let dest = cacheDirectory.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: dest.path) else { return dest }
        do {
            try ToneGenerator.write(to: dest, duration: duration)
            return dest
        } catch {
            return nil
        }
    }

    /// Removes all previously generated test tones. Call when the cache is stale.
    static func clearLocalCache() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: nil)) ?? []
        for f in files where f.lastPathComponent.hasPrefix("wkdemo-") {
            try? FileManager.default.removeItem(at: f)
        }
    }

    // MARK: - Internal

    static var cacheDirectory: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WaveformKitDemo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

// MARK: - Tone Generator

enum ToneGenerator {

    /// Writes a test tone suitable for waveform demos.
    ///
    /// The signal:
    /// - sweeps linearly from `lowHz` to `highHz` over `duration`
    /// - applies a rhythmic amplitude envelope (beat every ~0.5 s)
    /// - adds a slow modulating carrier for visual variety
    static func write(
        to url: URL,
        duration: Double = 30,
        sampleRate: Double = 44100,
        lowHz: Double = 220,
        highHz: Double = 2200
    ) throws {
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else { throw CocoaError(.fileWriteUnknown) }

        buffer.frameLength = frameCount
        let ptr = buffer.floatChannelData![0]

        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let progress = t / duration

            // Frequency sweep
            let freq = lowHz + (highHz - lowHz) * progress

            // Slow amplitude envelope: full signal with periodic quiet dips
            let envelope = 0.3 + 0.4 * (0.5 + 0.5 * sin(t * 0.7))

            // Beat pattern: sharp attack every ~0.5 s
            let beatPhase = t.truncatingRemainder(dividingBy: 0.5) / 0.5
            let beat = pow(sin(.pi * beatPhase), 2)

            let amp = Float(envelope * (0.4 + 0.6 * beat))
            ptr[i] = amp * Float(sin(2 * .pi * freq * t))
        }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}
