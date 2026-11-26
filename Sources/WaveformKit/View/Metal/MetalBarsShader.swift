import SwiftUI

/// Shader source and CPU-side data layout for the Metal bar renderer.
///
/// ## Why the shader is a string
///
/// A `.metal` file in the package would be compiled by Xcode's Metal toolchain, which since
/// Xcode 26 is a separate download (`xcodebuild -downloadComponent MetalToolchain`).  Shipping
/// one would break the build for every consumer who has not installed it — for a feature most
/// of them never turn on.  Compiling this source at runtime with
/// `MTLDevice.makeLibrary(source:options:)` uses the compiler built into the OS instead, costs
/// a few milliseconds once per process off the main thread, and is cached by Metal across
/// launches.
///
/// ## Data layout
///
/// Every struct shared with the GPU is built from `SIMD4<Float>` fields only, so its Swift
/// layout matches Metal's `float4` layout with no padding to get wrong.  Tests pin the strides.
enum MetalBarsShader {

    static let vertexFunctionName = "waveformBarVertex"
    static let fragmentFunctionName = "waveformBarFragment"

    /// Colour stops per shading.  The stop table holds the played shading in the first half and
    /// the unplayed shading in the second.
    static let maximumStopsPerShading = 16

    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float4 layout;      // view width, view height, bar width, step (bar width + spacing)
        float4 shape;       // corner radius, minimum bar height, amplitude scale, progress x
        float4 flags;       // bar count, mirrored, shows progress, points per pixel
        float4 stopCounts;  // played stops, unplayed stops, unused, unused
    };

    struct Stop {
        float4 color;       // straight (not premultiplied) sRGB-encoded RGBA
        float4 location;    // x = position in 0...1 across the view's width
    };

    struct BarVertex {
        float4 position [[position]];
        float2 local;               // offset from the bar's centre, in points
        float2 halfSize [[flat]];
        float pointX;               // x in view space, for horizontal gradients
        float played [[flat]];
    };

    vertex BarVertex waveformBarVertex(uint vid [[vertex_id]],
                                       uint iid [[instance_id]],
                                       const device float *amplitudes [[buffer(0)]],
                                       constant Uniforms &u [[buffer(1)]]) {
        float width = u.layout.x;
        float height = u.layout.y;
        float barWidth = u.layout.z;

        // Matches BarLayout.barHeight: at least the minimum, at most the view's height.
        float amplitude = max(amplitudes[iid], 0.0) * u.shape.z;
        float h = max(u.shape.y, min(height, amplitude * height));
        float x = float(iid) * u.layout.w;
        float top = u.flags.y > 0.5 ? (height - h) * 0.5 : height - h;

        float2 halfSize = float2(barWidth * 0.5, h * 0.5);
        float2 center = float2(x + halfSize.x, top + halfSize.y);

        // Grow the quad by one pixel so the antialiased edge has room to fade out.
        float pad = u.flags.w;
        float2 corner = float2((vid & 1) ? 1.0 : -1.0, (vid & 2) ? 1.0 : -1.0);
        float2 p = center + corner * (halfSize + pad);

        BarVertex out;
        out.position = float4(p.x / width * 2.0 - 1.0, 1.0 - p.y / height * 2.0, 0.0, 1.0);
        out.local = p - center;
        out.halfSize = halfSize;
        out.pointX = p.x;
        // Same rule as the Canvas renderer: a bar is played once its centre is behind the playhead.
        out.played = (u.flags.z < 0.5 || center.x <= u.shape.w) ? 1.0 : 0.0;
        return out;
    }

    float4 sampleStops(constant Stop *stops, uint offset, uint count, float t) {
        if (count <= 1 || t <= stops[offset].location.x) {
            return stops[offset].color;
        }
        for (uint i = 1; i < count; i++) {
            Stop a = stops[offset + i - 1];
            Stop b = stops[offset + i];
            if (t <= b.location.x) {
                float span = max(b.location.x - a.location.x, 1e-5);
                return mix(a.color, b.color, clamp((t - a.location.x) / span, 0.0, 1.0));
            }
        }
        return stops[offset + count - 1].color;
    }

    fragment float4 waveformBarFragment(BarVertex in [[stage_in]],
                                        constant Uniforms &u [[buffer(0)]],
                                        constant Stop *stops [[buffer(1)]]) {
        // Signed distance to the rounded rectangle, then one pixel of coverage falloff.
        float r = min(u.shape.x, min(in.halfSize.x, in.halfSize.y));
        float2 q = abs(in.local) - in.halfSize + r;
        float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
        float coverage = clamp(0.5 - d / u.flags.w, 0.0, 1.0);
        if (coverage <= 0.0) {
            discard_fragment();
        }

        bool played = in.played > 0.5;
        uint offset = played ? 0 : \(maximumStopsPerShading);
        uint count = uint(played ? u.stopCounts.x : u.stopCounts.y);
        float4 c = sampleStops(stops, offset, count, clamp(in.pointX / u.layout.x, 0.0, 1.0));

        // Premultiplied output for the pipeline's one / one-minus-source-alpha blend.
        return float4(c.rgb * c.a, c.a) * coverage;
    }
    """
}

// MARK: - GPU structs

/// Mirrors `Uniforms` in `MetalBarsShader.source`.
struct MetalBarUniforms: Equatable {
    var layout: SIMD4<Float>
    var shape: SIMD4<Float>
    var flags: SIMD4<Float>
    var stopCounts: SIMD4<Float>

    init(
        size: CGSize,
        barCount: Int,
        spacing: CGFloat,
        cornerRadius: CGFloat,
        amplitudeScale: CGFloat,
        progress: Double,
        showsProgress: Bool,
        mirrored: Bool,
        pointsPerPixel: CGFloat,
        playedStopCount: Int,
        unplayedStopCount: Int
    ) {
        let bars = BarLayout(count: barCount, width: size.width, spacing: spacing)
        layout = SIMD4(Float(size.width), Float(size.height), Float(bars.barWidth), Float(bars.step))
        shape = SIMD4(
            Float(max(0, cornerRadius)),
            Float(BarLayout.minimumBarHeight),
            Float(amplitudeScale),
            Float(size.width * CGFloat(min(1, max(0, progress))))
        )
        flags = SIMD4(
            Float(barCount),
            mirrored ? 1 : 0,
            showsProgress ? 1 : 0,
            // Guard the shader's divide: a zero would turn every edge into NaN coverage.
            Float(pointsPerPixel > 0 ? pointsPerPixel : 0.5)
        )
        stopCounts = SIMD4(Float(playedStopCount), Float(unplayedStopCount), 0, 0)
    }
}

/// Mirrors `Stop` in `MetalBarsShader.source`.
struct MetalGradientStop: Equatable {
    var color: SIMD4<Float>
    var location: SIMD4<Float>

    static let clear = MetalGradientStop(color: SIMD4<Float>(repeating: 0), location: 0)

    init(color: SIMD4<Float>, location: Float) {
        self.color = color
        self.location = SIMD4(location, 0, 0, 0)
    }

    /// The stops for one shading — a solid colour, or a horizontal gradient across the view's
    /// width, matching the Canvas renderer's `.linearGradient` from leading to trailing edge.
    ///
    /// Colours are resolved against `environment`, so light/dark and accent colours follow the
    /// view.  Components are clamped to `0...1`: wide-gamut colours render at their nearest sRGB
    /// value.  Gradients longer than `maximumStopsPerShading` keep their first stops.
    static func stops(
        color: Color,
        gradient: Gradient?,
        in environment: EnvironmentValues
    ) -> [MetalGradientStop] {
        guard let gradient, !gradient.stops.isEmpty else {
            return [MetalGradientStop(color: rgba(color, in: environment), location: 0)]
        }
        return gradient.stops
            .sorted { $0.location < $1.location }
            .prefix(MetalBarsShader.maximumStopsPerShading)
            .map { MetalGradientStop(color: rgba($0.color, in: environment), location: Float($0.location)) }
    }

    /// The fixed-size table the fragment shader reads: played stops, then unplayed stops, each
    /// padded to `maximumStopsPerShading`.
    static func table(played: [MetalGradientStop], unplayed: [MetalGradientStop]) -> [MetalGradientStop] {
        let n = MetalBarsShader.maximumStopsPerShading
        func padded(_ stops: [MetalGradientStop]) -> [MetalGradientStop] {
            let head = Array(stops.prefix(n))
            return head + Array(repeating: .clear, count: n - head.count)
        }
        return padded(played) + padded(unplayed)
    }

    private static func rgba(_ color: Color, in environment: EnvironmentValues) -> SIMD4<Float> {
        let resolved = color.resolve(in: environment)
        func unit(_ value: Float) -> Float { value.isFinite ? min(1, max(0, value)) : 0 }
        return SIMD4(unit(resolved.red), unit(resolved.green), unit(resolved.blue), unit(resolved.opacity))
    }
}
