// swift-tools-version: 6.2
// NopeKit: the modules behind nope. See AGENTS.md, "Architecture: interface separate from logic",
// and docs/ARCHITECTURE.md. Import boundaries are checked by scripts/check-architecture.sh.

import PackageDescription

/// Settings shared by every target: Swift 6 language mode (strict concurrency) and no warnings.
let strictSettings: [SwiftSetting] = [
    .treatAllWarnings(as: .error),
]

/// The network-free C2PA library (`C2PAC`), built from c2pa-rs source by
/// `scripts/build-c2pa-lib.sh` with every network feature off, and published as a release asset
/// of this repository (`c2pa-lib/README.md`). Pinned by its SwiftPM checksum.
///
/// Set `NOPE_C2PA_LIB_FROM_SOURCE=1` to use a local build in `build/c2pa-lib/` instead, for example
/// to test a change to `c2pa-lib/` before it is published.
let c2paLibrary: Target =
    Context.environment["NOPE_C2PA_LIB_FROM_SOURCE"] == "1"
    ? .binaryTarget(name: "C2PAC", path: "build/c2pa-lib/C2PAC.xcframework")
    : .binaryTarget(
        name: "C2PAC",
        url: "https://github.com/Photivra/nope-camera/releases/download/c2pa-lib-v0.92.0/C2PAC.xcframework.zip",
        checksum: "b30f1902d84d34ece70644959f3d6837b5cce4b0b4ae9f8669c446063fc1adb8")

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
        // The C2PA library's Swift wrapper is vendored in Vendor/c2pa-swift (without its
        // networking code) and its C library is c2paLibrary above. These are the wrapper's own
        // dependencies, from Apple, pinned exactly (security/allowed-dependencies.txt).
        // NopeSigning also uses swift-certificates and swift-asn1 to build each photo's certificate.
        .package(url: "https://github.com/apple/swift-certificates.git", exact: "1.21.1"),
        .package(url: "https://github.com/apple/swift-asn1.git", exact: "1.7.4"),
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "4.5.2"),
    ],
    targets: [
        c2paLibrary,
        // c2pa-swift v0.1.0, vendored and trimmed (Vendor/c2pa-swift/README.md). Third-party code
        // keeps its own Swift 5 language mode and isn't held to the warnings-as-errors setting.
        .target(
            name: "C2PA",
            dependencies: [
                "C2PAC",
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "SwiftASN1", package: "swift-asn1"),
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            path: "Vendor/c2pa-swift/Sources/C2PA",
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "NopeCore", swiftSettings: strictSettings),
        // Links NopeSigning into an iOS executable for scripts/check-no-networking.sh only; never
        // shipped (Tools/NopeSigningLinkCheck/main.swift).
        .executableTarget(
            name: "NopeSigningLinkCheck", dependencies: ["NopeSigning", "NopeCore"],
            path: "Tools/NopeSigningLinkCheck", swiftSettings: strictSettings),
        .target(name: "NopeCapture", dependencies: ["NopeCore"], swiftSettings: strictSettings),
        .target(name: "NopeDevelop", dependencies: ["NopeCore"], swiftSettings: strictSettings),
        .target(
            name: "NopeSigning", dependencies: [
                "NopeCore", "C2PA",
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
                "NopeSigning", "NopeCore", "C2PA",
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "SwiftASN1", package: "swift-asn1"),
            ],
            swiftSettings: strictSettings),
        .testTarget(name: "NopeUITests", dependencies: ["NopeUI", "NopeCore"], swiftSettings: strictSettings),
    ],
    swiftLanguageModes: [.v6]
)
