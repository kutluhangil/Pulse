// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PulseKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PulseCore", targets: ["PulseCore"]),
        .library(name: "PulseClient", targets: ["PulseClient"]),
        .library(name: "PulseUI", targets: ["PulseUI"]),
    ],
    targets: [
        // Models, formatting and alert rules. No UI, no networking.
        .target(name: "PulseCore"),
        // Live connection to the agent (SSE), Keychain.
        .target(name: "PulseClient", dependencies: ["PulseCore"]),
        // SwiftUI panel, tiles, settings.
        .target(name: "PulseUI", dependencies: ["PulseCore", "PulseClient"], resources: [.process("Resources")]),
        .testTarget(name: "PulseCoreTests", dependencies: ["PulseCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "PulseClientTests", dependencies: ["PulseClient"]),
        .testTarget(name: "PulseUITests", dependencies: ["PulseUI"], resources: [.copy("../PulseCoreTests/Fixtures")]),
    ]
)
