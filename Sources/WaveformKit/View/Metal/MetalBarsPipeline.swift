import Metal
import Observation

/// The device, queue, and compiled pipeline every Metal waveform shares.
///
/// `@unchecked Sendable` safety invariant: every stored property is an immutable `let`, and
/// Apple documents `MTLDevice`, `MTLCommandQueue`, and `MTLRenderPipelineState` as safe to use
/// from any thread.  Recent SDKs already mark them `Sendable`; older SDKs the package still
/// builds against do not, and the resources are created on a background task and handed to the
/// main actor, so the conformance has to be stated here rather than inferred.
final class MetalBarsResources: @unchecked Sendable {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState

    /// The pixel format both the pipeline and every view use.
    static let pixelFormat = MTLPixelFormat.bgra8Unorm

    private init(device: MTLDevice, queue: MTLCommandQueue, pipeline: MTLRenderPipelineState) {
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
    }

    /// Compiles the shader and builds the pipeline.  Blocking, so call it off the main thread.
    /// Returns `nil` when there is no Metal device or compilation fails; callers fall back to
    /// `Canvas`.
    static func make() -> MetalBarsResources? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: MetalBarsShader.source, options: nil),
              let vertex = library.makeFunction(name: MetalBarsShader.vertexFunctionName),
              let fragment = library.makeFunction(name: MetalBarsShader.fragmentFunctionName)
        else { return nil }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "WaveformKit bars"
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        let attachment = descriptor.colorAttachments[0]
        attachment?.pixelFormat = pixelFormat
        // The fragment shader writes premultiplied colour.
        attachment?.isBlendingEnabled = true
        attachment?.rgbBlendOperation = .add
        attachment?.alphaBlendOperation = .add
        attachment?.sourceRGBBlendFactor = .one
        attachment?.sourceAlphaBlendFactor = .one
        attachment?.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment?.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }
        return MetalBarsResources(device: device, queue: queue, pipeline: pipeline)
    }
}

/// Builds `MetalBarsResources` once per process, in the background, the first time a view asks.
///
/// Observable so that a view drawing with `Canvas` while the shader compiles re-renders and
/// switches to Metal by itself once it is ready.
@Observable
@MainActor
final class MetalBarsPipeline {

    static let shared = MetalBarsPipeline()

    enum State {
        case idle
        case compiling
        case ready(MetalBarsResources)
        /// No Metal device, or the shader failed to compile.  Permanent for the process.
        case unavailable
    }

    private(set) var state: State = .idle

    /// The shared resources once compiled, otherwise `nil`.
    var resources: MetalBarsResources? {
        if case .ready(let resources) = state { return resources }
        return nil
    }

    /// Starts compiling if nothing has asked yet.  Cheap to call repeatedly.
    func prepareIfNeeded() {
        guard case .idle = state else { return }
        state = .compiling
        Task {
            let resources = await Task.detached(priority: .userInitiated) {
                MetalBarsResources.make()
            }.value
            state = resources.map(State.ready) ?? .unavailable
        }
    }
}
