import XCTest
@testable import WaveformKit

final class WaveformKitTests: XCTestCase {
    func testSummaryConstruction() {
        let s = WaveformSummary(
            amplitudes: [0.1, 0.5, 0.9],
            duration: 10,
            sampleRate: 44100,
            channelCount: 2
        )
        XCTAssertEqual(s.amplitudes.count, 3)
        XCTAssertEqual(s.duration, 10)
    }

    func testEmptySummary() {
        XCTAssertEqual(WaveformSummary.empty.amplitudes.count, 0)
        XCTAssertEqual(WaveformSummary.empty.duration, 0)
    }

    // MARK: - Idle shimmer

    func testIdleProgressStartsAtZero() {
        XCTAssertEqual(WaveformView.idleProgress(at: 0, cycle: 2.5), 0, accuracy: 1e-9)
    }

    func testIdleProgressPeaksAtHalfCycle() {
        let cycle: TimeInterval = 2.5
        XCTAssertEqual(WaveformView.idleProgress(at: cycle / 2, cycle: cycle), 1, accuracy: 1e-9)
    }

    func testIdleProgressReturnsToZeroAtFullCycle() {
        let cycle: TimeInterval = 2.5
        XCTAssertEqual(WaveformView.idleProgress(at: cycle, cycle: cycle), 0, accuracy: 1e-9)
    }

    func testIdleProgressBounded() {
        // Sample 200 points across two cycles, all must stay within [0, 1].
        for i in 0..<200 {
            let t = TimeInterval(i) * 0.05
            let p = WaveformView.idleProgress(at: t, cycle: 2.5)
            XCTAssertGreaterThanOrEqual(p, 0)
            XCTAssertLessThanOrEqual(p, 1)
        }
    }

    func testIdleProgressZeroCycleIsSafe() {
        XCTAssertEqual(WaveformView.idleProgress(at: 1.0, cycle: 0), 0)
    }

    // MARK: - Idle placeholder

    func testPlaceholderAmplitudesCount() {
        XCTAssertEqual(WaveformView.placeholderAmplitudes(count: 50).count, 50)
        XCTAssertEqual(WaveformView.placeholderAmplitudes(count: 0).count, 0)
    }

    func testPlaceholderAmplitudesBounded() {
        for a in WaveformView.placeholderAmplitudes(count: 200) {
            XCTAssertGreaterThanOrEqual(a, 0)
            XCTAssertLessThanOrEqual(a, 1)
        }
    }

    // MARK: - MicrophoneRecorder

    @MainActor
    func testMicrophoneRecorderInitialState() {
        let r = MicrophoneRecorder(bandCount: 16, binsPerSecond: 10)
        XCTAssertFalse(r.isRecording)
        XCTAssertFalse(r.isPaused)
        XCTAssertEqual(r.currentTime, 0)
        XCTAssertEqual(r.currentAmplitude, 0)
        XCTAssertEqual(r.bands.count, 16)
        XCTAssertEqual(r.summary.amplitudes.count, 0)
        XCTAssertNil(r.lastError)
        XCTAssertNil(r.recordedFileURL)
        XCTAssertFalse(r.isPlaying)
    }

    @MainActor
    func testMicrophoneRecorderSeekIsNoOp() {
        let r = MicrophoneRecorder()
        r.seek(to: 99)
        XCTAssertEqual(r.currentTime, 0)
    }

    @MainActor
    func testMicrophoneRecorderResetWithoutStartIsSafe() {
        let r = MicrophoneRecorder(bandCount: 8)
        r.reset()
        XCTAssertFalse(r.isRecording)
        XCTAssertEqual(r.bands.count, 8)
    }
}
