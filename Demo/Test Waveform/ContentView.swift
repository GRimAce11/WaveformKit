import SwiftUI

/// Root navigation screen. Each row is a self-contained demo of one WaveformKit capability.
struct HomeScreen: View {

    struct Demo: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let icon: String
        let iconColor: Color
    }

    private let demos: [Demo] = [
        Demo(title: "Style Gallery",
             subtitle: "All 6 built-in waveform styles",
             icon: "waveform",
             iconColor: .blue),
        Demo(title: "Playback",
             subtitle: "Seek, scrub, markers, player adapters",
             icon: "play.circle.fill",
             iconColor: .green),
        Demo(title: "Async Loading",
             subtitle: "WaveformState lifecycle · progress · error",
             icon: "arrow.down.circle",
             iconColor: .orange),
        Demo(title: "Microphone",
             subtitle: "Live FFT · recording · playback",
             icon: "mic.circle.fill",
             iconColor: .red),
        Demo(title: "Custom Renderer",
             subtitle: "WaveformRenderer protocol examples",
             icon: "paintbrush.fill",
             iconColor: .purple),
        Demo(title: "Viewport",
             subtitle: "Programmatic zoom · visible range",
             icon: "magnifyingglass",
             iconColor: .teal),
    ]

    var body: some View {
        NavigationStack {
            List(demos) { demo in
                NavigationLink { destination(for: demo) } label: {
                    DemoRow(demo: demo)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("WaveformKit")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    @ViewBuilder
    private func destination(for demo: Demo) -> some View {
        switch demo.title {
        case "Style Gallery":    StyleGalleryScreen()
        case "Playback":         PlaybackScreen()
        case "Async Loading":    AsyncLoadingScreen()
        case "Microphone":       MicrophoneScreen()
        case "Custom Renderer":  CustomRendererScreen()
        case "Viewport":         ViewportScreen()
        default:                 Text("Coming soon")
        }
    }
}

private struct DemoRow: View {
    let demo: HomeScreen.Demo

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: demo.icon)
                .font(.title2)
                .foregroundStyle(demo.iconColor)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(demo.title)
                    .font(.body)
                Text(demo.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    HomeScreen()
}
