// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WaveformKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
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
