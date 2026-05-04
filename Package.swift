// swift-tools-version: 5.9
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
    ]
)
