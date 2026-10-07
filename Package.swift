// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacPulse",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacPulse", targets: ["MacPulse"]),
        .executable(name: "MacPulseProbe", targets: ["MacPulseProbe"])
    ],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "TelemetryBridge", linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation"), .linkedFramework("CoreAudio")]),
        .target(name: "MetricsCore", dependencies: ["TelemetryBridge", "CSQLite"]),
        // The standalone bundle assembler installs these at Contents/Resources.
        .executableTarget(name: "MacPulse", dependencies: ["MetricsCore"], exclude: ["Resources"]),
        .executableTarget(name: "MacPulseProbe", dependencies: ["MetricsCore"]),
        .testTarget(name: "MetricsCoreTests", dependencies: ["MetricsCore"])
    ]
)
