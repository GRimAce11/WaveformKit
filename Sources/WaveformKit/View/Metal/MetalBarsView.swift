// MetalKit does not exist on watchOS; `BarsView` draws with `Canvas` there.
#if canImport(MetalKit)
import SwiftUI
import MetalKit
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Representable

/// Hosts a `WaveformMetalView` in SwiftUI.  Inputs flow in through `update`; the view redraws
/// only when they change, never on a display-link loop.
///
/// `@MainActor` on the whole type, not just the representable conformance: the helpers below
/// create and mutate the main-actor `WaveformMetalView`, and would otherwise be nonisolated.
@MainActor
struct MetalBarsView {
    let resources: MetalBarsResources
    let amplitudes: [Float]
    let progress: Double
    let amplitudeScale: CGFloat
    let showsProgress: Bool
    let spacing: CGFloat
    let cornerRadius: CGFloat
    let colors: WaveformColors
    let mirrored: Bool

    fileprivate func makeView() -> WaveformMetalView {
        WaveformMetalView(resources: resources)
    }

    fileprivate func update(_ view: WaveformMetalView, environment: EnvironmentValues) {
        let played = MetalGradientStop.stops(
            color: colors.played, gradient: colors.playedGradient, in: environment
        )
        let unplayed = MetalGradientStop.stops(
            color: colors.unplayed, gradient: colors.unplayedGradient, in: environment
        )
        view.frameData = WaveformMetalView.FrameData(
            amplitudes: amplitudes,
            progress: progress,
            amplitudeScale: amplitudeScale,
            showsProgress: showsProgress,
            spacing: spacing,
            cornerRadius: cornerRadius,
            mirrored: mirrored,
            stops: MetalGradientStop.table(played: played, unplayed: unplayed),
            playedStopCount: played.count,
            unplayedStopCount: unplayed.count
        )
    }
}

#if os(macOS)
extension MetalBarsView: NSViewRepresentable {
    func makeNSView(context: Context) -> WaveformMetalView { makeView() }
    func updateNSView(_ view: WaveformMetalView, context: Context) {
        update(view, environment: context.environment)
    }
}
#else
extension MetalBarsView: UIViewRepresentable {
    func makeUIView(context: Context) -> WaveformMetalView { makeView() }
    func updateUIView(_ view: WaveformMetalView, context: Context) {
        update(view, environment: context.environment)
    }
}
#endif

// MARK: - MTKView

/// Draws one row of bars in a single instanced draw call.
///
/// Subclasses `MTKView` and overrides `draw(_:)` rather than using an `MTKViewDelegate`, which
/// Apple documents as the delegate's alternative.  `UIView` and `NSView` are main-actor
/// isolated on every SDK, so the override is too — whereas the delegate protocol's isolation
/// annotations differ between SDK releases.
final class WaveformMetalView: MTKView {

    struct FrameData: Equatable {
        var amplitudes: [Float]
        var progress: Double
        var amplitudeScale: CGFloat
        var showsProgress: Bool
        var spacing: CGFloat
        var cornerRadius: CGFloat
        var mirrored: Bool
        var stops: [MetalGradientStop]
        var playedStopCount: Int
        var unplayedStopCount: Int
    }

    /// Setting new data schedules exactly one redraw; identical data schedules none.
    var frameData: FrameData? {
        didSet {
            guard frameData != oldValue else { return }
            requestRedraw()
        }
    }

    private let resources: MetalBarsResources

    /// Amplitude buffers in flight.  Three lets the CPU fill one while the GPU reads another
    /// and a third waits to be presented, without ever writing a buffer the GPU is reading.
    private static let maxFramesInFlight = 3
    private var amplitudeBuffers: [MTLBuffer?] = Array(
        repeating: nil, count: WaveformMetalView.maxFramesInFlight
    )
    private var bufferIndex = 0
    private let inFlight = DispatchSemaphore(value: WaveformMetalView.maxFramesInFlight)

    init(resources: MetalBarsResources) {
        self.resources = resources
        super.init(frame: .zero, device: resources.device)
        colorPixelFormat = MetalBarsResources.pixelFormat
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        framebufferOnly = true
        // Draw on demand: only when `frameData` changes or the view resizes.
        isPaused = true
        enableSetNeedsDisplay = true
        #if os(macOS)
        wantsLayer = true
        layer?.isOpaque = false
        #else
        isOpaque = false
        backgroundColor = .clear
        // Touches belong to the SwiftUI gestures on the enclosing `WaveformView`.
        isUserInteractionEnabled = false
        #endif
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("WaveformMetalView is created in code only")
    }

    // Drawing is on demand, so a resize — rotation, a fold on iPhone Duo, a window drag — has to
    // ask for a frame explicitly, or the previous drawable is stretched to the new bounds.
    #if os(macOS)
    /// Let clicks and drags fall through to the SwiftUI gestures on the enclosing view.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        requestRedraw()
    }
    #else
    override func layoutSubviews() {
        super.layoutSubviews()
        requestRedraw()
    }
    #endif

    private func requestRedraw() {
        #if os(macOS)
        needsDisplay = true
        #else
        setNeedsDisplay()
        #endif
    }

    override func draw(_ rect: CGRect) {
        guard let frameData else { return }

        // Wait for a free amplitude buffer before acquiring a drawable, as Apple's samples do.
        inFlight.wait()
        guard let pass = currentRenderPassDescriptor,
              let drawable = currentDrawable,
              let commandBuffer = resources.queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass)
        else {
            inFlight.signal()
            return
        }
        // Explicitly `@Sendable`: Metal calls this on its own thread.  A plain closure written
        // here would inherit main-actor isolation on SDKs whose parameter is not `@Sendable`,
        // and Swift 6 traps when a main-actor closure runs off the main thread.
        let semaphore = inFlight
        commandBuffer.addCompletedHandler { @Sendable _ in semaphore.signal() }

        let size = bounds.size
        let count = frameData.amplitudes.count
        if count > 0, size.width > 0, size.height > 0, drawableSize.width > 0,
           let buffer = amplitudeBuffer(for: frameData.amplitudes) {
            var uniforms = MetalBarUniforms(
                size: size,
                barCount: count,
                spacing: frameData.spacing,
                cornerRadius: frameData.cornerRadius,
                amplitudeScale: frameData.amplitudeScale,
                progress: frameData.progress,
                showsProgress: frameData.showsProgress,
                mirrored: frameData.mirrored,
                pointsPerPixel: size.width / drawableSize.width,
                playedStopCount: frameData.playedStopCount,
                unplayedStopCount: frameData.unplayedStopCount
            )
            encoder.setRenderPipelineState(resources.pipeline)
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<MetalBarUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<MetalBarUniforms>.stride, index: 0)
            frameData.stops.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                encoder.setFragmentBytes(base, length: bytes.count, index: 1)
            }
            encoder.drawPrimitives(
                type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: count
            )
        }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// The next buffer in the ring, grown if needed and filled with `amplitudes`.
    private func amplitudeBuffer(for amplitudes: [Float]) -> MTLBuffer? {
        bufferIndex = (bufferIndex + 1) % Self.maxFramesInFlight
        let length = amplitudes.count * MemoryLayout<Float>.stride
        if (amplitudeBuffers[bufferIndex]?.length ?? 0) < length {
            amplitudeBuffers[bufferIndex] = resources.device.makeBuffer(
                length: length, options: .storageModeShared
            )
        }
        guard let buffer = amplitudeBuffers[bufferIndex] else { return nil }
        amplitudes.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            buffer.contents().copyMemory(from: base, byteCount: length)
        }
        return buffer
    }
}

#endif
