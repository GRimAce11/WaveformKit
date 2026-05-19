import SwiftUI

/// Protocol for custom waveform drawing styles.
///
/// Implementations receive pre-resampled amplitude data and draw into a SwiftUI
/// `GraphicsContext`.  The library calls `draw(...)` inside a `Canvas` view, so conforming
/// types must be `Sendable` — Canvas draw closures can execute off the main thread.
///
/// ## Usage
///
/// ```swift
/// struct RainbowBarsRenderer: WaveformRenderer {
///     func draw(
///         context: inout GraphicsContext,
///         size: CGSize,
///         amplitudes: [Float],
///         progress: Double,
///         amplitudeScale: CGFloat,
///         showsProgress: Bool,
///         colors: WaveformColors
///     ) {
///         let barWidth = size.width / CGFloat(amplitudes.count)
///         for (i, amp) in amplitudes.enumerated() {
///             let hue  = Double(i) / Double(amplitudes.count)
///             let h    = CGFloat(amp) * amplitudeScale * size.height
///             let rect = CGRect(x: CGFloat(i) * barWidth,
///                               y: size.height - h,
///                               width: barWidth - 1,
///                               height: h)
///             context.fill(Path(rect), with: .color(Color(hue: hue, saturation: 1, brightness: 1)))
///         }
///     }
/// }
///
/// WaveformView(
///     summary: summary,
///     currentTime: player.currentTime,
///     style: .custom(renderer: RainbowBarsRenderer(), barCount: 80)
/// )
/// ```
public protocol WaveformRenderer: Sendable {

    /// Draw the waveform into `context`.
    ///
    /// - Parameters:
    ///   - context:        SwiftUI drawing context.  Mutated additively.
    ///   - size:           Available drawing area in points.
    ///   - amplitudes:     Pre-resampled values in 0...1.  `amplitudes.count == barCount`
    ///                     from the `.custom(barCount:)` style parameter.
    ///   - progress:       Playback progress in 0...1.  Use to split played/unplayed tinting.
    ///   - amplitudeScale: Reactive boost multiplier (1.0 when movement is `.progress`).
    ///   - showsProgress:  `true` when the played/unplayed colour split should be rendered.
    ///   - colors:         `WaveformColors` from the host view.
    func draw(
        context: inout GraphicsContext,
        size: CGSize,
        amplitudes: [Float],
        progress: Double,
        amplitudeScale: CGFloat,
        showsProgress: Bool,
        colors: WaveformColors
    )
}

// MARK: - Internal Canvas wrapper

/// Wraps a `WaveformRenderer` in a SwiftUI `Canvas` view.
/// Used by `WaveformView` for the `.custom` style case.
struct CustomRendererView: View {
    let renderer: any WaveformRenderer
    let amplitudes: [Float]
    let progress: Double
    let amplitudeScale: CGFloat
    let showsProgress: Bool
    let colors: WaveformColors

    var body: some View {
        Canvas { context, size in
            renderer.draw(
                context: &context,
                size: size,
                amplitudes: amplitudes,
                progress: progress,
                amplitudeScale: amplitudeScale,
                showsProgress: showsProgress,
                colors: colors
            )
        }
    }
}
