import Foundation
import AVFoundation
import Accelerate
import Observation

public enum AVAudioEnginePlayerError: Error, Sendable {
    case fileLoadFailed(underlying: NSError)
    case engineStartFailed(underlying: NSError)
    case audioSessionFailed(underlying: NSError)
}

/// Local-file audio player that uses `AVAudioEngine` + `AVAudioPlayerNode` under the hood, so the
/// FFT spectrum bands work the same way they do during live microphone capture. Conforms to both
/// `WaveformPlayerAdapter` (currentTime / duration / seek / play / pause) and `AmplitudeTap`
/// (currentAmplitude / bands), so a single instance drives `WaveformView` end-to-end.
///
/// Use this when:
/// - You're playing a local file and want real FFT spectrum bands (`AVAudioPlayer` can't expose
///   them; `AVPlayer` works but is heavier and streaming-oriented).
/// - You want a single object to bind in your view body instead of a separate adapter + tap pair.
///
/// Usage:
/// ```swift
/// let player = try AVAudioEnginePlayer(url: url, bandCount: 32)
/// player.play()
///
/// WaveformView(
///     summary: summary,
///     currentTime: player.currentTime,
///     amplitude: player.currentAmplitude,
///     bands: player.bands,
///     style: .dancingBars(count: 32),
///     movement: .reactive(),
///     onSeek: { player.seek(to: $0) }
/// )
/// ```
@Observable
@MainActor
public final class AVAudioEnginePlayer: WaveformPlayerAdapter, AmplitudeTap {
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var isPlaying: Bool = false
    public private(set) var currentAmplitude: Float = 0
    public private(set) var bands: [Float]
    public private(set) var didFinish: Bool = false
    public private(set) var lastError: AVAudioEnginePlayerError?

    public let bandCount: Int
    public let autoResumeAfterInterruption: Bool

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let playerNode = AVAudioPlayerNode()
    @ObservationIgnored private let file: AVAudioFile
    @ObservationIgnored private let storage: AmplitudeTapStorage
    @ObservationIgnored private let pollInterval: TimeInterval
    /// Polling ticker.  A `Task` rather than a `Timer`: it is `Sendable` so `deinit` can cancel
    /// it, and unlike a default-mode `Timer` it keeps ticking while the user scrolls.
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var amplitudeEnvelope = AmplitudeEnvelope()
    @ObservationIgnored private var bandEnvelopes: [AmplitudeEnvelope]
    @ObservationIgnored private var seekOffset: TimeInterval = 0
    @ObservationIgnored private var tapInstalled = false
    @ObservationIgnored private let onInterruption: (@MainActor (AudioInterruption) -> Void)?
    @ObservationIgnored private var wasPlayingBeforeInterruption: Bool = false
    @ObservationIgnored private let teardown = AudioTeardown()

    public init(
        url: URL,
        bandCount: Int = 32,
        pollRate: Double = 30,
        autoResumeAfterInterruption: Bool = true,
        onInterruption: (@MainActor (AudioInterruption) -> Void)? = nil
    ) throws {
        do {
            self.file = try AVAudioFile(forReading: url)
        } catch {
            throw AVAudioEnginePlayerError.fileLoadFailed(underlying: error as NSError)
        }
        self.bandCount = bandCount
        self.autoResumeAfterInterruption = autoResumeAfterInterruption
        self.onInterruption = onInterruption
        self.pollInterval = 1.0 / max(1, pollRate)
        self.bands = [Float](repeating: 0, count: bandCount)
        self.bandEnvelopes = Array(repeating: AmplitudeEnvelope(), count: bandCount)
        let sourceFormat = file.processingFormat
        self.storage = AmplitudeTapStorage(bandCount: bandCount, sampleRate: Float(sourceFormat.sampleRate))
        self.duration = Double(file.length) / sourceFormat.sampleRate

        // Capture the engine and node only — never `self`, or the player would never
        // deallocate and this cleanup would never run.
        teardown.onDeinit = { [engine, playerNode] in
            if engine.isRunning {
                playerNode.stop()
                engine.stop()
            }
        }

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: sourceFormat)

        installTap(format: sourceFormat)
        schedule(from: 0)
    }

    public func play() {
        guard !isPlaying else { return }
        do {
            #if os(iOS) || os(tvOS) || os(visionOS)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            if !engine.isRunning { try engine.start() }
        } catch {
            lastError = .engineStartFailed(underlying: error as NSError)
            return
        }
        didFinish = false
        playerNode.play()
        isPlaying = true
        startTimer()
        installSystemObservers()
    }

    public func pause() {
        guard isPlaying else { return }
        playerNode.pause()
        isPlaying = false
        stopTimer()
    }

    /// Stop playback and reset to the beginning. Different from `pause()`: drains the scheduled
    /// buffer and re-schedules from t = 0, so the next `play()` starts cleanly from the top.
    public func stop() {
        playerNode.stop()
        isPlaying = false
        stopTimer()
        removeSystemObservers()
        wasPlayingBeforeInterruption = false
        seekOffset = 0
        currentTime = 0
        schedule(from: 0)
    }

    public func seek(to time: TimeInterval) {
        let clamped = max(0, min(duration, time))
        let wasPlaying = isPlaying
        playerNode.stop()
        seekOffset = clamped
        currentTime = clamped
        schedule(from: clamped)
        if wasPlaying {
            playerNode.play()
            isPlaying = true
        }
    }

    private func schedule(from time: TimeInterval) {
        let sampleRate = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition((time * sampleRate).rounded())
        guard startFrame < file.length else {
            // Schedule with zero frames is invalid; treat as immediate finish.
            handleCompletion()
            return
        }
        let frameCount = AVAudioFrameCount(file.length - startFrame)
        playerNode.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: frameCount,
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleCompletion()
            }
        }
    }

    private func handleCompletion() {
        guard isPlaying else { return }
        isPlaying = false
        didFinish = true
        stopTimer()
        currentTime = duration
    }

    private func installTap(format: AVAudioFormat) {
        guard !tapInstalled else { return }
        let storageRef = storage
        playerNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            Self.processBuffer(buffer, storage: storageRef)
        }
        tapInstalled = true
    }

    private func startTimer() {
        stopTimer()
        let interval = Duration.seconds(pollInterval)
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                self.tick()
            }
        }
    }

    private func stopTimer() {
        tickTask?.cancel()
        tickTask = nil
    }

    private func tick() {
        let (rawAmp, rawBands) = storage.snapshot()
        currentAmplitude = amplitudeEnvelope.step(target: rawAmp, dt: Float(pollInterval))
        let n = min(rawBands.count, bands.count, bandEnvelopes.count)
        for i in 0..<n {
            bands[i] = bandEnvelopes[i].step(target: rawBands[i], dt: Float(pollInterval))
        }
        // Derive currentTime from playerNode's render position.
        if let nodeTime = playerNode.lastRenderTime,
           let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
           playerTime.sampleRate > 0 {
            let elapsedInSegment = Double(playerTime.sampleTime) / playerTime.sampleRate
            currentTime = min(duration, max(0, seekOffset + elapsedInSegment))
        }
    }

    // MARK: - System event observers

    private func installSystemObservers() {
        #if os(iOS) || os(tvOS) || os(visionOS)
        guard teardown.observers.isEmpty else { return }
        let center = NotificationCenter.default
        teardown.observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            // Pull the Sendable primitives out here, on the notification's own thread:
            // `userInfo` is `[AnyHashable: Any]?`, which cannot cross into the main actor
            // under the Swift 6 language mode.
            let rawType    = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let rawOptions = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor [weak self] in
                self?.handleInterruption(rawType: rawType, rawOptions: rawOptions)
            }
        })
        teardown.observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let rawReason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor [weak self] in
                self?.handleRouteChange(rawReason: rawReason)
            }
        })
        #endif
    }

    private func removeSystemObservers() {
        teardown.removeObservers()
    }

    #if os(iOS) || os(tvOS) || os(visionOS)
    private func handleInterruption(rawType: UInt?, rawOptions: UInt?) {
        guard let rawType,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            if isPlaying {
                wasPlayingBeforeInterruption = true
                playerNode.pause()
                isPlaying = false
                stopTimer()
            }
            onInterruption?(.began)
        case .ended:
            let opts = AVAudioSession.InterruptionOptions(rawValue: rawOptions ?? 0)
            let shouldResume = opts.contains(.shouldResume)
            onInterruption?(.ended(shouldResume: shouldResume))
            if shouldResume, autoResumeAfterInterruption, wasPlayingBeforeInterruption {
                wasPlayingBeforeInterruption = false
                play()
            } else if !shouldResume {
                wasPlayingBeforeInterruption = false
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(rawReason: UInt?) {
        guard let rawReason,
              let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason) else { return }
        let mapped: AudioInterruption.RouteChangeReason
        switch reason {
        case .oldDeviceUnavailable: mapped = .oldDeviceUnavailable
        case .newDeviceAvailable:   mapped = .newDeviceAvailable
        default:                    mapped = .other
        }
        onInterruption?(.audioRouteChanged(reason: mapped))
    }
    #else
    private func handleInterruption(rawType: UInt?, rawOptions: UInt?) {}
    private func handleRouteChange(rawReason: UInt?) {}
    #endif

    // Called from AVAudioEngine's internal render thread — must be allocation-free.
    // bandScratch is pre-allocated in AmplitudeTapStorage.init and never touched from
    // the main thread, so no lock is needed for it here.
    nonisolated private static func processBuffer(_ buffer: AVAudioPCMBuffer, storage: AmplitudeTapStorage) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }
        let ch0 = channelData[0]
        var rms: Float = 0
        vDSP_rmsqv(ch0, 1, &rms, vDSP_Length(frameLength))
        storage.analyzer.push(samples: ch0, count: frameLength)
        // Write into pre-allocated scratch — zero heap allocation on the render thread.
        storage.analyzer.computeBands(out: &storage.bandScratch)
        storage.writeFromAudioThread(amplitude: min(1, max(0, rms)))
    }

    // No `deinit` here on purpose: engine shutdown and observer removal belong to
    // `EnginePlayerTeardown`, which this class releases on the way out.  The ticker `Task`
    // captures `self` weakly, so it stops on its next iteration.
}
