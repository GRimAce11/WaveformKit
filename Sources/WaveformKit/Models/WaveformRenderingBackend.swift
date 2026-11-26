import SwiftUI

/// Which drawing technology a `WaveformView` uses for its bars.
///
/// SwiftUI's `Canvas` fills one rounded-rectangle path per bar on the CPU, which is ideal for
/// the 50–200 bars a seek bar usually shows and starts to cost real frame time in the
/// thousands — the range a zoomable editor timeline reaches once a `WaveformSummaryPyramid`
/// gives it the detail to fill them.  The Metal backend draws every bar in a single instanced
/// GPU draw call, so its cost barely moves with the bar count.
///
/// Set it with the `waveformRenderingBackend(_:)` modifier, which applies to every
/// `WaveformView` underneath — one call covers a whole list of rows:
///
/// ```swift
/// WaveformView(summary: summary, currentTime: t, style: .bars(count: 2_000, spacing: 0))
///     .waveformRenderingBackend(.automatic())
/// ```
///
/// ## Scope
///
/// Metal draws `.bars` and `.mirroredBars`.  Every other style, and `WaveformView.snapshot`,
/// always uses `Canvas`.  When Metal is unavailable, or while its shader is still compiling on
/// first use, the view draws with `Canvas` and switches over by itself.
public enum WaveformRenderingBackend: Sendable, Hashable {

    /// Always `Canvas`.  The default, and the behaviour of every release before 0.7.0.
    case canvas

    /// Metal for `.bars` and `.mirroredBars` at any bar count.
    case metal

    /// Metal once a bar style asks for at least `minimumBarCount` bars, `Canvas` below that.
    ///
    /// Few bars gain nothing from the GPU, and each Metal waveform keeps its own drawable, so
    /// leaving small views on `Canvas` keeps a long list of rows cheap.
    case automatic(minimumBarCount: Int = 512)

    /// Whether a bar style with `barCount` bars should be drawn with Metal.
    public func prefersMetal(barCount: Int) -> Bool {
        switch self {
        case .canvas:                        return false
        case .metal:                         return true
        case .automatic(let minimumBarCount): return barCount >= minimumBarCount
        }
    }
}

// MARK: - Environment

private struct WaveformRenderingBackendKey: EnvironmentKey {
    static let defaultValue = WaveformRenderingBackend.canvas
}

extension EnvironmentValues {
    /// The backend `WaveformView`s in this environment draw bars with.
    public var waveformRenderingBackend: WaveformRenderingBackend {
        get { self[WaveformRenderingBackendKey.self] }
        set { self[WaveformRenderingBackendKey.self] = newValue }
    }
}

extension View {
    /// Chooses how `WaveformView`s inside this view draw their bars.
    ///
    /// See `WaveformRenderingBackend` for what each option does and which styles it covers.
    public func waveformRenderingBackend(_ backend: WaveformRenderingBackend) -> some View {
        environment(\.waveformRenderingBackend, backend)
    }
}
