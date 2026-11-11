import Foundation

/// What the current device's cameras can do, published as plain values.
///
/// A ``CaptureBackend`` builds this at run time (progressive enhancement: AGENTS.md, "Code").
/// Interfaces show a feature only when the matching value says the device supports it.
public struct DeviceCapabilities: Equatable, Sendable {
    /// The physical lenses available, in the order an interface should list them.
    public let lenses: [Lens]

    /// A device with no usable camera, such as the iOS Simulator.
    public static let none = DeviceCapabilities(lenses: [])

    /// Creates a capability description.
    ///
    /// - Parameter lenses: The physical lenses available, in display order.
    public init(lenses: [Lens]) {
        self.lenses = lenses
    }

    /// Whether the device has at least one camera nope. can use.
    public var hasCamera: Bool {
        !lenses.isEmpty
    }

    /// Whether at least one lens delivers single-frame Bayer RAW.
    ///
    /// When it's `false`, every photo uses the labeled HEIF fallback.
    public var supportsBayerRAW: Bool {
        lenses.contains { $0.supportsBayerRAW }
    }
}
