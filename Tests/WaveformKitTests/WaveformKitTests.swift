import XCTest
import SwiftUI
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

    // MARK: - Marker hit testing

    private let testSize = CGSize(width: 200, height: 60)
    private let testDuration: TimeInterval = 20

    func testHitTestEmptyMarkersReturnsNil() {
        let hit = WaveformView.hitTestMarker(
            [],
            at: CGPoint(x: 100, y: 30),
            in: testSize,
            duration: testDuration,
            style: .bars()
        )
        XCTAssertNil(hit)
    }

    func testHitTestZeroDurationReturnsNil() {
        let m = WaveformMarker(time: 5, color: .red)
        let hit = WaveformView.hitTestMarker(
            [m],
            at: CGPoint(x: 50, y: 30),
            in: testSize,
            duration: 0,
            style: .bars()
        )
        XCTAssertNil(hit)
    }

    func testHitTestPointMarkerExact() {
        let m = WaveformMarker(time: 10, color: .red, label: "mid")
        let hit = WaveformView.hitTestMarker(
            [m],
            at: CGPoint(x: 100, y: 30),
            in: testSize,
            duration: testDuration,
            style: .bars()
        )
        XCTAssertEqual(hit?.id, m.id)
    }

    func testHitTestPointMarkerOutsideRadius() {
        let m = WaveformMarker(time: 10, color: .red)
        let hit = WaveformView.hitTestMarker(
            [m],
            at: CGPoint(x: 130, y: 30),
            in: testSize,
            duration: testDuration,
            style: .bars()
        )
        XCTAssertNil(hit)
    }

    func testHitTestRegionMarkerInside() {
        let m = WaveformMarker(time: 5, duration: 5, color: .blue, label: "chorus")
        let hit = WaveformView.hitTestMarker(
            [m],
            at: CGPoint(x: 70, y: 30),
            in: testSize,
            duration: testDuration,
            style: .bars()
        )
        XCTAssertEqual(hit?.id, m.id)
    }

    func testHitTestRegionMarkerOutsideButWithinEdgeRadius() {
        let m = WaveformMarker(time: 5, duration: 5, color: .blue)
        let hit = WaveformView.hitTestMarker(
            [m],
            at: CGPoint(x: 110, y: 30),
            in: testSize,
            duration: testDuration,
            style: .bars()
        )
        XCTAssertEqual(hit?.id, m.id)
    }

    func testHitTestPicksNearestMarker() {
        let near = WaveformMarker(time: 10, color: .red)
        let far = WaveformMarker(time: 11, color: .green)
        let hit = WaveformView.hitTestMarker(
            [far, near],
            at: CGPoint(x: 102, y: 30),
            in: testSize,
            duration: testDuration,
            style: .bars()
        )
        XCTAssertEqual(hit?.id, near.id)
    }

    func testHitTestSkipsCircularStyle() {
        let m = WaveformMarker(time: 10, color: .red)
        let hit = WaveformView.hitTestMarker(
            [m],
            at: CGPoint(x: 100, y: 30),
            in: testSize,
            duration: testDuration,
            style: .circular()
        )
        XCTAssertNil(hit)
    }

    func testMarkerIsRegion() {
        XCTAssertFalse(WaveformMarker(time: 1, color: .red).isRegion)
        XCTAssertTrue(WaveformMarker(time: 1, duration: 2, color: .red).isRegion)
    }

    func testMarkerClampsNegativeDuration() {
        let m = WaveformMarker(time: 1, duration: -5, color: .red)
        XCTAssertEqual(m.duration, 0)
        XCTAssertFalse(m.isRegion)
    }

    // MARK: - FFT band edges

    func testFFTBandEdgesCount() {
        let edges = FFTAnalyzer.computeBandEdges(fftSize: 1024, bandCount: 32, sampleRate: 44100)
        XCTAssertEqual(edges.count, 33)
    }

    func testFFTBandEdgesAreMonotonicallyNonDecreasing() {
        let edges = FFTAnalyzer.computeBandEdges(fftSize: 1024, bandCount: 32, sampleRate: 48000)
        for i in 1..<edges.count {
            XCTAssertGreaterThanOrEqual(edges[i], edges[i - 1])
        }
    }

    func testFFTBandEdgesStayWithinFFTBins() {
        let edges = FFTAnalyzer.computeBandEdges(fftSize: 1024, bandCount: 32, sampleRate: 96000)
        let half = 1024 / 2
        for e in edges {
            XCTAssertGreaterThanOrEqual(e, 1)
            XCTAssertLessThanOrEqual(e, half - 1)
        }
    }

    func testFFTBandEdgesDifferAcrossSampleRates() {
        let e44 = FFTAnalyzer.computeBandEdges(fftSize: 1024, bandCount: 32, sampleRate: 44100)
        let e96 = FFTAnalyzer.computeBandEdges(fftSize: 1024, bandCount: 32, sampleRate: 96000)
        XCTAssertNotEqual(e44, e96)
    }

    func testFFTUpdateSampleRateChangesEdges() {
        let analyzer = FFTAnalyzer(fftSize: 1024, bandCount: 32, sampleRate: 44100)
        let original = analyzer.sampleRate
        analyzer.updateSampleRate(48000)
        XCTAssertEqual(analyzer.sampleRate, 48000)
        XCTAssertNotEqual(analyzer.sampleRate, original)
    }

    func testFFTUpdateSampleRateNoOpForIdenticalRate() {
        let analyzer = FFTAnalyzer(fftSize: 1024, bandCount: 32, sampleRate: 44100)
        analyzer.updateSampleRate(44100)
        XCTAssertEqual(analyzer.sampleRate, 44100)
    }
}
