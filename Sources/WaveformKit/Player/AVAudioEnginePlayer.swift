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
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var amplitudeEnvelope = AmplitudeEnvelope()
    @ObservationIgnored private var bandEnvelopes: [AmplitudeEnvelope]
    @ObservationIgnored private var seekOffset: TimeInterval = 0
    @ObservationIgnored private var tapInstalled = false
    @ObservationIgnored private let onInterruption: (@MainActor (AudioInterruption) -> Void)?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    @ObservationIgnored private var routeObserver: NSObjectProtocol?
    @ObservationIgnored private var wasPlayingBeforeInterruption: Bool = false

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
        timer?.invalidate()
        timer = nil
    }

    /// Stop playback and reset to the beginning. Different from `pause()`: drains the scheduled
    /// buffer and re-schedules from t = 0, so the next `play()` starts cleanly from the top.
    public func stop() {
        playerNode.stop()
        isPlaying = false
        timer?.invalidate()
        timer = nil
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
        timer?.invalidate()
        timer = nil
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
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
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
        guard interruptionObserver == nil else { return }
        let center = NotificationCenter.default
        interruptionObserver = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let userInfo = note.userInfo
            Task { @MainActor [weak self] in
                self?.handleInterruption(userInfo: userInfo)
            }
        }
        routeObserver = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let userInfo = note.userInfo
            Task { @MainActor [weak self] in
                self?.handleRouteChange(userInfo: userInfo)
            }
        }
        #endif
    }

    private func removeSystemObservers() {
        let center = NotificationCenter.default
        if let o = interruptionObserver { center.removeObserver(o) }
        if let o = routeObserver { center.removeObserver(o) }
        interruptionObserver = nil
        routeObserver = nil
    }

    #if os(iOS) || os(tvOS) || os(visionOS)
    private func handleInterruption(userInfo: [AnyHashable: Any]?) {
        guard let userInfo,
              let raw = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            if isPlaying {
                wasPlayingBeforeInterruption = true
                playerNode.pause()
                isPlaying = false
                timer?.invalidate()
                timer = nil
            }
            onInterruption?(.began)
        case .ended:
            let optsRaw = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let opts = AVAudioSession.InterruptionOptions(rawValue: optsRaw)
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

    private func handleRouteChange(userInfo: [AnyHashable: Any]?) {
        guard let userInfo,
              let raw = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        let mapped: AudioInterruption.RouteChangeReason
        switch reason {
        case .oldDeviceUnavailable: mapped = .oldDeviceUnavailable
        case .newDeviceAvailable:   mapped = .newDeviceAvailable
        default:                    mapped = .other
        }
        onInterruption?(.audioRouteChanged(reason: mapped))
    }
    #else
    private func handleInterruption(userInfo: [AnyHashable: Any]?) {}
    private func handleRouteChange(userInfo: [AnyHashable: Any]?) {}
    #endif

    nonisolated private static func processBuffer(_ buffer: AVAudioPCMBuffer, storage: AmplitudeTapStorage) {
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
    }

    deinit {
        timer?.invalidate()
        let center = NotificationCenter.default
        if let o = interruptionObserver { center.removeObserver(o) }
        if let o = routeObserver { center.removeObserver(o) }
        if engine.isRunning {
            playerNode.stop()
            engine.stop()
        }
    }
}
