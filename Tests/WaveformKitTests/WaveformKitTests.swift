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

    // MARK: - MicrophoneInterruption

    func testMicrophoneInterruptionEquality() {
        XCTAssertEqual(MicrophoneInterruption.began, .began)
        XCTAssertEqual(MicrophoneInterruption.ended(shouldResume: true), .ended(shouldResume: true))
        XCTAssertNotEqual(MicrophoneInterruption.ended(shouldResume: true), .ended(shouldResume: false))
        XCTAssertEqual(
            MicrophoneInterruption.audioRouteChanged(reason: .oldDeviceUnavailable),
            MicrophoneInterruption.audioRouteChanged(reason: .oldDeviceUnavailable)
        )
        XCTAssertNotEqual(
            MicrophoneInterruption.audioRouteChanged(reason: .oldDeviceUnavailable),
            MicrophoneInterruption.audioRouteChanged(reason: .newDeviceAvailable)
        )
    }

    @MainActor
    func testMicrophoneRecorderAcceptsInterruptionCallback() {
        var seen: MicrophoneInterruption?
        let r = MicrophoneRecorder(
            autoResumeAfterInterruption: false,
            onInterruption: { event in seen = event }
        )
        XCTAssertFalse(r.autoResumeAfterInterruption)
        XCTAssertNil(seen)
        _ = r
    }

    // MARK: - Demo summary

    func testDemoSummaryShape() {
        let s = WaveformSummary.demo(duration: 30, bars: 100)
        XCTAssertEqual(s.amplitudes.count, 100)
        XCTAssertEqual(s.duration, 30)
        for a in s.amplitudes {
            XCTAssertGreaterThanOrEqual(a, 0)
            XCTAssertLessThanOrEqual(a, 1)
        }
    }

    func testDemoSummaryIsDeterministic() {
        // Same seed should produce identical output across calls — useful for snapshot tests.
        let a = WaveformSummary.demo(duration: 10, bars: 50, seed: 7)
        let b = WaveformSummary.demo(duration: 10, bars: 50, seed: 7)
        XCTAssertEqual(a.amplitudes, b.amplitudes)
    }

    func testDemoSummaryDifferentSeedsDiffer() {
        let a = WaveformSummary.demo(duration: 10, bars: 50, seed: 1)
        let b = WaveformSummary.demo(duration: 10, bars: 50, seed: 2)
        XCTAssertNotEqual(a.amplitudes, b.amplitudes)
    }

    // MARK: - Circular marker hit testing

    func testHitTestCircularPointMarker() {
        // Circular view 200x200, duration 20s. Marker at time=5 → progress=0.25 → angle = 0° (right).
        let m = WaveformMarker(time: 5, color: .red)
        let size = CGSize(width: 200, height: 200)
        // At progress 0.25 (clockwise from top), the outer-ring point is to the right of center.
        // Tap at (190, 100) is on that ring near angle 0 → should hit.
        let hit = WaveformView.hitTestMarker(
            [m],
            at: CGPoint(x: 190, y: 100),
            in: size,
            duration: 20,
            style: .circular()
        )
        XCTAssertEqual(hit?.id, m.id)
    }

    func testHitTestCircularRegionInside() {
        // Region 0..10 spans top→right quadrant. Tap inside that arc range should hit.
        let m = WaveformMarker(time: 0, duration: 10, color: .blue)
        let size = CGSize(width: 200, height: 200)
        // Progress 0.125 (45° from top) → tap location in upper-right quadrant on outer ring.
        let hit = WaveformView.hitTestMarker(
            [m],
            at: CGPoint(x: 170, y: 30),
            in: size,
            duration: 20,
            style: .circular()
        )
        XCTAssertEqual(hit?.id, m.id)
    }

    func testHitTestCircularPickFarsidesAcrossWrap() {
        // Marker at time = 19s of 20s = progress 0.95 → just above the start (top, clockwise from
        // top, 0.95 of the way around). Tap at progress 0.0 (top center) should be close due to
        // wrap-around angular distance (0.05 in progress space ≈ 31 points on a 100-radius ring,
        // outside default 14-point hit radius). Use a tighter mid-radius tap.
        let m = WaveformMarker(time: 19.95, color: .red)
        let size = CGSize(width: 200, height: 200)
        // Tap just to the left of top (progress slightly past 0/wraps near 1)
        let hit = WaveformView.hitTestMarker(
            [m],
            at: CGPoint(x: 100, y: 5),
            in: size,
            duration: 20,
            style: .circular(),
            hitRadius: 30
        )
        XCTAssertEqual(hit?.id, m.id)
    }

    // MARK: - Format time

    func testFormatTimeUnderOneMinute() {
        XCTAssertEqual(WaveformView.formatTime(7), "0:07")
        XCTAssertEqual(WaveformView.formatTime(0), "0:00")
    }

    func testFormatTimeMinutesSeconds() {
        XCTAssertEqual(WaveformView.formatTime(125), "2:05")
    }

    func testFormatTimeHours() {
        XCTAssertEqual(WaveformView.formatTime(3725), "1:02:05")
    }

    // MARK: - Halving

    func testHalveByAveragingEvenLength() {
        let result = MicrophoneRecorder.halveByAveraging([0.2, 0.4, 0.6, 0.8])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0], 0.3, accuracy: 1e-6)
        XCTAssertEqual(result[1], 0.7, accuracy: 1e-6)
    }

    func testHalveByAveragingOddLength() {
        // Odd length: pairs averaged, last element preserved.
        let result = MicrophoneRecorder.halveByAveraging([0.2, 0.4, 0.6, 0.8, 0.9])
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0], 0.3, accuracy: 1e-6)
        XCTAssertEqual(result[1], 0.7, accuracy: 1e-6)
        XCTAssertEqual(result[2], 0.9, accuracy: 1e-6)
    }

    func testHalveByAveragingShortPassthrough() {
        XCTAssertEqual(MicrophoneRecorder.halveByAveraging([0.5]), [0.5])
        XCTAssertEqual(MicrophoneRecorder.halveByAveraging([]), [])
    }

    // MARK: - WaveformSummary integration

    func testDemoSummaryWorksAsWaveformViewInput() {
        let summary: WaveformSummary = .demo()
        XCTAssertGreaterThan(summary.amplitudes.count, 0)
    }

    // MARK: - Per-marker accessibility labels

    func testMarkerAccessibilityLabelWithCustomLabel() {
        let m = WaveformMarker(time: 12, color: .red, label: "Intro")
        XCTAssertEqual(WaveformView.markerAccessibilityLabel(for: m), "Intro, at 0:12")
    }

    func testMarkerAccessibilityLabelWithoutCustomLabel() {
        let m = WaveformMarker(time: 67, color: .red)
        XCTAssertEqual(WaveformView.markerAccessibilityLabel(for: m), "Marker at 1:07")
    }

    func testMarkerAccessibilityLabelRegionWithCustomLabel() {
        let m = WaveformMarker(time: 48, duration: 22, color: .orange, label: "Verse")
        XCTAssertEqual(WaveformView.markerAccessibilityLabel(for: m), "Verse, 0:48 to 1:10")
    }

    func testMarkerAccessibilityLabelRegionWithoutCustomLabel() {
        let m = WaveformMarker(time: 0, duration: 30, color: .blue)
        XCTAssertEqual(WaveformView.markerAccessibilityLabel(for: m), "Region, 0:00 to 0:30")
    }

    func testMarkerAccessibilityLabelWhitespaceLabelFallsBackToDefault() {
        let m = WaveformMarker(time: 5, color: .red, label: "   ")
        XCTAssertEqual(WaveformView.markerAccessibilityLabel(for: m), "Marker at 0:05")
    }

    // MARK: - AudioInterruption shared type

    func testMicrophoneInterruptionIsAliasOfAudioInterruption() {
        let a: AudioInterruption = .began
        let b: MicrophoneInterruption = .began
        XCTAssertEqual(a, b)

        let c: AudioInterruption = .audioRouteChanged(reason: .oldDeviceUnavailable)
        let d: MicrophoneInterruption = .audioRouteChanged(reason: .oldDeviceUnavailable)
        XCTAssertEqual(c, d)
    }

    func testAudioInterruptionEquality() {
        XCTAssertEqual(AudioInterruption.began, .began)
        XCTAssertEqual(AudioInterruption.ended(shouldResume: true), .ended(shouldResume: true))
        XCTAssertNotEqual(AudioInterruption.ended(shouldResume: true), .ended(shouldResume: false))
    }
}
