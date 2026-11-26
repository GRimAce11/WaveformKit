import CoreGraphics

/// Horizontal geometry of a row of bars, shared by the `Canvas` and Metal bar renderers so the
/// two backends put every bar in exactly the same place.
struct BarLayout: Equatable {
    /// Shortest bar drawn, in points, so silence still reads as a row of bars.
    static let minimumBarHeight: CGFloat = 2

    let barWidth: CGFloat
    /// Distance from one bar's leading edge to the next: `barWidth + spacing`.
    let step: CGFloat

    /// Bars never shrink below one point.  When `count` bars plus their spacing cannot fit in
    /// `width`, the row runs past the trailing edge (and is clipped) rather than collapsing.
    /// For very large counts pass a `spacing` of 0.
    init(count: Int, width: CGFloat, spacing: CGFloat) {
        let totalSpacing = spacing * CGFloat(max(0, count - 1))
        barWidth = max(1, (width - totalSpacing) / CGFloat(max(1, count)))
        step = barWidth + spacing
    }

    /// Leading edge of bar `index`.
    func x(at index: Int) -> CGFloat { CGFloat(index) * step }

    /// Height of a bar with this (already scaled) amplitude in a view `height` points tall.
    static func barHeight(amplitude: CGFloat, height: CGFloat) -> CGFloat {
        max(minimumBarHeight, min(height, amplitude * height))
    }
}
