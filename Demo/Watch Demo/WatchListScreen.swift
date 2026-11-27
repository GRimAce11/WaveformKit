import SwiftUI
import WaveformKit

/// Waveform rows in a `List` with `.inScrollView`: the crown must keep scrolling the list, and
/// taps still seek.
struct WatchListScreen: View {
    @State private var positions: [TimeInterval] = Array(repeating: 0, count: 6)
    @State private var viewports: [WaveformViewport] = (0..<6).map { _ in WaveformViewport(duration: 30) }

    var body: some View {
        List(0..<6, id: \.self) { index in
            VStack(alignment: .leading, spacing: 4) {
                Text("Episode \(index + 1)").font(.footnote)
                WaveformView(
                    summary:     .demo(duration: 30, bars: 120, seed: UInt64(index + 1)),
                    currentTime: positions[index],
                    style:       .bars(count: 28, spacing: 2),
                    viewport:    $viewports[index],
                    zoom:        .inScrollView,
                    onSeek:      { positions[index] = $0 }
                )
                .frame(height: 28)
            }
        }
        .navigationTitle("In a list")
    }
}
