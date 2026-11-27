import SwiftUI

/// Draws `.bars` / `.mirroredBars` with whichever backend the environment asks for.
///
/// Falls back to the `Canvas` renderer whenever Metal cannot draw yet — no device, or the
/// shader still compiling on first use — so the view is never blank.  Where MetalKit does not
/// exist (watchOS), it is always `Canvas`.
struct BarsView: View {
    let amplitudes: [Float]
    let progress: Double
    let amplitudeScale: CGFloat
    let showsProgress: Bool
    let spacing: CGFloat
    let cornerRadius: CGFloat
    let colors: WaveformColors
    let mirrored: Bool

    @Environment(\.waveformRenderingBackend) private var backend

    var body: some View {
        #if canImport(MetalKit)
        let wantsMetal = backend.prefersMetal(barCount: amplitudes.count)
        // Reading `resources` registers an observation, so this view re-renders when the
        // shader finishes compiling.
        if wantsMetal, let resources = MetalBarsPipeline.shared.resources {
            MetalBarsView(
                resources: resources,
                amplitudes: amplitudes, progress: progress, amplitudeScale: amplitudeScale,
                showsProgress: showsProgress, spacing: spacing, cornerRadius: cornerRadius,
                colors: colors, mirrored: mirrored
            )
        } else {
            canvas
                .task(id: wantsMetal) {
                    if wantsMetal { MetalBarsPipeline.shared.prepareIfNeeded() }
                }
        }
        #else
        canvas
        #endif
    }

    private var canvas: BarsRenderer {
        BarsRenderer(
            amplitudes: amplitudes, progress: progress, amplitudeScale: amplitudeScale,
            showsProgress: showsProgress, spacing: spacing, cornerRadius: cornerRadius,
            colors: colors, mirrored: mirrored
        )
    }
}
