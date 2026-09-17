// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WaveformKit",
    // tvOS is deliberately absent: SwiftUI marks `DragGesture` unavailable there, so seeking,
    // panning, marker taps, and double-tap-to-reset cannot compile. Supporting it means a
    // focus-engine interaction model, which is Phase 5 work rather than a platform line here.
    platforms: [.iOS(.v17), .macOS(.v14), .visionOS(.v1)],
    products: [
        .library(name: "WaveformKit", targets: ["WaveformKit"]),
    ],
    targets: [
        .target(name: "WaveformKit"),
        .testTarget(name: "WaveformKitTests", dependencies: ["WaveformKit"]),
    ],
    // v6 is used wherever the toolchain supports it; v5 is listed so the package still builds
    // under a Swift 5 language mode if a consumer pins one.
    swiftLanguageModes: [.v6, .v5]
)
