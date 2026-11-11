// swift-tools-version: 6.2
// NopeKit: the modules behind nope. See AGENTS.md, "Architecture: interface separate from logic",
// and docs/ARCHITECTURE.md. Import boundaries are checked by scripts/check-architecture.sh.

import PackageDescription

/// Settings shared by every target: Swift 6 language mode (strict concurrency) and no warnings.
let strictSettings: [SwiftSetting] = [
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "NopeKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "NopeCore", targets: ["NopeCore"]),
        .library(name: "NopeCapture", targets: ["NopeCapture"]),
        .library(name: "NopeDevelop", targets: ["NopeDevelop"]),
        .library(name: "NopeSigning", targets: ["NopeSigning"]),
        .library(name: "NopeUI", targets: ["NopeUI"]),
    ],
    targets: [
        .target(name: "NopeCore", swiftSettings: strictSettings),
        .target(name: "NopeCapture", dependencies: ["NopeCore"], swiftSettings: strictSettings),
        .target(name: "NopeDevelop", dependencies: ["NopeCore"], swiftSettings: strictSettings),
        .target(name: "NopeSigning", dependencies: ["NopeCore"], swiftSettings: strictSettings),
        .target(
            name: "NopeUI", dependencies: ["NopeCore"], resources: [.process("Resources")],
            swiftSettings: strictSettings),
        .testTarget(name: "NopeCoreTests", dependencies: ["NopeCore"], swiftSettings: strictSettings),
        .testTarget(
            name: "NopeCaptureTests", dependencies: ["NopeCapture", "NopeCore"], swiftSettings: strictSettings),
        .testTarget(
            name: "NopeDevelopTests", dependencies: ["NopeDevelop", "NopeCore"], swiftSettings: strictSettings),
        .testTarget(
            name: "NopeSigningTests", dependencies: ["NopeSigning", "NopeCore"], swiftSettings: strictSettings),
        .testTarget(name: "NopeUITests", dependencies: ["NopeUI", "NopeCore"], swiftSettings: strictSettings),
    ],
    swiftLanguageModes: [.v6]
)
