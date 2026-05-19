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

    func testResampleDownsample() {
        // 4 bins → 2 bins: each output is mean of 2 input bins.
        let src: [Float] = [0.2, 0.4, 0.6, 0.8]
        let result = resampleAmplitudes(src: src, startIdx: 0, endIdx: 4, targetCount: 2)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0], 0.3, accuracy: 1e-5)
        XCTAssertEqual(result[1], 0.7, accuracy: 1e-5)
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
}
