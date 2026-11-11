import Foundation

/// A ``CaptureBackend`` that returns fixed answers instead of talking to hardware.
///
/// Use it in tests, SwiftUI previews and UI tests, and in development builds until the
/// AVFoundation adapter is wired in. It never shows a system prompt.
///
/// ```swift
/// let backend = SimulatedCaptureBackend(
///     permission: .notDetermined,
///     permissionAfterRequest: .authorized,
///     capabilities: DeviceCapabilities(lenses: [Lens(id: "wide", kind: .wide, supportsBayerRAW: true)])
/// )
/// let model = CameraModel(backend: backend)
/// ```
public struct SimulatedCaptureBackend: CaptureBackend {
    /// The permission reported before any request.
    public let permission: CameraPermission

    /// The permission reported after ``requestPermission()``.
    public let permissionAfterRequest: CameraPermission

    /// The capabilities reported by ``deviceCapabilities()``.
    public let capabilities: DeviceCapabilities

    /// Creates a simulated backend.
    ///
    /// - Parameters:
    ///   - permission: The permission reported before any request.
    ///   - permissionAfterRequest: The permission reported after a request. Defaults to
    ///     `permission`, as if the person dismissed the prompt without changing anything.
    ///   - capabilities: The capabilities to report. Defaults to ``DeviceCapabilities/none``.
    public init(
        permission: CameraPermission,
        permissionAfterRequest: CameraPermission? = nil,
        capabilities: DeviceCapabilities = .none
    ) {
        self.permission = permission
        self.permissionAfterRequest = permissionAfterRequest ?? permission
        self.capabilities = capabilities
    }

    /// Returns ``permission``.
    public func currentPermission() async -> CameraPermission {
        permission
    }

    /// Returns ``permissionAfterRequest`` without showing a prompt.
    public func requestPermission() async -> CameraPermission {
        permissionAfterRequest
    }

    /// Returns ``capabilities``.
    public func deviceCapabilities() async -> DeviceCapabilities {
        capabilities
    }
}
