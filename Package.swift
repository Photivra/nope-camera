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
    dependencies: [
        // The C2PA library, the only non-platform dependency (AGENTS.md, "Code";
        // security/allowed-dependencies.txt). Pinned exactly; its own dependencies (swift-certificates,
        // swift-asn1, swift-crypto) are pinned by Package.resolved.
        .package(url: "https://github.com/contentauth/c2pa-swift.git", exact: "0.0.16"),
        // Used directly to build each photo's self-issued certificate; also c2pa-swift's own
        // dependencies, so pinned to the same versions Package.resolved records.
        .package(url: "https://github.com/apple/swift-certificates.git", exact: "1.21.1"),
        .package(url: "https://github.com/apple/swift-asn1.git", exact: "1.7.4"),
    ],
    targets: [
        .target(name: "NopeCore", swiftSettings: strictSettings),
        .target(name: "NopeCapture", dependencies: ["NopeCore"], swiftSettings: strictSettings),
        .target(name: "NopeDevelop", dependencies: ["NopeCore"], swiftSettings: strictSettings),
        .target(
            name: "NopeSigning", dependencies: [
                "NopeCore", .product(name: "C2PA", package: "c2pa-swift"),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "SwiftASN1", package: "swift-asn1"),
            ],
            swiftSettings: strictSettings),
        .target(
            name: "NopeUI", dependencies: ["NopeCore"], resources: [.process("Resources")],
            swiftSettings: strictSettings),
        .testTarget(name: "NopeCoreTests", dependencies: ["NopeCore"], swiftSettings: strictSettings),
        .testTarget(
            name: "NopeCaptureTests", dependencies: ["NopeCapture", "NopeCore"], swiftSettings: strictSettings),
        .testTarget(
            name: "NopeDevelopTests", dependencies: ["NopeDevelop", "NopeCore"], swiftSettings: strictSettings),
        .testTarget(
            name: "NopeSigningTests",
            dependencies: [
                "NopeSigning", "NopeCore", .product(name: "C2PA", package: "c2pa-swift"),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "SwiftASN1", package: "swift-asn1"),
            ],
            swiftSettings: strictSettings),
        .testTarget(name: "NopeUITests", dependencies: ["NopeUI", "NopeCore"], swiftSettings: strictSettings),
    ],
    swiftLanguageModes: [.v6]
)
