import Foundation
import AVFoundation
import Accelerate
import Observation

public enum MicrophoneRecorderError: Error, Sendable {
    case permissionDenied
    case alreadyRecording
    case engineStartFailed(underlying: NSError)
    case audioSessionFailed(underlying: NSError)
    case fileCreationFailed(underlying: NSError)
}

/// Live microphone capture that drives the same `WaveformView` API as the file-playback adapters.
///
/// Usage:
/// ```swift
/// let recorder = MicrophoneRecorder()
/// try await recorder.start()
/// // ...later
/// recorder.stop()
///
/// WaveformView(
///     summary: recorder.summary,
///     currentTime: recorder.currentTime,
///     amplitude: recorder.currentAmplitude,
///     bands: recorder.bands,
///     style: .mirroredBars(),
///     movement: .reactive(boost: 1.5)
/// )
/// ```
///
/// Apps must declare `NSMicrophoneUsageDescription` in Info.plist. To persist the recording, pass
/// `outputURL:` at init — buffers are written to disk during capture.
@Observable
@MainActor
public final class MicrophoneRecorder: WaveformPlayerAdapter {
    public private(set) var isRecording: Bool = false
    public private(set) var isPaused: Bool = false
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var currentAmplitude: Float = 0
    public private(set) var bands: [Float]
    public private(set) var summary: WaveformSummary
    public private(set) var lastError: MicrophoneRecorderError?
    public private(set) var recordedFileURL: URL?

    /// Mirrors `WaveformPlayerAdapter`. Equals `maximumDuration` while recording, falls back to
    /// `currentTime` afterward so progress-style views still render correctly.
    public var duration: TimeInterval {
        if let max = maximumDuration { return max }
        return currentTime
    }

    /// Recording doesn't have a seekable timeline, but conformance requires the method. No-op.
    public func seek(to time: TimeInterval) {}

    public var isPlaying: Bool { isRecording && !isPaused }

    public let bandCount: Int
    public let binsPerSecond: Double
    public let maximumDuration: TimeInterval?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var storage: AmplitudeTapStorage
    @ObservationIgnored private var amplitudes: [Float] = []
    @ObservationIgnored private var wallStartedAt: TimeInterval = 0
    @ObservationIgnored private var pausedAccumulator: TimeInterval = 0
    @ObservationIgnored private var pausedAt: TimeInterval?
    @ObservationIgnored private var tickTimer: Timer?
    @ObservationIgnored private var binTimer: Timer?
    @ObservationIgnored private var amplitudeEnvelope = AmplitudeEnvelope()
    @ObservationIgnored private var bandEnvelopes: [AmplitudeEnvelope]
    @ObservationIgnored private let pollInterval: TimeInterval
    @ObservationIgnored private let binInterval: TimeInterval
    @ObservationIgnored private let outputURL: URL?
    @ObservationIgnored private var outputFile: AVAudioFile?

    public init(
        bandCount: Int = 32,
        binsPerSecond: Double = 20,
        pollRate: Double = 30,
        maximumDuration: TimeInterval? = nil,
        outputURL: URL? = nil
    ) {
        self.bandCount = bandCount
        self.binsPerSecond = max(1, binsPerSecond)
        self.maximumDuration = maximumDuration
        self.outputURL = outputURL
        self.pollInterval = 1.0 / max(1, pollRate)
        self.binInterval = 1.0 / max(1, binsPerSecond)
        self.bands = [Float](repeating: 0, count: bandCount)
        self.bandEnvelopes = Array(repeating: AmplitudeEnvelope(), count: bandCount)
        self.storage = AmplitudeTapStorage(bandCount: bandCount, sampleRate: 44100)
        self.summary = WaveformSummary(
            amplitudes: [],
            duration: 0,
            sampleRate: 0,
            channelCount: 1
        )
    }

    public func start() async throws {
        guard !isRecording else { throw MicrophoneRecorderError.alreadyRecording }

        guard await Self.requestPermission() else {
            lastError = .permissionDenied
            throw MicrophoneRecorderError.permissionDenied
        }

        #if os(iOS) || os(tvOS) || os(visionOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            let mapped = MicrophoneRecorderError.audioSessionFailed(underlying: error as NSError)
            lastError = mapped
            throw mapped
        }
        #endif

        amplitudes.removeAll(keepingCapacity: true)
        currentTime = 0
        currentAmplitude = 0
        pausedAccumulator = 0
        pausedAt = nil
        lastError = nil

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        storage = AmplitudeTapStorage(bandCount: bandCount, sampleRate: Float(format.sampleRate))
        bands = [Float](repeating: 0, count: bandCount)
        bandEnvelopes = Array(repeating: AmplitudeEnvelope(), count: bandCount)
        summary = WaveformSummary(
            amplitudes: [],
            duration: 0,
            sampleRate: format.sampleRate,
            channelCount: Int(format.channelCount)
        )

        if let outputURL {
            do {
                outputFile = try AVAudioFile(forWriting: outputURL, settings: format.settings)
                recordedFileURL = outputURL
            } catch {
                let mapped = MicrophoneRecorderError.fileCreationFailed(underlying: error as NSError)
                lastError = mapped
                throw mapped
            }
        }

        let storageRef = storage
        let fileRef = outputFile
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            Self.processBuffer(buffer, storage: storageRef, file: fileRef)
        }

        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            outputFile = nil
            recordedFileURL = nil
            let mapped = MicrophoneRecorderError.engineStartFailed(underlying: error as NSError)
            lastError = mapped
            throw mapped
        }

        wallStartedAt = Date.timeIntervalSinceReferenceDate
        isRecording = true
        isPaused = false
        startTickTimers()
    }

    public func pause() {
        guard isRecording, !isPaused else { return }
        engine.pause()
        pausedAt = Date.timeIntervalSinceReferenceDate
        isPaused = true
    }

    public func resume() {
        guard isRecording, isPaused else { return }
        if let pausedAt {
            pausedAccumulator += Date.timeIntervalSinceReferenceDate - pausedAt
        }
        pausedAt = nil
        do {
            try engine.start()
            isPaused = false
        } catch {
            lastError = .engineStartFailed(underlying: error as NSError)
        }
    }

    public func stop() {
        guard isRecording else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        tickTimer?.invalidate()
        tickTimer = nil
        binTimer?.invalidate()
        binTimer = nil
        isRecording = false
        isPaused = false

        outputFile = nil
        summary = WaveformSummary(
            amplitudes: amplitudes,
            duration: currentTime,
            sampleRate: summary.sampleRate,
            channelCount: summary.channelCount
        )

        #if os(iOS) || os(tvOS) || os(visionOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        #endif
    }

    /// Drop the in-progress (or just-finished) capture, including any file written via `outputURL`.
    /// Safe to call whether or not a recording is active.
    public func reset() {
        let url = recordedFileURL
        if isRecording { stop() }
        amplitudes.removeAll()
        currentTime = 0
        currentAmplitude = 0
        bands = [Float](repeating: 0, count: bandCount)
        summary = WaveformSummary(amplitudes: [], duration: 0, sampleRate: summary.sampleRate, channelCount: summary.channelCount)
        lastError = nil
        recordedFileURL = nil
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    private func startTickTimers() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        binTimer = Timer.scheduledTimer(withTimeInterval: binInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.appendBin() }
        }
    }

    private func tick() {
        let (rawAmp, rawBands) = storage.snapshot()
        currentAmplitude = amplitudeEnvelope.step(target: rawAmp, dt: Float(pollInterval))
        let n = min(rawBands.count, bands.count, bandEnvelopes.count)
        for i in 0..<n {
            bands[i] = bandEnvelopes[i].step(target: rawBands[i], dt: Float(pollInterval))
        }
        if !isPaused {
            let now = Date.timeIntervalSinceReferenceDate
            currentTime = now - wallStartedAt - pausedAccumulator
            if let cap = maximumDuration, currentTime >= cap {
                currentTime = cap
                stop()
            }
        }
    }

    private func appendBin() {
        guard isRecording, !isPaused else { return }
        amplitudes.append(currentAmplitude)
        summary = WaveformSummary(
            amplitudes: amplitudes,
            duration: currentTime,
            sampleRate: summary.sampleRate,
            channelCount: summary.channelCount
        )
    }

    /// Runs on an internal AVAudioEngine queue. No main-actor state touched.
    nonisolated private static func processBuffer(
        _ buffer: AVAudioPCMBuffer,
        storage: AmplitudeTapStorage,
        file: AVAudioFile?
    ) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }
        let ch0 = channelData[0]

        var rms: Float = 0
        vDSP_rmsqv(ch0, 1, &rms, vDSP_Length(frameLength))
        _ = storage.analyzer.push(samples: ch0, count: frameLength)
        var bandOut = [Float](repeating: 0, count: storage.analyzer.bandCount)
        storage.analyzer.computeBands(out: &bandOut)
        storage.update(amplitude: min(1, max(0, rms)), withBands: bandOut)

        if let file {
            try? file.write(from: buffer)
        }
    }

    deinit {
        tickTimer?.invalidate()
        binTimer?.invalidate()
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
    }

    private static func requestPermission() async -> Bool {
        #if os(iOS) || os(tvOS) || os(visionOS)
        if #available(iOS 17, tvOS 17, visionOS 1, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { cont in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    cont.resume(returning: granted)
                }
            }
        }
        #elseif os(macOS)
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
        #else
        return false
        #endif
    }
}
