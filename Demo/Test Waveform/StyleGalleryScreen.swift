import SwiftUI
import WaveformKit

/// Renders all six WaveformKit styles side by side so you can compare them at a glance.
/// Great for README screenshots: run on device, scroll to each style, capture.
struct StyleGalleryScreen: View {

    private let summary: WaveformSummary = .demo(duration: 30, bars: 200, seed: 7)

    @State private var movement: WaveformMovement = .progress
    @State private var progress: Double = 0.4
    @State private var accentColor: Color = .blue

    // Simulated amplitude for reactive/dancing modes
    @State private var amplitude: Float = 0
    @State private var bands: [Float] = Array(repeating: 0, count: 32)
    @State private var animationTimer: Timer?

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                movementPicker
                    .padding(.horizontal)

                ForEach(styles, id: \.label) { config in
                    StyleCard(
                        label: config.label,
                        description: config.description,
                        summary: summary,
                        progress: progress,
                        amplitude: amplitude,
                        bands: bands,
                        style: config.style,
                        movement: movement,
                        colors: WaveformColors(
                            played: accentColor,
                            unplayed: accentColor.opacity(0.2),
                            playedGradient: Gradient(colors: [accentColor, accentColor.opacity(0.5)])
                        )
                    )
                }

                colorRow
                    .padding(.horizontal)

                progressSlider
                    .padding(.horizontal)

                Spacer(minLength: 24)
            }
            .padding(.top, 16)
        }
        .navigationTitle("Style Gallery")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: startAnimation)
        .onDisappear(perform: stopAnimation)
    }

    // MARK: - Controls

    private var movementPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Movement").font(.caption).foregroundStyle(.secondary)
            Picker("Movement", selection: $movement) {
                Text("Progress").tag(WaveformMovement.progress)
                Text("Reactive").tag(WaveformMovement.reactive(boost: 1.4))
                Text("Combined").tag(WaveformMovement.combined(boost: 1.0))
                Text("Idle").tag(WaveformMovement.idle)
            }
            .pickerStyle(.segmented)
        }
    }

    private var colorRow: some View {
        HStack {
            Text("Accent color").font(.caption).foregroundStyle(.secondary)
            Spacer()
            ForEach([Color.blue, .purple, .pink, .orange, .green, .red], id: \.self) { c in
                Circle()
                    .fill(c)
                    .frame(width: 26, height: 26)
                    .overlay(
                        Circle().stroke(Color.primary.opacity(accentColor == c ? 0.6 : 0),
                                        lineWidth: 2).padding(2)
                    )
                    .onTapGesture { accentColor = c }
            }
        }
    }

    private var progressSlider: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Progress: \(Int(progress * 100))%").font(.caption).foregroundStyle(.secondary)
            Slider(value: $progress, in: 0...1)
                .tint(accentColor)
        }
    }

    // MARK: - Style definitions

    private struct StyleConfig {
        let label: String
        let description: String
        let style: WaveformStyle
    }

    private let styles: [StyleConfig] = [
        StyleConfig(label: "bars", description: "SoundCloud / podcast seeker",
                    style: .bars(count: 120, spacing: 2, cornerRadius: 1.5)),
        StyleConfig(label: "mirroredBars", description: "WhatsApp / iMessage voice notes",
                    style: .mirroredBars(count: 120, spacing: 2, cornerRadius: 1.5)),
        StyleConfig(label: "dancingBars", description: "Live equalizer / Now Playing",
                    style: .dancingBars(count: 32, spacing: 3, cornerRadius: 2)),
        StyleConfig(label: "line", description: "Smooth filled curve, minimal",
                    style: .line(thickness: 2)),
        StyleConfig(label: "dots", description: "Capsule dots, voice-note compact",
                    style: .dots(count: 60, dotSize: 4, spacing: 4)),
        StyleConfig(label: "circular", description: "Radial bars, album art overlay",
                    style: .circular(count: 64, innerRadiusFraction: 0.45, barWidth: 3)),
    ]

    // MARK: - Simulated reactive animation

    private func startAnimation() {
        var t: Float = 0
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            t += 0.08
            amplitude = abs(sin(t * 0.7)) * 0.6 + 0.15
            bands = (0..<32).map { i in
                let phase = t + Float(i) * 0.4
                return max(0.05, min(1, abs(sin(phase)) * 0.8))
            }
        }
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
}

// MARK: - StyleCard

private struct StyleCard: View {
    let label: String
    let description: String
    let summary: WaveformSummary
    let progress: Double
    let amplitude: Float
    let bands: [Float]
    let style: WaveformStyle
    let movement: WaveformMovement
    let colors: WaveformColors

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(".\(label)")
                    .font(.system(.callout, design: .monospaced))
                    .fontWeight(.medium)
                Spacer()
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            if case .circular = style {
                WaveformView(
                    summary: summary,
                    currentTime: progress * summary.duration,
                    amplitude: amplitude,
                    bands: bands,
                    style: style,
                    movement: movement,
                    colors: colors
                )
                .aspectRatio(1, contentMode: .fit)
                .frame(width: 160, height: 160)
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 16))
            } else {
                WaveformView(
                    summary: summary,
                    currentTime: progress * summary.duration,
                    amplitude: amplitude,
                    bands: bands,
                    style: style,
                    movement: movement,
                    colors: colors
                )
                .frame(height: 80)
                .background(Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)
            }
        }
    }
}

#Preview {
    NavigationStack { StyleGalleryScreen() }
}
