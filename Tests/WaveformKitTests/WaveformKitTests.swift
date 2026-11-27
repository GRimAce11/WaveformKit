import XCTest
import SwiftUI
import AVFoundation
#if canImport(Metal)
import Metal
#endif
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

    // MARK: - FFT correctness

    /// A full-scale 1 kHz sine pushed into a fresh FFTAnalyzer must produce a visible peak
    /// in the mid-frequency bands (roughly bands 15–20 at 44.1 kHz with 32 log-spaced bands)
    /// and near-silence in the sub-bass and near-Nyquist extremes.
    ///
    /// This test also exercises the optimised push() block-copy path: the entire fftSize window
    /// is pushed in a single call, which uses the single-segment (no-wrap) branch.
    func testFFTSineWaveCorrectness_1kHz() {
        let fftSize = 1024
        let sampleRate: Float = 44100
        let testFreq: Float = 1000
        let analyzer = FFTAnalyzer(fftSize: fftSize, bandCount: 32, sampleRate: sampleRate)

        // Generate exactly one FFT window of a full-scale 1 kHz sine.
        var sine = [Float](repeating: 0, count: fftSize)
        for i in 0..<fftSize {
            sine[i] = sinf(2 * .pi * testFreq * Float(i) / sampleRate)
        }
        sine.withUnsafeBufferPointer { buf in
            _ = analyzer.push(samples: buf.baseAddress!, count: fftSize)
        }

        var bands = [Float](repeating: 0, count: 32)
        analyzer.computeBands(out: &bands)

        // ── Peak should be in the mid bands ──────────────────────────────────────────────
        // At 44.1 kHz, 1 kHz maps to FFT bin ≈ 23 (1000 * 1024 / 44100).
        // With 32 log-spaced bands from 40 Hz to 16 kHz, that bin falls in bands 15–20.
        let peakIdx = bands.indices.max(by: { bands[$0] < bands[$1] })!
        XCTAssertGreaterThan(bands[peakIdx], 0.3,
            "Peak band \(peakIdx) should show strong energy for a full-scale 1 kHz sine (got \(bands[peakIdx]))")
        XCTAssertTrue((10...24).contains(peakIdx),
            "1 kHz peak should land in bands 10–24, got band \(peakIdx)")

        // ── Sub-bass and near-Nyquist should be silent ──────────────────────────────────
        XCTAssertLessThan(bands[0], 0.05,
            "Band 0 (sub-bass) should be near silence for a 1 kHz sine (got \(bands[0]))")
        XCTAssertLessThan(bands[31], 0.05,
            "Band 31 (near-Nyquist) should be near silence for a 1 kHz sine (got \(bands[31]))")
    }

    /// Verify that pushing the same signal in two equal halves produces identical FFT output
    /// to a single full-window push.  This exercises the ring buffer's wrap-around branch
    /// (second half triggers the two-segment block-copy path in push()).
    func testFFTRingBufferWrapAroundConsistency() {
        let fftSize = 1024
        let sampleRate: Float = 44100
        let testFreq: Float = 440   // A4

        // Build a reference signal.
        var signal = [Float](repeating: 0, count: fftSize)
        for i in 0..<fftSize {
            signal[i] = sinf(2 * .pi * testFreq * Float(i) / sampleRate)
        }

        // Reference: single full-window push.
        let refAnalyzer = FFTAnalyzer(fftSize: fftSize, bandCount: 32, sampleRate: sampleRate)
        signal.withUnsafeBufferPointer { buf in
            _ = refAnalyzer.push(samples: buf.baseAddress!, count: fftSize)
        }
        var refBands = [Float](repeating: 0, count: 32)
        refAnalyzer.computeBands(out: &refBands)

        // Under test: push in two halves so the second push wraps around the ring boundary.
        let testAnalyzer = FFTAnalyzer(fftSize: fftSize, bandCount: 32, sampleRate: sampleRate)
        let half = fftSize / 2
        signal.withUnsafeBufferPointer { buf in
            _ = testAnalyzer.push(samples: buf.baseAddress!,        count: half)
            _ = testAnalyzer.push(samples: buf.baseAddress! + half, count: half)
        }
        var testBands = [Float](repeating: 0, count: 32)
        testAnalyzer.computeBands(out: &testBands)

        // Both paths must produce bit-identical output because the ring contents are identical.
        for i in 0..<32 {
            XCTAssertEqual(refBands[i], testBands[i], accuracy: 1e-5,
                "Band \(i): single-push \(refBands[i]) vs split-push \(testBands[i])")
        }
    }

    /// Push in four unequal chunks to exercise multiple wrap points and confirm the
    /// band output still matches a single-pass reference.
    func testFFTRingBufferMultiChunkConsistency() {
        let fftSize = 1024
        let sampleRate: Float = 44100

        var signal = [Float](repeating: 0, count: fftSize)
        for i in 0..<fftSize { signal[i] = sinf(2 * .pi * 880 * Float(i) / sampleRate) }

        let refAnalyzer = FFTAnalyzer(fftSize: fftSize, bandCount: 32, sampleRate: sampleRate)
        signal.withUnsafeBufferPointer { buf in
            _ = refAnalyzer.push(samples: buf.baseAddress!, count: fftSize)
        }
        var refBands = [Float](repeating: 0, count: 32)
        refAnalyzer.computeBands(out: &refBands)

        // Chunk sizes chosen so wrap occurs in the middle of a chunk (not at a boundary).
        let chunks = [256, 300, 212, 256]
        assert(chunks.reduce(0, +) == fftSize)

        let testAnalyzer = FFTAnalyzer(fftSize: fftSize, bandCount: 32, sampleRate: sampleRate)
        var offset = 0
        signal.withUnsafeBufferPointer { buf in
            for size in chunks {
                testAnalyzer.push(samples: buf.baseAddress! + offset, count: size)
                offset += size
            }
        }
        var testBands = [Float](repeating: 0, count: 32)
        testAnalyzer.computeBands(out: &testBands)

        for i in 0..<32 {
            XCTAssertEqual(refBands[i], testBands[i], accuracy: 1e-5,
                "Band \(i) mismatch between single-push and 4-chunk push")
        }
    }

    // MARK: - FFT performance benchmarks

    /// Establishes an upper-bound performance budget for computeBands().
    ///
    /// Rationale: at 44.1 kHz with a 1024-frame tap buffer, the audio render thread fires
    /// ~43 times per second.  Each callback has an ~23 ms budget (1000 ms / 43).  The FFT
    /// should consume well under 1% of that budget — i.e., < 230 µs.  We set a conservative
    /// hard limit of 200 µs to leave headroom for slower CI machines.
    ///
    /// This test will fail on Simulator (which runs no real-time audio) if the machine is
    /// unusually loaded; treat failures as a signal to profile, not as a correctness regression.
    func testComputeBandsPerformanceBudget() {
        let fftSize = 1024
        let analyzer = FFTAnalyzer(fftSize: fftSize, bandCount: 32, sampleRate: 44100)

        // Fill ring with band-limited noise so all bands register something.
        var noise = [Float](repeating: 0, count: fftSize)
        var rng: UInt64 = 0xDEADBEEF_CAFEBABE
        for i in 0..<fftSize {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            noise[i] = Float(Int64(bitPattern: rng)) / Float(Int64.max)
        }
        noise.withUnsafeBufferPointer { buf in
            _ = analyzer.push(samples: buf.baseAddress!, count: fftSize)
        }

        var bands = [Float](repeating: 0, count: 32)
        let iterations = 10_000

        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations {
            analyzer.computeBands(out: &bands)
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        let usPerCall = (elapsed / Double(iterations)) * 1_000_000
        // Budget: 200 µs.  This is ~10× more conservative than the 23 ms callback period
        // to ensure the FFT remains a negligible fraction of render-thread work.
        XCTAssertLessThan(usPerCall, 200,
            String(format: "computeBands exceeded 200 µs budget: %.1f µs/call", usPerCall))
    }

    /// Measures the push() throughput with a 512-frame buffer (typical AVAudioEngine delivery).
    ///
    /// The optimised block-copy implementation should complete in < 5 µs for 512 Float samples
    /// on any Apple Silicon or A-series device.  The budget below is deliberately generous
    /// (20 µs) to pass on CI machines and simulators without false failures.
    func testPushPerformanceBudget() {
        let fftSize = 1024
        let analyzer = FFTAnalyzer(fftSize: fftSize, bandCount: 32, sampleRate: 44100)

        // 512-frame buffer: exercises the split-copy (wrap-around) path on alternate calls.
        var samples = [Float](repeating: 0, count: 512)
        for i in 0..<512 { samples[i] = Float(i) / 512.0 }

        let iterations = 50_000

        let start = CFAbsoluteTimeGetCurrent()
        samples.withUnsafeBufferPointer { buf in
            for _ in 0..<iterations {
                analyzer.push(samples: buf.baseAddress!, count: 512)
            }
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        let usPerCall = (elapsed / Double(iterations)) * 1_000_000
        XCTAssertLessThan(usPerCall, 20,
            String(format: "push(512) exceeded 20 µs budget: %.2f µs/call", usPerCall))
    }

    // MARK: - WaveformSummary identity (Phase 2)

    func testSummaryIDIsUniquePerInstance() {
        let a = WaveformSummary(amplitudes: [0.5], duration: 1, sampleRate: 44100, channelCount: 1)
        let b = WaveformSummary(amplitudes: [0.5], duration: 1, sampleRate: 44100, channelCount: 1)
        XCTAssertNotEqual(a.id, b.id, "Two separate init() calls must produce distinct UUIDs")
    }

    func testSummaryIDIsStableOnSameInstance() {
        let s = WaveformSummary(amplitudes: [0.1, 0.9], duration: 5, sampleRate: 44100, channelCount: 1)
        XCTAssertEqual(s.id, s.id, "id must be stable on the same instance")
    }

    func testSummaryEquatableIgnoresID() {
        // Two instances with identical data but necessarily different UUIDs must be equal.
        let a = WaveformSummary(amplitudes: [0.1, 0.5, 0.9], duration: 10, sampleRate: 44100, channelCount: 1)
        let b = WaveformSummary(amplitudes: [0.1, 0.5, 0.9], duration: 10, sampleRate: 44100, channelCount: 1)
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(a, b, "== must not compare id")
    }

    func testSummaryDecodesWithFreshID() throws {
        let original = WaveformSummary(amplitudes: [0.2, 0.8], duration: 3, sampleRate: 48000, channelCount: 2)
        let data     = try JSONEncoder().encode(original)
        let decoded  = try JSONDecoder().decode(WaveformSummary.self, from: data)
        XCTAssertEqual(original, decoded, "Round-trip must preserve data equality")
        XCTAssertNotEqual(original.id, decoded.id, "Decoded instance must have a fresh UUID")
        XCTAssertFalse(data.description.contains(original.id.uuidString),
                       "id must not appear in the encoded JSON")
    }

    // MARK: - WaveformState (Phase 2)

    func testWaveformStateIdleHasNilSummary() {
        let s: WaveformState = .idle
        XCTAssertNil(s.summary)
        XCTAssertFalse(s.isLoading)
        XCTAssertNil(s.loadingProgress)
        XCTAssertNil(s.error)
    }

    func testWaveformStateLoadingProperties() {
        let s: WaveformState = .loading(progress: 0.42)
        XCTAssertNil(s.summary)
        XCTAssertTrue(s.isLoading)
        XCTAssertEqual(s.loadingProgress ?? -1, 0.42, accuracy: 1e-6)
        XCTAssertNil(s.error)
    }

    func testWaveformStateLoadedProperties() {
        let summary = WaveformSummary.demo(bars: 10)
        let s: WaveformState = .loaded(summary)
        XCTAssertEqual(s.summary?.id, summary.id)
        XCTAssertFalse(s.isLoading)
        XCTAssertNil(s.loadingProgress)
        XCTAssertNil(s.error)
    }

    func testWaveformStateFailedProperties() {
        struct FakeError: Error {}
        let s: WaveformState = .failed(FakeError())
        XCTAssertNil(s.summary)
        XCTAssertFalse(s.isLoading)
        XCTAssertNil(s.loadingProgress)
        XCTAssertNotNil(s.error)
    }

    // MARK: - WaveformLoader (Phase 2)

    @MainActor
    func testWaveformLoaderInitialStateIsIdle() {
        let loader = WaveformLoader()
        XCTAssertFalse(loader.state.isLoading)
        XCTAssertNil(loader.state.summary)
    }

    @MainActor
    func testWaveformLoaderSetInjectsSummaryDirectly() {
        let loader  = WaveformLoader()
        let summary = WaveformSummary.demo(bars: 20)
        loader.set(summary)
        XCTAssertEqual(loader.state.summary?.id, summary.id)
    }

    @MainActor
    func testWaveformLoaderCancelFromIdleIsSafe() {
        let loader = WaveformLoader()
        loader.cancel()  // must not crash
        XCTAssertFalse(loader.state.isLoading)
    }

    @MainActor
    func testWaveformLoaderRetryFromIdleIsNoOp() {
        let loader = WaveformLoader()
        loader.retry()   // must not crash; no lastURL stored
        XCTAssertFalse(loader.state.isLoading)
    }

    // MARK: - WaveformViewport (Phase 2)

    func testViewportInitShowsFullRange() {
        let vp = WaveformViewport(duration: 120)
        XCTAssertEqual(vp.visibleRange.lowerBound, 0, accuracy: 1e-9)
        XCTAssertEqual(vp.visibleRange.upperBound, 120, accuracy: 1e-9)
        XCTAssertEqual(vp.zoomFactor, 1, accuracy: 1e-9)
        XCTAssertFalse(vp.isZoomed)
    }

    func testViewportZoomDoublesZoomFactor() {
        var vp = WaveformViewport(duration: 120)
        vp.zoom(to: 2, anchor: 0.5)
        XCTAssertEqual(vp.zoomFactor, 2, accuracy: 0.01)
        XCTAssertTrue(vp.isZoomed)
        // Visible span should be half the duration.
        let span = vp.visibleRange.upperBound - vp.visibleRange.lowerBound
        XCTAssertEqual(span, 60, accuracy: 0.1)
    }

    func testViewportZoomCentredOnAnchor() {
        var vp = WaveformViewport(duration: 100)
        // Zoom 4× centred on the right edge of the current range (anchor = 1.0).
        vp.zoom(to: 4, anchor: 1.0)
        let span = vp.visibleRange.upperBound - vp.visibleRange.lowerBound
        XCTAssertEqual(span, 25, accuracy: 0.1)
        // The right boundary should stay at 100 (clamped to duration).
        XCTAssertEqual(vp.visibleRange.upperBound, 100, accuracy: 0.1)
    }

    func testViewportPanShiftsRange() {
        var vp = WaveformViewport(duration: 100)
        vp.zoom(to: 4)          // span = 25 s, centred
        let before = vp.visibleRange.lowerBound
        vp.pan(by: 10)
        XCTAssertEqual(vp.visibleRange.lowerBound, before + 10, accuracy: 0.1)
    }

    func testViewportPanClampsAtEnd() {
        var vp = WaveformViewport(duration: 60)
        vp.zoom(to: 2)          // span = 30 s
        vp.pan(by: 1000)        // try to pan way past the end
        XCTAssertEqual(vp.visibleRange.upperBound, 60, accuracy: 0.1)
    }

    func testViewportPanClampsAtStart() {
        var vp = WaveformViewport(duration: 60)
        vp.zoom(to: 2)
        vp.pan(by: -1000)
        XCTAssertEqual(vp.visibleRange.lowerBound, 0, accuracy: 0.1)
    }

    func testViewportResetZoom() {
        var vp = WaveformViewport(duration: 90)
        vp.zoom(to: 5)
        XCTAssertTrue(vp.isZoomed)
        vp.resetZoom()
        XCTAssertFalse(vp.isZoomed)
        XCTAssertEqual(vp.zoomFactor, 1, accuracy: 1e-9)
    }

    func testViewportVisibleIndicesFullRange() {
        let vp = WaveformViewport(duration: 30)
        let indices = vp.visibleIndices(totalBars: 200)
        XCTAssertEqual(indices, 0..<200)
    }

    func testViewportVisibleIndicesZoomed() {
        var vp = WaveformViewport(duration: 100)
        // Show only the first 50 % of the waveform.
        vp.visibleRange = 0...50
        let indices = vp.visibleIndices(totalBars: 200)
        // Normalised range is [0, 0.5], so we expect bars 0..<100.
        XCTAssertEqual(indices.lowerBound, 0)
        XCTAssertLessThanOrEqual(indices.upperBound, 101)  // allow ±1 for rounding
        XCTAssertGreaterThanOrEqual(indices.upperBound, 99)
    }

    func testViewportNormalisedRange() {
        var vp = WaveformViewport(duration: 200)
        vp.visibleRange = 50...150
        let norm = vp.normalizedRange
        XCTAssertEqual(norm.lowerBound, 0.25, accuracy: 1e-9)
        XCTAssertEqual(norm.upperBound, 0.75, accuracy: 1e-9)
    }

    func testViewportTimeForVisibleProgress() {
        var vp = WaveformViewport(duration: 100)
        vp.visibleRange = 20...60
        let t = vp.time(forVisibleProgress: 0.5)
        XCTAssertEqual(t, 40, accuracy: 1e-9)  // midpoint of [20, 60]
    }

    func testViewportVisibleProgressForTime() {
        var vp = WaveformViewport(duration: 100)
        vp.visibleRange = 20...60
        XCTAssertEqual(vp.visibleProgress(for: 20) ?? -1, 0,   accuracy: 1e-9)
        XCTAssertEqual(vp.visibleProgress(for: 60) ?? -1, 1,   accuracy: 1e-9)
        XCTAssertEqual(vp.visibleProgress(for: 40) ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertNil(vp.visibleProgress(for: 10), "Time outside visible range should return nil")
        XCTAssertNil(vp.visibleProgress(for: 80), "Time outside visible range should return nil")
    }

    // MARK: - resampleAmplitudes (Phase 2)

    func testResampleToSameCount() {
        let src: [Float] = [0.1, 0.2, 0.3, 0.4]
        let result = resampleAmplitudes(src: src, startIdx: 0, endIdx: 4, targetCount: 4)
        XCTAssertEqual(result, src)
    }

    func testResampleDownsampleMean() {
        // 4 bins → 2 bins: each output is the mean of 2 input bins.
        let src: [Float] = [0.2, 0.4, 0.6, 0.8]
        let result = resampleAmplitudes(src: src, startIdx: 0, endIdx: 4, targetCount: 2, mode: .mean)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0], 0.3, accuracy: 1e-5)
        XCTAssertEqual(result[1], 0.7, accuracy: 1e-5)
    }

    func testResampleDownsamplePeak() {
        // Same input, peak pooling: each output is the loudest of the 2 bins it covers.
        let src: [Float] = [0.2, 0.4, 0.6, 0.8]
        let result = resampleAmplitudes(src: src, startIdx: 0, endIdx: 4, targetCount: 2, mode: .peak)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0], 0.4, accuracy: 1e-5)
        XCTAssertEqual(result[1], 0.8, accuracy: 1e-5)
    }

    func testResampleDefaultsToPeak() {
        let src: [Float] = [0.2, 0.4, 0.6, 0.8]
        let explicit = resampleAmplitudes(src: src, startIdx: 0, endIdx: 4, targetCount: 2, mode: .peak)
        let implicit = resampleAmplitudes(src: src, startIdx: 0, endIdx: 4, targetCount: 2)
        XCTAssertEqual(explicit, implicit)
    }

    func testResamplePeakPreservesTransient() {
        // One loud spike buried in a quiet run: the reason peak is the default.  Mean pooling
        // dilutes it by the bin count; peak keeps it at full height.
        var src = [Float](repeating: 0.1, count: 64)
        src[20] = 1.0
        let peak = resampleAmplitudes(src: src, startIdx: 0, endIdx: 64, targetCount: 8, mode: .peak)
        let mean = resampleAmplitudes(src: src, startIdx: 0, endIdx: 64, targetCount: 8, mode: .mean)

        XCTAssertEqual(peak.max() ?? 0, 1.0, accuracy: 1e-5, "Peak pooling must keep the spike")
        XCTAssertLessThan(mean.max() ?? 0, 0.3, "Mean pooling averages the spike away")
    }

    func testResampleModesAgreeWhenNoPooling() {
        // Upsampling gives every output bar a single source bin, so both modes must match.
        let src: [Float] = [0.2, 0.8]
        XCTAssertEqual(
            resampleAmplitudes(src: src, startIdx: 0, endIdx: 2, targetCount: 4, mode: .peak),
            resampleAmplitudes(src: src, startIdx: 0, endIdx: 2, targetCount: 4, mode: .mean)
        )
    }

    func testResampleCacheKeyIncludesMode() {
        // Without mode in the key, switching modes would return the previous mode's array.
        let cache = ResampleCache()
        let id = UUID()
        cache.set([0.9], summaryID: id, count: 1, startIdx: 0, endIdx: 4, mode: .peak)
        XCTAssertNil(cache.get(summaryID: id, count: 1, startIdx: 0, endIdx: 4, mode: .mean))
        XCTAssertEqual(cache.get(summaryID: id, count: 1, startIdx: 0, endIdx: 4, mode: .peak), [0.9])
    }

    func testResampleUpsample() {
        // 2 bins → 4 bins: each input bin maps to 2 output bins.
        let src: [Float] = [0.2, 0.8]
        let result = resampleAmplitudes(src: src, startIdx: 0, endIdx: 2, targetCount: 4)
        XCTAssertEqual(result.count, 4)
        // First two outputs come from bin 0 (0.2), last two from bin 1 (0.8).
        XCTAssertEqual(result[0], 0.2, accuracy: 1e-5)
        XCTAssertEqual(result[1], 0.2, accuracy: 1e-5)
        XCTAssertEqual(result[2], 0.8, accuracy: 1e-5)
        XCTAssertEqual(result[3], 0.8, accuracy: 1e-5)
    }

    func testResampleViewportSlice() {
        let src: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6]
        // Extract bars 2..<4 (values 0.3, 0.4) and resample to 2 bars.
        let result = resampleAmplitudes(src: src, startIdx: 2, endIdx: 4, targetCount: 2)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0], 0.3, accuracy: 1e-5)
        XCTAssertEqual(result[1], 0.4, accuracy: 1e-5)
    }

    func testResampleEmptySliceReturnsEmpty() {
        let src: [Float] = [0.5, 0.5, 0.5]
        XCTAssertEqual(resampleAmplitudes(src: src, startIdx: 2, endIdx: 2, targetCount: 4), [])
        XCTAssertEqual(resampleAmplitudes(src: src, startIdx: 0, endIdx: 3, targetCount: 0), [])
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

    // MARK: - ResampleCache LRU (Phase 3)

    func testResampleCacheStoresAndReturns() {
        let cache = ResampleCache()
        let id = UUID()
        cache.set([0.1, 0.2], summaryID: id, count: 2, startIdx: 0, endIdx: 10, mode: .peak)
        XCTAssertEqual(cache.get(summaryID: id, count: 2, startIdx: 0, endIdx: 10, mode: .peak), [0.1, 0.2])
    }

    func testResampleCacheMissesOnDifferentSlice() {
        let cache = ResampleCache()
        let id = UUID()
        cache.set([0.1, 0.2], summaryID: id, count: 2, startIdx: 0, endIdx: 10, mode: .peak)
        XCTAssertNil(cache.get(summaryID: id, count: 2, startIdx: 1, endIdx: 10, mode: .peak))
        XCTAssertNil(cache.get(summaryID: id, count: 3, startIdx: 0, endIdx: 10, mode: .peak))
    }

    func testResampleCacheDropsEverythingOnNewSummary() {
        let cache = ResampleCache()
        let first = UUID()
        cache.set([0.1], summaryID: first, count: 1, startIdx: 0, endIdx: 10, mode: .peak)
        cache.set([0.2], summaryID: UUID(), count: 1, startIdx: 0, endIdx: 10, mode: .peak)
        XCTAssertEqual(cache.count, 1, "A new summary should evict every entry from the old one")
        XCTAssertNil(cache.get(summaryID: first, count: 1, startIdx: 0, endIdx: 10, mode: .peak))
    }

    func testResampleCacheStaysBoundedUnderPinch() {
        // Simulates a live pinch: every frame asks for a slightly different visible slice.
        // Before the LRU bound this grew one permanent entry per frame.
        let cache = ResampleCache(capacity: 8)
        let id = UUID()
        for frame in 0..<200 {
            cache.set([Float(frame)], summaryID: id, count: 100, startIdx: frame, endIdx: 500 - frame, mode: .peak)
        }
        XCTAssertEqual(cache.count, 8, "Cache must not grow past its capacity during a gesture")
    }

    func testResampleCacheEvictsLeastRecentlyUsed() {
        let cache = ResampleCache(capacity: 2)
        let id = UUID()
        cache.set([1], summaryID: id, count: 1, startIdx: 0, endIdx: 1, mode: .peak)
        cache.set([2], summaryID: id, count: 1, startIdx: 0, endIdx: 2, mode: .peak)
        // Touch the first entry so the second becomes the least recently used.
        _ = cache.get(summaryID: id, count: 1, startIdx: 0, endIdx: 1, mode: .peak)
        cache.set([3], summaryID: id, count: 1, startIdx: 0, endIdx: 3, mode: .peak)

        XCTAssertEqual(cache.count, 2)
        XCTAssertEqual(cache.get(summaryID: id, count: 1, startIdx: 0, endIdx: 1, mode: .peak), [1],
                       "Recently read entry should survive")
        XCTAssertNil(cache.get(summaryID: id, count: 1, startIdx: 0, endIdx: 2, mode: .peak),
                     "Least recently used entry should have been evicted")
        XCTAssertEqual(cache.get(summaryID: id, count: 1, startIdx: 0, endIdx: 3, mode: .peak), [3])
    }

    func testResampleCacheCapacityIsAtLeastOne() {
        let cache = ResampleCache(capacity: 0)
        let id = UUID()
        cache.set([1], summaryID: id, count: 1, startIdx: 0, endIdx: 1, mode: .peak)
        XCTAssertEqual(cache.count, 1)
    }

    // MARK: - WaveformZoomOptions (Phase 3)

    func testZoomOptionsDefaultsPreserveSeekBehaviour() {
        let options = WaveformZoomOptions()
        XCTAssertTrue(options.isEnabled)
        XCTAssertEqual(options.dragBehavior, .seek)
        XCTAssertFalse(options.yieldsToVerticalScroll)
        XCTAssertTrue(options.resetsOnDoubleTap)
    }

    func testZoomOptionsPresets() {
        XCTAssertFalse(WaveformZoomOptions.disabled.isEnabled)
        XCTAssertEqual(WaveformZoomOptions.editor.dragBehavior, .panWhenZoomed)
        XCTAssertTrue(WaveformZoomOptions.inScrollView.yieldsToVerticalScroll)
    }

    func testZoomOptionsClampsNonsenseInput() {
        let options = WaveformZoomOptions(
            maxZoomFactor: 0.2, minVisibleDuration: -5, scrollIntentThreshold: -3
        )
        XCTAssertEqual(options.maxZoomFactor, 1, "Zoom factor below 1× is not a zoom")
        XCTAssertEqual(options.minVisibleDuration, 0)
        XCTAssertEqual(options.scrollIntentThreshold, 0)
    }

    func testZoomTargetMultipliesBaseByMagnification() {
        let options = WaveformZoomOptions(maxZoomFactor: 50)
        XCTAssertEqual(options.zoomTarget(base: 2, magnification: 3), 6, accuracy: 1e-9)
        XCTAssertEqual(options.zoomTarget(base: 4, magnification: 0.5), 2, accuracy: 1e-9)
    }

    func testZoomTargetClampsToBounds() {
        let options = WaveformZoomOptions(maxZoomFactor: 10)
        XCTAssertEqual(options.zoomTarget(base: 8, magnification: 100), 10, accuracy: 1e-9,
                       "Must not exceed maxZoomFactor")
        XCTAssertEqual(options.zoomTarget(base: 2, magnification: 0.001), 1, accuracy: 1e-9,
                       "Must not zoom out past the full duration")
    }

    func testCrownZoomIsExponentialAndClamped() {
        let options = WaveformZoomOptions(maxZoomFactor: 16)
        XCTAssertEqual(options.crownRange.lowerBound, 0)
        XCTAssertEqual(options.crownRange.upperBound, 4, accuracy: 1e-9)
        XCTAssertEqual(options.zoomFactor(crownValue: 0), 1, accuracy: 1e-9)
        XCTAssertEqual(options.zoomFactor(crownValue: 1), 2, accuracy: 1e-9)
        XCTAssertEqual(options.zoomFactor(crownValue: 3), 8, accuracy: 1e-9)
        XCTAssertEqual(options.zoomFactor(crownValue: 10), 16, accuracy: 1e-9, "Clamped to maxZoomFactor")
        XCTAssertEqual(options.zoomFactor(crownValue: -2), 1, accuracy: 1e-9, "Never below the full view")
        XCTAssertEqual(options.zoomFactor(crownValue: .nan), 1)
    }

    func testCrownValueRoundTripsZoomFactor() {
        let options = WaveformZoomOptions(maxZoomFactor: 50)
        for factor in [1.0, 1.5, 2, 7.3, 50] {
            XCTAssertEqual(
                options.zoomFactor(crownValue: options.crownValue(zoomFactor: factor)), factor,
                accuracy: 1e-9
            )
        }
        XCTAssertEqual(options.crownValue(zoomFactor: 0.5), 0)
        XCTAssertEqual(options.crownValue(zoomFactor: 500), options.crownRange.upperBound)
        XCTAssertEqual(WaveformZoomOptions(maxZoomFactor: 1).crownRange.upperBound, 0)
    }

    func testZoomTargetRejectsNonFiniteMagnification() {
        let options = WaveformZoomOptions()
        XCTAssertEqual(options.zoomTarget(base: 3, magnification: .infinity), 3, accuracy: 1e-9)
        XCTAssertEqual(options.zoomTarget(base: 3, magnification: .nan), 3, accuracy: 1e-9)
    }

    func testPanSecondsIsInvertedRelativeToDrag() {
        // Dragging 100 pt right across a 200 pt view showing 10 s should move the window
        // 5 s *earlier*, so the audio under the finger travels with it.
        let seconds = WaveformZoomOptions.panSeconds(deltaPoints: 100, visibleSpan: 10, width: 200)
        XCTAssertEqual(seconds, -5, accuracy: 1e-9)

        let back = WaveformZoomOptions.panSeconds(deltaPoints: -100, visibleSpan: 10, width: 200)
        XCTAssertEqual(back, 5, accuracy: 1e-9)
    }

    func testPanSecondsScalesWithZoom() {
        // The same finger travel covers less time the further you are zoomed in.
        let wide   = WaveformZoomOptions.panSeconds(deltaPoints: 50, visibleSpan: 100, width: 200)
        let zoomed = WaveformZoomOptions.panSeconds(deltaPoints: 50, visibleSpan: 10,  width: 200)
        XCTAssertLessThan(abs(zoomed), abs(wide))
    }

    func testPanSecondsGuardsDegenerateGeometry() {
        XCTAssertEqual(WaveformZoomOptions.panSeconds(deltaPoints: 50, visibleSpan: 10, width: 0), 0)
        XCTAssertEqual(WaveformZoomOptions.panSeconds(deltaPoints: 50, visibleSpan: 0, width: 200), 0)
    }

    // MARK: - Double-tap recognition (Phase 3)

    func testDoubleTapWithinIntervalAndSlop() {
        let first = TapState(lastTapTime: Date(timeIntervalSinceReferenceDate: 100),
                             lastTapLocation: CGPoint(x: 50, y: 20))
        XCTAssertTrue(WaveformView.isDoubleTap(
            previous: first,
            location: CGPoint(x: 55, y: 24),
            time: Date(timeIntervalSinceReferenceDate: 100.15)
        ))
    }

    func testDoubleTapRejectedWhenTooSlow() {
        let first = TapState(lastTapTime: Date(timeIntervalSinceReferenceDate: 100),
                             lastTapLocation: CGPoint(x: 50, y: 20))
        XCTAssertFalse(WaveformView.isDoubleTap(
            previous: first,
            location: CGPoint(x: 50, y: 20),
            time: Date(timeIntervalSinceReferenceDate: 100.6)
        ))
    }

    func testDoubleTapRejectedWhenTooFarApart() {
        let first = TapState(lastTapTime: Date(timeIntervalSinceReferenceDate: 100),
                             lastTapLocation: CGPoint(x: 50, y: 20))
        XCTAssertFalse(WaveformView.isDoubleTap(
            previous: first,
            location: CGPoint(x: 200, y: 20),
            time: Date(timeIntervalSinceReferenceDate: 100.1)
        ))
    }

    func testFirstTapIsNeverADoubleTap() {
        // A fresh TapState sits at .distantPast, which must not read as a recent first tap.
        XCTAssertFalse(WaveformView.isDoubleTap(
            previous: TapState(),
            location: .zero,
            time: Date()
        ))
    }

    // MARK: - AudioSource (Phase 3)

    func testAudioSourceAccessors() {
        let url = URL(fileURLWithPath: "/tmp/clip.m4a")
        let fileSource = AudioSource.file(url)
        XCTAssertEqual(fileSource.url, url)
        XCTAssertNil(fileSource.summary)

        let summary = WaveformSummary.demo(duration: 12)
        let precomputed = AudioSource.precomputed(summary)
        XCTAssertNil(precomputed.url)
        XCTAssertEqual(precomputed.summary, summary)
    }

    @MainActor
    func testLoaderResolvesPrecomputedSourceImmediately() {
        let loader = WaveformLoader()
        let summary = WaveformSummary.demo(duration: 42)

        loader.load(source: .precomputed(summary))

        // No decode, no async hop — .loaded must be visible on the very next line.
        guard case .loaded(let loaded) = loader.state else {
            return XCTFail("Precomputed source should resolve synchronously, got \(loader.state)")
        }
        XCTAssertEqual(loaded, summary)
    }

    @MainActor
    func testLoaderFileSourceEntersLoadingState() {
        let loader = WaveformLoader()
        loader.load(source: .file(URL(fileURLWithPath: "/nonexistent/clip.m4a")))
        XCTAssertTrue(loader.state.isLoading, "A file source must go through the decode path")
        loader.cancel()
    }

    func testStaticLoaderReturnsPrecomputedSummary() async throws {
        let summary = WaveformSummary.demo(duration: 7)
        let result = try await WaveformLoader.load(source: .precomputed(summary))
        XCTAssertEqual(result, summary)
    }

    // MARK: - WaveformCache eviction (Phase 3)

    /// Points the cache at a scratch directory and restores the previous settings afterwards,
    /// so the suite never touches the real Caches folder.
    private func withTemporaryCache(
        budget: Int,
        _ body: (URL) throws -> Void
    ) rethrows {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WaveformKitTests-\(UUID().uuidString)", isDirectory: true)
        let previousDirectory = WaveformCache.directoryOverride
        let previousConfig = WaveformCache.configuration
        // Create it up front: an unbounded budget short-circuits eviction, so the cache's own
        // lazy directory creation would never run for those cases.
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        WaveformCache.directoryOverride = dir
        WaveformCache.configuration = WaveformCache.Configuration(maximumBytes: budget)
        defer {
            try? FileManager.default.removeItem(at: dir)
            WaveformCache.directoryOverride = previousDirectory
            WaveformCache.configuration = previousConfig
        }
        try body(dir)
    }

    /// Creates a real file so `fingerprint` has size and mtime attributes to key on.
    private func makeSourceFile(_ dir: URL, name: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data(repeating: 0, count: 64).write(to: url)
        return url
    }

    func testCacheRoundTrip() throws {
        try withTemporaryCache(budget: WaveformCache.Configuration.defaultMaximumBytes) { dir in
            let audio = try makeSourceFile(dir, name: "a.wav")
            let summary = WaveformSummary.demo(duration: 30, bars: 64)
            WaveformCache.save(summary, url: audio, targetBars: 64)

            let loaded = WaveformCache.load(url: audio, targetBars: 64)
            XCTAssertEqual(loaded, summary)
            XCTAssertNil(WaveformCache.load(url: audio, targetBars: 128),
                         "A different bar count is a different cache entry")
        }
    }

    func testCacheReportsCurrentByteSize() throws {
        try withTemporaryCache(budget: WaveformCache.Configuration.defaultMaximumBytes) { dir in
            XCTAssertEqual(WaveformCache.currentByteSize, 0)
            let audio = try makeSourceFile(dir, name: "a.wav")
            WaveformCache.save(.demo(duration: 30, bars: 200), url: audio, targetBars: 200)
            XCTAssertGreaterThan(WaveformCache.currentByteSize, 0)
        }
    }

    func testCacheEvictsDownToBudget() throws {
        // Budget fits roughly one entry; saving several must not grow without bound.
        try withTemporaryCache(budget: 4_000) { dir in
            for i in 0..<10 {
                let audio = try makeSourceFile(dir, name: "clip\(i).wav")
                WaveformCache.save(.demo(duration: 30, bars: 200), url: audio, targetBars: 200)
            }
            XCTAssertLessThanOrEqual(
                WaveformCache.currentByteSize, 4_000,
                "Cache must stay inside its byte budget"
            )
            XCTAssertGreaterThan(WaveformCache.currentByteSize, 0, "Eviction must not empty the cache")
        }
    }

    func testCacheEvictsLeastRecentlyUsedEntry() throws {
        try withTemporaryCache(budget: .max) { dir in
            let first  = try makeSourceFile(dir, name: "first.wav")
            let second = try makeSourceFile(dir, name: "second.wav")
            let summary = WaveformSummary.demo(duration: 30, bars: 200)

            WaveformCache.save(summary, url: first,  targetBars: 200)
            WaveformCache.save(summary, url: second, targetBars: 200)

            // Read `first` back so it becomes the most recently used entry.  mtime has
            // one-second resolution on some filesystems, so make the gap unambiguous.
            Thread.sleep(forTimeInterval: 1.1)
            XCTAssertNotNil(WaveformCache.load(url: first, targetBars: 200))

            // Shrink the budget to hold about one entry and force eviction.
            let oneEntry = WaveformCache.currentByteSize / 2 + 1
            WaveformCache.configuration = WaveformCache.Configuration(maximumBytes: oneEntry)

            XCTAssertNotNil(WaveformCache.load(url: first, targetBars: 200),
                            "Recently read entry should survive eviction")
            XCTAssertNil(WaveformCache.load(url: second, targetBars: 200),
                         "Least recently used entry should have been evicted")
        }
    }

    func testCacheUnboundedConfigurationNeverEvicts() throws {
        try withTemporaryCache(budget: .max) { dir in
            XCTAssertEqual(WaveformCache.configuration, .unbounded)
            for i in 0..<5 {
                let audio = try makeSourceFile(dir, name: "clip\(i).wav")
                WaveformCache.save(.demo(duration: 30, bars: 200), url: audio, targetBars: 200)
            }
            XCTAssertEqual(WaveformCache.evictIfNeeded(), 0)
            for i in 0..<5 {
                let audio = dir.appendingPathComponent("clip\(i).wav")
                XCTAssertNotNil(WaveformCache.load(url: audio, targetBars: 200))
            }
        }
    }

    func testCacheClearRemovesEverything() throws {
        try withTemporaryCache(budget: .max) { dir in
            let audio = try makeSourceFile(dir, name: "a.wav")
            WaveformCache.save(.demo(duration: 30, bars: 64), url: audio, targetBars: 64)
            XCTAssertNotNil(WaveformCache.load(url: audio, targetBars: 64))
            WaveformCache.clear()
            XCTAssertNil(WaveformCache.load(url: audio, targetBars: 64))
        }
    }

    func testCacheConfigurationClampsNegativeBudget() {
        XCTAssertEqual(WaveformCache.Configuration(maximumBytes: -1).maximumBytes, 0)
        XCTAssertEqual(WaveformCache.Configuration.unbounded.maximumBytes, .max)
    }

    // MARK: - AudioDecoder end-to-end (Phase 3)
    //
    // These decode real audio rather than a fixture array.  The file is synthesized with
    // AVAudioFile at test time so the repo carries no binary assets and the suite stays
    // hermetic.  Everything before this point tests the pieces around the decoder; this tests
    // the decoder itself, which is the path every real caller takes.

    /// Writes a mono 44.1 kHz WAV whose amplitude follows `envelope(t)` for `t` in 0...1.
    /// Returns the file URL; the caller is responsible for deleting it.
    private func makeToneFile(
        duration: TimeInterval,
        frequency: Double = 440,
        sampleRate: Double = 44100,
        envelope: (Double) -> Double = { _ in 1.0 }
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WaveformKitTone-\(UUID().uuidString).wav")
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)

        let totalFrames = Int(duration * sampleRate)
        let chunkFrames = 4096
        var written = 0
        while written < totalFrames {
            let count = min(chunkFrames, totalFrames - written)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
            buffer.frameLength = AVAudioFrameCount(count)
            let channel = buffer.floatChannelData![0]
            for i in 0..<count {
                let frame = written + i
                let t = Double(frame) / sampleRate
                let position = Double(frame) / Double(totalFrames)
                channel[i] = Float(sin(2 * .pi * frequency * t) * envelope(position))
            }
            try file.write(from: buffer)
            written += count
        }
        return url
    }

    private func removeFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    func testDecoderProducesRequestedBarCount() async throws {
        let url = try makeToneFile(duration: 2.0)
        defer { removeFile(url) }

        let summary = try await AudioDecoder.summarize(url: url, targetBars: 100)

        // The decoder emits a trailing partial bar for the remainder, so allow one extra.
        XCTAssertGreaterThanOrEqual(summary.amplitudes.count, 100)
        XCTAssertLessThanOrEqual(summary.amplitudes.count, 101)
    }

    func testDecoderReportsDurationAndFormat() async throws {
        let url = try makeToneFile(duration: 1.5, sampleRate: 44100)
        defer { removeFile(url) }

        let summary = try await AudioDecoder.summarize(url: url, targetBars: 50)

        XCTAssertEqual(summary.duration, 1.5, accuracy: 0.05)
        XCTAssertEqual(summary.sampleRate, 44100, accuracy: 1)
        XCTAssertEqual(summary.channelCount, 1)
    }

    func testDecoderNormalisesToUnitPeak() async throws {
        // A constant-amplitude tone at half scale must still normalise to a peak of 1.
        let url = try makeToneFile(duration: 1.0, envelope: { _ in 0.5 })
        defer { removeFile(url) }

        let summary = try await AudioDecoder.summarize(url: url, targetBars: 40)

        XCTAssertEqual(summary.amplitudes.max() ?? 0, 1.0, accuracy: 1e-4,
                       "Amplitudes are normalised so the loudest bar is 1.0")
        XCTAssertTrue(summary.amplitudes.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    func testDecoderTracksAmplitudeEnvelope() async throws {
        // Ramp from silence to full scale: the decoded bars must rise monotonically overall,
        // which is the property that makes a waveform look like the audio it came from.
        let url = try makeToneFile(duration: 2.0, envelope: { $0 })
        defer { removeFile(url) }

        let summary = try await AudioDecoder.summarize(url: url, targetBars: 20)
        let amps = summary.amplitudes
        XCTAssertGreaterThan(amps.count, 10)

        let firstQuarter = amps.prefix(amps.count / 4).reduce(0, +) / Float(amps.count / 4)
        let lastQuarter  = amps.suffix(amps.count / 4).reduce(0, +) / Float(amps.count / 4)
        XCTAssertLessThan(firstQuarter, 0.3, "Start of a fade-in should be quiet")
        XCTAssertGreaterThan(lastQuarter, 0.7, "End of a fade-in should be loud")
    }

    func testDecoderReportsProgressMonotonicallyAndFinishesAtOne() async throws {
        let url = try makeToneFile(duration: 1.0)
        defer { removeFile(url) }

        let collector = ProgressCollector()
        _ = try await AudioDecoder.summarize(url: url, targetBars: 50) { p in
            collector.record(p)
        }
        let values = collector.values

        XCTAssertFalse(values.isEmpty, "Progress must be reported at least once")
        XCTAssertEqual(values.last, 1.0, "The final callback signals completion")
        XCTAssertTrue(values.allSatisfy { $0 >= 0 && $0 <= 1 })
        for (a, b) in zip(values, values.dropFirst()) {
            XCTAssertLessThanOrEqual(a, b, "Progress must never go backwards")
        }
    }

    func testDecoderThrowsOnMissingFile() async {
        let url = URL(fileURLWithPath: "/nonexistent/definitely-not-audio.wav")
        do {
            _ = try await AudioDecoder.summarize(url: url, targetBars: 20)
            XCTFail("Decoding a missing file should throw")
        } catch {
            // Any error is acceptable; AVFoundation's is not one of ours.
        }
    }

    func testDecoderThrowsOnNonAudioFile() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WaveformKitNotAudio-\(UUID().uuidString).wav")
        try Data("this is not audio".utf8).write(to: url)
        defer { removeFile(url) }

        do {
            _ = try await AudioDecoder.summarize(url: url, targetBars: 20)
            XCTFail("Decoding a non-audio file should throw")
        } catch {
            // Expected.
        }
    }

    func testDecoderRespectsCancellation() async throws {
        let url = try makeToneFile(duration: 20.0)
        defer { removeFile(url) }

        let task = Task {
            try await AudioDecoder.summarize(url: url, targetBars: 4000)
        }
        task.cancel()

        do {
            _ = try await task.value
            // A very fast machine may finish before cancellation is observed; that is not a
            // failure, only an unexercised path.
        } catch is CancellationError {
            // The path we care about.
        } catch {
            XCTFail("Cancellation should surface as CancellationError, got \(error)")
        }
    }

    // MARK: - Decoder + cache + loader, together

    /// Async sibling of `withTemporaryCache` — the decode has to be awaited inside the scope,
    /// which a synchronous closure cannot do without smuggling results across isolation.
    private func withTemporaryCacheAsync(
        budget: Int,
        _ body: () async throws -> Void
    ) async rethrows {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WaveformKitTests-\(UUID().uuidString)", isDirectory: true)
        let previousDirectory = WaveformCache.directoryOverride
        let previousConfig = WaveformCache.configuration
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        WaveformCache.directoryOverride = dir
        WaveformCache.configuration = WaveformCache.Configuration(maximumBytes: budget)
        defer {
            try? FileManager.default.removeItem(at: dir)
            WaveformCache.directoryOverride = previousDirectory
            WaveformCache.configuration = previousConfig
        }
        try await body()
    }

    func testLoaderDecodesRealFileAndCachesIt() async throws {
        let audio = try makeToneFile(duration: 1.0, envelope: { $0 })
        defer { removeFile(audio) }

        try await withTemporaryCacheAsync(budget: .max) {
            let summary = try await WaveformLoader.load(url: audio, targetBars: 60)
            XCTAssertGreaterThan(summary.amplitudes.count, 50)

            // The second read must come back from disk with identical data.
            let cached = try XCTUnwrap(WaveformCache.load(url: audio, targetBars: 60))
            XCTAssertEqual(cached, summary, "A cache round-trip must preserve the summary")
        }
    }

    func testLoaderSkipsDecodeOnCacheHit() async throws {
        let audio = try makeToneFile(duration: 1.0)
        defer { removeFile(audio) }

        try await withTemporaryCacheAsync(budget: .max) {
            let first = try await WaveformLoader.load(url: audio, targetBars: 40)

            // With useCache: false the decoder runs again and produces an equal — but freshly
            // decoded — summary. Equality ignores `id`, so compare identity tokens instead.
            let uncached = try await WaveformLoader.load(url: audio, targetBars: 40, useCache: false)
            XCTAssertNotEqual(first.id, uncached.id, "useCache: false must bypass the cache")
            XCTAssertEqual(first, uncached, "Decoding the same file twice must agree")
        }
    }
}

/// Collects progress callbacks fired from the decoder's background executor.
private final class ProgressCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Double] = []

    func record(_ value: Double) {
        lock.withLock { storage.append(value) }
    }

    var values: [Double] {
        lock.withLock { storage }
    }
}

// MARK: - WaveformSummaryPyramid (Phase 4)

extension WaveformKitTests {

    /// Deterministic pseudo-random bins in 0...1, so failures reproduce.
    private func pyramidFixture(count: Int, seed: UInt64 = 7) -> [Float] {
        var state = seed
        return (0..<count).map { _ in
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float(state >> 40) / Float(1 << 24)
        }
    }

    func testPyramidLevelsHalveDownToOneBin() {
        let pyramid = WaveformSummaryPyramid(amplitudes: pyramidFixture(count: 10))
        XCTAssertEqual(pyramid.resolution, 10)
        XCTAssertEqual((0..<pyramid.levelCount).map { pyramid.level($0).count }, [10, 5, 3, 2, 1],
                       "Each level halves the previous one, carrying an odd tail bin up unpaired")
    }

    func testEmptyPyramid() {
        let pyramid = WaveformSummaryPyramid(amplitudes: [])
        XCTAssertTrue(pyramid.isEmpty)
        XCTAssertEqual(pyramid.levelCount, 0)
        XCTAssertEqual(pyramid.amplitudes(count: 10), [])
        XCTAssertNil(pyramid.slice(for: 0...1, count: 10))
    }

    func testPyramidPeakLevelsAreExactMaxima() {
        let base = pyramidFixture(count: 1000)
        let pyramid = WaveformSummaryPyramid(amplitudes: base)
        let quantised = pyramid.baseAmplitudes
        let level3 = pyramid.level(3, mode: .peak)
        for j in level3.indices {
            let block = quantised[(j * 8)..<min(quantised.count, (j + 1) * 8)]
            XCTAssertEqual(level3[j], block.max(), "Level 3 bin \(j) must be the loudest of its 8 base bins")
        }
    }

    func testPyramidMeanLevelsAverage() {
        let pyramid = WaveformSummaryPyramid(amplitudes: [0.2, 0.4, 0.6, 0.8])
        let level1 = pyramid.level(1, mode: .mean)
        XCTAssertEqual(level1.count, 2)
        XCTAssertEqual(level1[0], 0.3, accuracy: 1e-4)
        XCTAssertEqual(level1[1], 0.7, accuracy: 1e-4)
        XCTAssertEqual(pyramid.level(1, mode: .peak)[1], 0.8, accuracy: 1e-4)
        XCTAssertEqual(pyramid.level(99), [], "An out-of-range level is empty, not a crash")
    }

    func testPyramidClampsAndQuantises() {
        let pyramid = WaveformSummaryPyramid(amplitudes: [-1, 2, .nan, .infinity, 0.5])
        let base = pyramid.baseAmplitudes
        XCTAssertEqual(base[0], 0)
        XCTAssertEqual(base[1], 1)
        XCTAssertEqual(base[2], 0, "NaN reads as silence")
        XCTAssertEqual(base[3], 0, "Infinity reads as silence")
        XCTAssertEqual(base[4], 0.5, accuracy: 1.0 / 65_535)
    }

    func testPyramidCodableRoundTripIsExact() throws {
        let original = WaveformSummaryPyramid(amplitudes: pyramidFixture(count: 777))
        let decoded = try JSONDecoder().decode(
            WaveformSummaryPyramid.self, from: JSONEncoder().encode(original)
        )
        XCTAssertEqual(decoded, original, "Quantising at init makes the 16-bit encoding lossless")
        XCTAssertEqual(decoded.levelCount, original.levelCount, "Coarser levels are rebuilt on decode")
    }

    func testPyramidEncodingIsCompact() throws {
        let pyramid = WaveformSummaryPyramid(
            amplitudes: pyramidFixture(count: WaveformSummaryPyramid.defaultResolution)
        )
        let bytes = try JSONEncoder().encode(pyramid).count
        // 16 384 × 2 bytes, base64-encoded ≈ 43.7 KB.  JSON numbers would be ~5× that.
        XCTAssertLessThan(bytes, 45_000)
    }

    func testPyramidRejectsOddByteCount() {
        let json = Data(#"{"base":"AAAA"}"#.utf8)   // base64 for three bytes
        XCTAssertThrowsError(try JSONDecoder().decode(WaveformSummaryPyramid.self, from: json))
    }

    func testPyramidSliceAtFullRangePicksCoarsestSufficientLevel() throws {
        let pyramid = WaveformSummaryPyramid(
            amplitudes: pyramidFixture(count: WaveformSummaryPyramid.defaultResolution)
        )
        let slice = try XCTUnwrap(pyramid.slice(for: 0...1, count: 200))
        // 16 384 >> 6 = 256 ≥ 200, and >> 7 = 128 < 200.
        XCTAssertEqual(slice, .init(level: 6, start: 0, end: 256))
    }

    func testPyramidSliceWhenZoomedUsesFinerLevel() throws {
        let pyramid = WaveformSummaryPyramid(
            amplitudes: pyramidFixture(count: WaveformSummaryPyramid.defaultResolution)
        )
        // 50× zoom: 2 % of 16 384 is 328 bins, which only the base level can cover at 200 bars.
        let slice = try XCTUnwrap(pyramid.slice(for: 0...0.02, count: 200))
        XCTAssertEqual(slice.level, 0)
        XCTAssertEqual(slice.end - slice.start, 328)

        // Past the base resolution the base is still used; the resampler repeats bins.
        let deep = try XCTUnwrap(pyramid.slice(for: 0.5...0.501, count: 200))
        XCTAssertEqual(deep.level, 0)
        XCTAssertEqual(pyramid.amplitudes(in: 0.5...0.501, count: 200).count, 200)
    }

    func testPyramidAmplitudesMatchResamplingTheBase() {
        // With a power-of-two base, each ladder is the exact reduction, so picking a level must
        // give the same bars as resampling the whole base directly.
        let pyramid = WaveformSummaryPyramid(amplitudes: pyramidFixture(count: 1024))
        let base = pyramid.baseAmplitudes
        for mode in WaveformResampleMode.allCases {
            let viaPyramid = pyramid.amplitudes(count: 64, mode: mode)
            let direct = resampleAmplitudes(src: base, startIdx: 0, endIdx: 1024, targetCount: 64, mode: mode)
            XCTAssertEqual(viaPyramid.count, 64)
            for (a, b) in zip(viaPyramid, direct) {
                XCTAssertEqual(a, b, accuracy: 1e-5, "\(mode) via pyramid must match the direct reduction")
            }
        }
    }

    func testPyramidRevealsDetailTheFlatArrayCannot() {
        // One transient in 16 384 bins.  The flat 200-bin summary smears it across the whole of
        // a 1 % zoom window; the pyramid keeps it about one bar wide.
        var fine = [Float](repeating: 0.1, count: WaveformSummaryPyramid.defaultResolution)
        fine[8_100] = 1.0
        let pyramid = WaveformSummaryPyramid(amplitudes: fine)
        let flat = resampleAmplitudes(src: fine, startIdx: 0, endIdx: fine.count, targetCount: 200, mode: .peak)

        var viewport = WaveformViewport(duration: 100)
        viewport.visibleRange = 49...50          // 1 % of the file, containing the transient
        let bars = 100
        let range = viewport.visibleIndices(totalBars: flat.count)
        let stretched = resampleAmplitudes(
            src: flat, startIdx: range.lowerBound, endIdx: range.upperBound, targetCount: bars
        )
        let detailed = pyramid.amplitudes(in: viewport.normalizedRange, count: bars)

        XCTAssertGreaterThanOrEqual(stretched.filter { $0 > 0.5 }.count, 20,
                                    "The flat array stretches the transient into a wide block")
        XCTAssertLessThanOrEqual(detailed.filter { $0 > 0.5 }.count, 2,
                                 "The pyramid keeps the transient narrow")
        XCTAssertEqual(detailed.max() ?? 0, 1.0, accuracy: 1e-4)
    }

    func testResampleCacheKeyIncludesLevel() {
        let cache = ResampleCache()
        let id = UUID()
        cache.set([0.5], summaryID: id, count: 1, level: 3, startIdx: 0, endIdx: 4, mode: .peak)
        XCTAssertNil(cache.get(summaryID: id, count: 1, level: 4, startIdx: 0, endIdx: 4, mode: .peak))
        XCTAssertNil(cache.get(summaryID: id, count: 1, startIdx: 0, endIdx: 4, mode: .peak),
                     "A pyramid slice must not collide with the same slice of the flat array")
        XCTAssertEqual(cache.get(summaryID: id, count: 1, level: 3, startIdx: 0, endIdx: 4, mode: .peak), [0.5])
    }

    // MARK: Summary integration

    func testSummaryDecodesWithoutPyramidKey() throws {
        // JSON written before 0.7.0, or by a server sending flat amplitudes only.
        let json = Data(#"{"amplitudes":[0.1,0.9],"duration":2,"sampleRate":44100,"channelCount":1}"#.utf8)
        let summary = try JSONDecoder().decode(WaveformSummary.self, from: json)
        XCTAssertNil(summary.pyramid)
        XCTAssertEqual(summary.amplitudes, [0.1, 0.9])
    }

    func testSummaryRoundTripsPyramid() throws {
        let original = WaveformSummary(
            amplitudes: [0.2, 0.8], duration: 2, sampleRate: 44_100, channelCount: 1,
            pyramid: WaveformSummaryPyramid(amplitudes: pyramidFixture(count: 300))
        )
        let decoded = try JSONDecoder().decode(WaveformSummary.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.pyramid?.resolution, 300)
    }

    func testSummaryEqualityIncludesPyramid() {
        let plain = WaveformSummary(amplitudes: [0.5], duration: 1, sampleRate: 44_100, channelCount: 1)
        let detailed = WaveformSummary(
            amplitudes: [0.5], duration: 1, sampleRate: 44_100, channelCount: 1,
            pyramid: WaveformSummaryPyramid(amplitudes: [0.5, 0.4])
        )
        XCTAssertNotEqual(plain, detailed)
    }

    // MARK: Decoder and cache

    func testDecoderBuildsPyramid() async throws {
        let url = try makeToneFile(duration: 2.0)
        defer { removeFile(url) }

        let summary = try await AudioDecoder.summarize(url: url, targetBars: 100)
        let pyramid = try XCTUnwrap(summary.pyramid, "Decoding builds a pyramid by default")

        // 88 200 frames at the 64-frame floor (the default resolution would give 5 frames a bin).
        let expected = 88_200 / AudioDecoder.minimumFramesPerPyramidBin
        XCTAssertEqual(Double(pyramid.resolution), Double(expected), accuracy: 2)
        XCTAssertEqual(pyramid.baseAmplitudes.max() ?? 0, 1.0, accuracy: 1e-3,
                       "Pyramid bins are normalised to a unit peak, like the bars")
    }

    func testDecoderPyramidTracksEnvelope() async throws {
        let url = try makeToneFile(duration: 2.0, envelope: { $0 })
        defer { removeFile(url) }

        let summary = try await AudioDecoder.summarize(url: url, targetBars: 20)
        let base = try XCTUnwrap(summary.pyramid).baseAmplitudes
        let quarter = base.count / 4
        let early = base[..<quarter].reduce(0, +) / Float(quarter)
        let late = base[(base.count - quarter)...].reduce(0, +) / Float(quarter)
        XCTAssertLessThan(early, late * 0.5, "A rising ramp must read quieter early than late")
    }

    func testDecoderSkipsPyramidWhenDisabled() async throws {
        let url = try makeToneFile(duration: 1.0)
        defer { removeFile(url) }

        let summary = try await AudioDecoder.summarize(url: url, targetBars: 40, pyramidResolution: 0)
        XCTAssertNil(summary.pyramid)
    }

    func testDecoderSkipsPyramidWhenNoFinerThanBars() async throws {
        // 4 410 frames over 100 bars is 44 frames a bar — already under the 64-frame floor.
        let url = try makeToneFile(duration: 0.1)
        defer { removeFile(url) }

        let summary = try await AudioDecoder.summarize(url: url, targetBars: 100)
        XCTAssertNil(summary.pyramid)
    }

    // MARK: AVAudioFile decoder (watchOS)
    //
    // watchOS has no AVAssetReader, so it decodes with AVAudioFile.  That path is compiled
    // everywhere so it can be checked here against the reader every other platform uses.

    func testAudioFileDecoderMatchesAssetReader() async throws {
        let url = try makeToneFile(duration: 2.0, envelope: { $0 })
        defer { removeFile(url) }

        let reader = try await AudioDecoder.summarize(url: url, targetBars: 100)
        let file = try AudioDecoder.summarizeWithAudioFile(
            url: url, targetBars: 100,
            pyramidResolution: WaveformSummaryPyramid.defaultResolution, onProgress: nil
        )

        XCTAssertEqual(file.duration, reader.duration, accuracy: 1e-6)
        XCTAssertEqual(file.sampleRate, reader.sampleRate)
        XCTAssertEqual(file.channelCount, reader.channelCount)
        XCTAssertEqual(file.amplitudes.count, reader.amplitudes.count)
        for (a, b) in zip(file.amplitudes, reader.amplitudes) {
            XCTAssertEqual(a, b, accuracy: 1e-4)
        }
        let filePyramid = try XCTUnwrap(file.pyramid)
        let readerPyramid = try XCTUnwrap(reader.pyramid)
        XCTAssertEqual(filePyramid.resolution, readerPyramid.resolution)
        for (a, b) in zip(filePyramid.baseAmplitudes, readerPyramid.baseAmplitudes) {
            XCTAssertEqual(a, b, accuracy: 1e-3)
        }
    }

    func testAudioFileDecoderReadsStereoAcrossChunks() throws {
        // Two channels and several read chunks: the interleaved layout and the chunk boundaries
        // must not change the bins.  Left is silent, right a full-scale tone, so every bar sees
        // the same mix and normalises to 1.
        let sampleRate = 44_100.0
        let frames = Int(AudioDecoder.audioFileChunkFrames) * 3 + 1_000
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WaveformKitStereo-\(UUID().uuidString).wav")
        defer { removeFile(url) }
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false
        )!
        do {
            let out = try AVAudioFile(forWriting: url, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
            buffer.frameLength = AVAudioFrameCount(frames)
            for i in 0..<frames {
                buffer.floatChannelData![0][i] = 0
                buffer.floatChannelData![1][i] = Float(sin(2 * .pi * 441 * Double(i) / sampleRate))
            }
            try out.write(from: buffer)
        }

        let summary = try AudioDecoder.summarizeWithAudioFile(
            url: url, targetBars: 10, pyramidResolution: 0, onProgress: nil
        )
        XCTAssertEqual(summary.channelCount, 2)
        XCTAssertEqual(summary.duration, Double(frames) / sampleRate, accuracy: 1e-6)
        XCTAssertGreaterThanOrEqual(summary.amplitudes.count, 10)
        for amplitude in summary.amplitudes.prefix(10) {
            XCTAssertEqual(amplitude, 1, accuracy: 0.01)
        }
    }

    func testAudioFileDecoderThrowsOnNonAudioFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WaveformKitNotAudio-\(UUID().uuidString).wav")
        try Data("this is not audio".utf8).write(to: url)
        defer { removeFile(url) }

        XCTAssertThrowsError(try AudioDecoder.summarizeWithAudioFile(
            url: url, targetBars: 20, pyramidResolution: 0, onProgress: nil
        )) { error in
            XCTAssertEqual(error as? AudioDecoderError, .readerInitFailed)
        }
    }

    func testAudioFileDecoderReportsProgressToOne() throws {
        let url = try makeToneFile(duration: 1.0)
        defer { removeFile(url) }

        let collector = ProgressCollector()
        _ = try AudioDecoder.summarizeWithAudioFile(
            url: url, targetBars: 50, pyramidResolution: 0, onProgress: { collector.record($0) }
        )
        XCTAssertEqual(collector.values.last, 1.0)
        for (a, b) in zip(collector.values, collector.values.dropFirst()) {
            XCTAssertLessThanOrEqual(a, b)
        }
    }

    func testCacheKeyIncludesPyramidResolution() throws {
        try withTemporaryCache(budget: WaveformCache.Configuration.defaultMaximumBytes) { dir in
            let audio = try makeSourceFile(dir, name: "p.wav")
            let summary = WaveformSummary.demo(duration: 30, bars: 64)
            WaveformCache.save(summary, url: audio, targetBars: 64, pyramidResolution: 0)

            XCTAssertNil(WaveformCache.load(url: audio, targetBars: 64),
                         "A flat-only entry must not satisfy a request for a pyramid")
            XCTAssertEqual(WaveformCache.load(url: audio, targetBars: 64, pyramidResolution: 0), summary)
        }
    }
}

// MARK: - Metal rendering backend (Phase 4)

extension WaveformKitTests {

    func testRenderingBackendSelection() {
        XCTAssertFalse(WaveformRenderingBackend.canvas.prefersMetal(barCount: 10_000))
        XCTAssertTrue(WaveformRenderingBackend.metal.prefersMetal(barCount: 1))
        XCTAssertFalse(WaveformRenderingBackend.automatic().prefersMetal(barCount: 511))
        XCTAssertTrue(WaveformRenderingBackend.automatic().prefersMetal(barCount: 512))
        XCTAssertTrue(WaveformRenderingBackend.automatic(minimumBarCount: 100).prefersMetal(barCount: 100))
    }

    func testRenderingBackendDefaultsToCanvas() {
        XCTAssertEqual(EnvironmentValues().waveformRenderingBackend, .canvas,
                       "Metal is opt-in; existing apps must keep drawing exactly as before")
    }

    func testBarLayoutMatchesCanvasArithmetic() {
        let layout = BarLayout(count: 100, width: 400, spacing: 2)
        // (400 - 2 × 99) / 100
        XCTAssertEqual(layout.barWidth, 2.02, accuracy: 1e-9)
        XCTAssertEqual(layout.step, 4.02, accuracy: 1e-9)
        XCTAssertEqual(layout.x(at: 10), 40.2, accuracy: 1e-9)
    }

    func testBarLayoutNeverGoesBelowOnePoint() {
        let layout = BarLayout(count: 5_000, width: 400, spacing: 2)
        XCTAssertEqual(layout.barWidth, 1, "Too many bars overflow and clip rather than vanish")
        XCTAssertEqual(BarLayout(count: 0, width: 400, spacing: 2).barWidth, 400,
                       "A zero count must not divide by zero")
    }

    func testBarHeightClamps() {
        XCTAssertEqual(BarLayout.barHeight(amplitude: 0, height: 100), BarLayout.minimumBarHeight)
        XCTAssertEqual(BarLayout.barHeight(amplitude: 0.5, height: 100), 50)
        XCTAssertEqual(BarLayout.barHeight(amplitude: 3, height: 100), 100,
                       "A reactive boost never pushes a bar past the view")
    }

    func testMetalStructsMatchShaderLayout() {
        // The shader reads these as float4 fields; any padding would misalign every value.
        XCTAssertEqual(MemoryLayout<MetalBarUniforms>.stride, 64)
        XCTAssertEqual(MemoryLayout<MetalGradientStop>.stride, 32)
    }

    func testMetalUniformsPacking() {
        let u = MetalBarUniforms(
            size: CGSize(width: 400, height: 80), barCount: 100, spacing: 2, cornerRadius: 1.5,
            amplitudeScale: 1.25, progress: 0.25, showsProgress: true, mirrored: true,
            pointsPerPixel: 1.0 / 3, playedStopCount: 1, unplayedStopCount: 3
        )
        XCTAssertEqual(u.layout.x, 400)
        XCTAssertEqual(u.layout.y, 80)
        XCTAssertEqual(u.layout.z, 2.02, accuracy: 1e-5)
        XCTAssertEqual(u.layout.w, 4.02, accuracy: 1e-5)
        XCTAssertEqual(u.shape, SIMD4(1.5, Float(BarLayout.minimumBarHeight), 1.25, 100))
        XCTAssertEqual(u.flags.x, 100)
        XCTAssertEqual(u.flags.y, 1)
        XCTAssertEqual(u.flags.z, 1)
        XCTAssertEqual(u.flags.w, 1.0 / 3, accuracy: 1e-6)
        XCTAssertEqual(u.stopCounts, SIMD4(1, 3, 0, 0))
    }

    func testMetalUniformsGuardAgainstBadInput() {
        let u = MetalBarUniforms(
            size: CGSize(width: 200, height: 40), barCount: 10, spacing: 0, cornerRadius: -4,
            amplitudeScale: 1, progress: 7, showsProgress: false, mirrored: false,
            pointsPerPixel: 0, playedStopCount: 1, unplayedStopCount: 1
        )
        XCTAssertEqual(u.shape.x, 0, "Negative corner radius is clamped")
        XCTAssertEqual(u.shape.w, 200, "Progress past 1 pins the playhead to the trailing edge")
        XCTAssertGreaterThan(u.flags.w, 0, "The shader divides by points-per-pixel")
    }

    func testMetalStopsForSolidColour() {
        let stops = MetalGradientStop.stops(
            color: Color(.sRGB, red: 1, green: 0.5, blue: 0, opacity: 0.8),
            gradient: nil, in: EnvironmentValues()
        )
        XCTAssertEqual(stops.count, 1)
        XCTAssertEqual(stops[0].color.x, 1, accuracy: 1e-3)
        XCTAssertEqual(stops[0].color.y, 0.5, accuracy: 1e-2)
        XCTAssertEqual(stops[0].color.z, 0, accuracy: 1e-3)
        XCTAssertEqual(stops[0].color.w, 0.8, accuracy: 1e-3)
    }

    func testMetalStopsForGradientAreSortedAndCapped() {
        let unsorted = Gradient(stops: [
            .init(color: .white, location: 1),
            .init(color: .black, location: 0),
            .init(color: .gray, location: 0.5),
        ])
        let stops = MetalGradientStop.stops(color: .red, gradient: unsorted, in: EnvironmentValues())
        XCTAssertEqual(stops.map(\.location.x), [0, 0.5, 1])

        let long = Gradient(colors: Array(repeating: Color.blue, count: 40))
        XCTAssertEqual(
            MetalGradientStop.stops(color: .red, gradient: long, in: EnvironmentValues()).count,
            MetalBarsShader.maximumStopsPerShading
        )
    }

    func testMetalStopsClampWideGamutComponents() {
        let stops = MetalGradientStop.stops(
            color: Color(.sRGB, red: 1.6, green: -0.2, blue: 0.5, opacity: 1),
            gradient: nil, in: EnvironmentValues()
        )
        XCTAssertEqual(stops[0].color.x, 1)
        XCTAssertEqual(stops[0].color.y, 0)
    }

    func testMetalStopTableLayout() {
        let a = MetalGradientStop(color: SIMD4(1, 0, 0, 1), location: 0)
        let b = MetalGradientStop(color: SIMD4(0, 0, 1, 1), location: 0)
        let table = MetalGradientStop.table(played: [a], unplayed: [b])
        let n = MetalBarsShader.maximumStopsPerShading
        XCTAssertEqual(table.count, n * 2)
        XCTAssertEqual(table[0], a)
        XCTAssertEqual(table[n], b, "Unplayed stops start at the offset the shader reads them from")
        XCTAssertEqual(table[1], .clear)
    }

    func testShaderSourceUsesTheSwiftSideConstants() {
        let source = MetalBarsShader.source
        XCTAssertTrue(source.contains("vertex BarVertex \(MetalBarsShader.vertexFunctionName)("))
        XCTAssertTrue(source.contains("fragment float4 \(MetalBarsShader.fragmentFunctionName)("))
        XCTAssertTrue(source.contains("played ? 0 : \(MetalBarsShader.maximumStopsPerShading);"))
    }

    #if canImport(MetalKit)
    func testMetalShaderCompilesOnThisDevice() throws {
        // The shader is a string compiled at runtime, so a Swift build cannot catch a typo in
        // it.  This does.  Skipped on machines with no Metal device.
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "No Metal device")
        XCTAssertNotNil(MetalBarsResources.make(), "Shader compilation or pipeline creation failed")
    }
    #endif
}

// MARK: - Region selection (Phase 5)

extension WaveformKitTests {

    // MARK: Options

    func testSelectionOptionsDefaults() {
        let o = WaveformSelectionOptions()
        XCTAssertEqual(o.activation, .longPress(holdDuration: 0.4))
        XCTAssertEqual(o.minimumLength, 0.1)
        XCTAssertNil(o.snapInterval)
        XCTAssertTrue(o.clearsOnTapOutside)
        XCTAssertTrue(o.updatesWhileDragging)
        XCTAssertEqual(WaveformSelectionOptions.editor.activation, .drag)
    }

    func testSelectionOptionsSanitiseInput() {
        let o = WaveformSelectionOptions(minimumLength: -3, snapInterval: 0)
        XCTAssertEqual(o.minimumLength, 0)
        XCTAssertNil(o.snapInterval, "A zero snap interval would divide by zero")
        XCTAssertNil(WaveformSelectionOptions(snapInterval: -1).snapInterval)
        XCTAssertNil(WaveformSelectionOptions(snapInterval: .infinity).snapInterval)
    }

    func testSelectionRangeOrdersAndClamps() {
        let o = WaveformSelectionOptions()
        XCTAssertEqual(o.range(from: 30, to: 10, duration: 60), 10...30, "Either drag direction works")
        XCTAssertEqual(o.range(from: -5, to: 90, duration: 60), 0...60, "Clamped to the file")
        XCTAssertNil(o.range(from: 1, to: 2, duration: 0), "Nothing to select in an empty file")
    }

    func testSelectionRangeEnforcesMinimumLength() {
        let o = WaveformSelectionOptions(minimumLength: 0.5)
        XCTAssertNil(o.range(from: 10, to: 10.2, duration: 60))
        XCTAssertEqual(o.range(from: 10, to: 10.2, duration: 60, enforcingMinimum: false), 10...10.2,
                       "The in-progress range under the finger may be tiny")
        XCTAssertNil(WaveformSelectionOptions(minimumLength: 0).range(from: 5, to: 5, duration: 60),
                     "A zero-length selection is never kept, even with no minimum")
    }

    func testSelectionSnapping() {
        let o = WaveformSelectionOptions(snapInterval: 0.5)
        XCTAssertEqual(o.snapped(10.26, duration: 60), 10.5)
        XCTAssertEqual(o.snapped(10.24, duration: 60), 10.0)
        XCTAssertEqual(o.snapped(59.9, duration: 59.8), 59.8, "Snapping never passes the end")
        XCTAssertEqual(o.snapped(.nan, duration: 60), 0)
        XCTAssertEqual(o.range(from: 1.1, to: 3.9, duration: 60), 1.0...4.0)
    }

    func testSelectionActivation() {
        let down = Date(timeIntervalSinceReferenceDate: 100)
        let longPress = WaveformSelectionOptions(activation: .longPress(holdDuration: 0.4))
        XCTAssertFalse(longPress.activatesSelection(touchDown: down, firstMove: down.addingTimeInterval(0.1)),
                       "A drag that starts straight away still seeks")
        XCTAssertTrue(longPress.activatesSelection(touchDown: down, firstMove: down.addingTimeInterval(0.4)))
        XCTAssertTrue(WaveformSelectionOptions.editor.activatesSelection(touchDown: down, firstMove: down))
    }

    func testSelectionAccessibilityStep() {
        XCTAssertEqual(WaveformSelectionOptions(snapInterval: 0.25).accessibilityStep(duration: 600), 0.25)
        XCTAssertEqual(WaveformSelectionOptions().accessibilityStep(duration: 600), 6, accuracy: 1e-9)
        XCTAssertEqual(WaveformSelectionOptions(minimumLength: 0.5).accessibilityStep(duration: 10), 0.5,
                       "Never smaller than the minimum length")
    }

    // MARK: Timeline mapping

    func testTimelineWithoutViewportCoversWholeFile() {
        let t = WaveformTimeline(duration: 60, viewport: nil, width: 300)
        XCTAssertEqual(t.visibleRange, 0...60)
        XCTAssertEqual(t.x(for: 30), 150, accuracy: 1e-9)
        XCTAssertEqual(t.time(forX: 75), 15, accuracy: 1e-9)
    }

    func testTimelineFollowsZoomedViewport() {
        var vp = WaveformViewport(duration: 60)
        vp.visibleRange = 20...30
        let t = WaveformTimeline(duration: 60, viewport: vp, width: 200)
        XCTAssertEqual(t.x(for: 25), 100, accuracy: 1e-9)
        XCTAssertEqual(t.time(forX: 0), 20, accuracy: 1e-9)
        XCTAssertLessThan(t.x(for: 10), 0, "Times before the window land off the leading edge")
        XCTAssertEqual(t.time(forX: 999), 30, accuracy: 1e-9, "Positions are clamped to the window")
    }

    func testTimelineHandlesEmptyInput() {
        let t = WaveformTimeline(duration: 0, viewport: nil, width: 300)
        XCTAssertEqual(t.pointsPerSecond, 0)
        XCTAssertEqual(t.x(for: 5), 0)
        XCTAssertEqual(WaveformTimeline(duration: 60, viewport: nil, width: 0).time(forX: 10), 0)
    }

    // MARK: Edge hit-testing

    func testSelectionEdgeHitTest() {
        let t = WaveformTimeline(duration: 60, viewport: nil, width: 600)   // 10 pt per second
        let sel: ClosedRange<TimeInterval> = 10...30                        // x = 100 ... 300
        XCTAssertEqual(SelectionEdge.hitTest(x: 110, selection: sel, timeline: t), .start)
        XCTAssertEqual(SelectionEdge.hitTest(x: 285, selection: sel, timeline: t), .end)
        XCTAssertNil(SelectionEdge.hitTest(x: 200, selection: sel, timeline: t),
                     "The middle of a selection is not a handle")
        XCTAssertNil(SelectionEdge.hitTest(x: 123, selection: sel, timeline: t),
                     "Outside the 44-point target")
    }

    func testSelectionEdgeHitTestPrefersNearerEdgeWhenTargetsOverlap() {
        let t = WaveformTimeline(duration: 60, viewport: nil, width: 600)
        let narrow: ClosedRange<TimeInterval> = 10...12                     // x = 100 ... 120
        XCTAssertEqual(SelectionEdge.hitTest(x: 104, selection: narrow, timeline: t), .start)
        XCTAssertEqual(SelectionEdge.hitTest(x: 117, selection: narrow, timeline: t), .end)
    }

    // MARK: Markers while zoomed (fix shipped with selection)

    func testMarkerHitTestFollowsZoomedViewport() {
        // 60 s on 600 pt.  Zoomed to 20...30, a marker at 25 s is drawn at x = 300, not x = 250.
        let m = WaveformMarker(time: 25, color: .red)
        let size = CGSize(width: 600, height: 60)
        let zoomedHit = WaveformView.hitTestMarker(
            [m], at: CGPoint(x: 300, y: 30), in: size, duration: 60, style: .bars(),
            visibleRange: 20...30
        )
        XCTAssertEqual(zoomedHit?.id, m.id)
        let staleHit = WaveformView.hitTestMarker(
            [m], at: CGPoint(x: 250, y: 30), in: size, duration: 60, style: .bars(),
            visibleRange: 20...30
        )
        XCTAssertNil(staleHit, "The full-duration position must no longer hit while zoomed")
    }

    func testMarkerHitTestDefaultsToWholeFile() {
        let m = WaveformMarker(time: 25, color: .red)
        let hit = WaveformView.hitTestMarker(
            [m], at: CGPoint(x: 250, y: 30), in: CGSize(width: 600, height: 60),
            duration: 60, style: .bars()
        )
        XCTAssertEqual(hit?.id, m.id)
    }
}

// MARK: - Right-to-left timelines (Phase 5)

extension WaveformKitTests {

    func testTimelineDirectionResolution() {
        XCTAssertTrue(WaveformTimelineDirection.automatic.isRightToLeft(in: .rightToLeft))
        XCTAssertFalse(WaveformTimelineDirection.automatic.isRightToLeft(in: .leftToRight))
        XCTAssertFalse(WaveformTimelineDirection.leftToRight.isRightToLeft(in: .rightToLeft),
                       "An explicit direction overrides the layout")
        XCTAssertTrue(WaveformTimelineDirection.rightToLeft.isRightToLeft(in: .leftToRight))
    }

    func testTimelineDirectionDefaultsToAutomatic() {
        XCTAssertEqual(EnvironmentValues().waveformTimelineDirection, .automatic,
                       "Follows the layout direction unless the app says otherwise (HIG: flip progress controls)")
    }

    func testRightToLeftTimelineMirrorsPositions() {
        let t = WaveformTimeline(duration: 60, viewport: nil, width: 600, rightToLeft: true)
        XCTAssertEqual(t.x(for: 0), 600, accuracy: 1e-9, "Time starts at the right edge")
        XCTAssertEqual(t.x(for: 60), 0, accuracy: 1e-9)
        XCTAssertEqual(t.x(for: 15), 450, accuracy: 1e-9)
        XCTAssertEqual(t.time(forX: 450), 15, accuracy: 1e-9)
        XCTAssertEqual(t.progress(forX: 600), 0, accuracy: 1e-9)
        XCTAssertEqual(t.progress(forX: -50), 1, accuracy: 1e-9, "Clamped past the trailing edge")
    }

    func testRightToLeftTimelineWhileZoomed() {
        var vp = WaveformViewport(duration: 60)
        vp.visibleRange = 20...30
        let t = WaveformTimeline(duration: 60, viewport: vp, width: 200, rightToLeft: true)
        XCTAssertEqual(t.x(for: 20), 200, accuracy: 1e-9)
        XCTAssertEqual(t.x(for: 22.5), 150, accuracy: 1e-9)
        XCTAssertEqual(t.time(forX: 0), 30, accuracy: 1e-9)
        XCTAssertGreaterThan(t.x(for: 10), 200, "Earlier times land off the right edge")
    }

    func testTimelineRoundTripsInBothDirections() {
        for rtl in [false, true] {
            let t = WaveformTimeline(duration: 90, viewport: nil, width: 375, rightToLeft: rtl)
            for time in stride(from: 0.0, through: 90, by: 7.5) {
                XCTAssertEqual(t.time(forX: t.x(for: time)), time, accuracy: 1e-9)
            }
        }
    }

    func testSelectionEdgesSwapSidesWhenRightToLeft() {
        let t = WaveformTimeline(duration: 60, viewport: nil, width: 600, rightToLeft: true)
        let sel: ClosedRange<TimeInterval> = 10...30        // start at x = 500, end at x = 300
        XCTAssertEqual(SelectionEdge.hitTest(x: 500, selection: sel, timeline: t), .start)
        XCTAssertEqual(SelectionEdge.hitTest(x: 300, selection: sel, timeline: t), .end)
    }

    func testMarkerHitTestRightToLeft() {
        let size = CGSize(width: 600, height: 60)
        let point = WaveformMarker(time: 15, color: .red)          // x = 450 when RTL
        XCTAssertEqual(WaveformView.hitTestMarker(
            [point], at: CGPoint(x: 450, y: 30), in: size, duration: 60, style: .bars(),
            rightToLeft: true
        )?.id, point.id)
        XCTAssertNil(WaveformView.hitTestMarker(
            [point], at: CGPoint(x: 150, y: 30), in: size, duration: 60, style: .bars(),
            rightToLeft: true
        ), "The left-to-right position must not hit")

        let region = WaveformMarker(time: 10, duration: 20, color: .blue)   // x = 300...500
        XCTAssertEqual(WaveformView.hitTestMarker(
            [region], at: CGPoint(x: 400, y: 30), in: size, duration: 60, style: .bars(),
            rightToLeft: true
        )?.id, region.id, "Inside a region whose start is its right edge")
    }

    func testPanFollowsTheFingerInBothDirections() {
        // 300 pt showing 30 s: 10 pt per second.  Dragging right by 50 pt…
        let ltr = WaveformZoomOptions.panSeconds(deltaPoints: 50, visibleSpan: 30, width: 300)
        let rtl = WaveformZoomOptions.panSeconds(deltaPoints: 50, visibleSpan: 30, width: 300, rightToLeft: true)
        XCTAssertEqual(ltr, -5, accuracy: 1e-9, "…reveals earlier audio when time runs left to right")
        XCTAssertEqual(rtl, 5, accuracy: 1e-9, "…and later audio when it runs right to left")
    }
}
