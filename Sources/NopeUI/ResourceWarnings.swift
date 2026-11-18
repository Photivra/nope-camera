import NopeCore
import SwiftUI

extension CameraWarnings {
    /// "Storage Low" when fewer than `DeviceStatus.lowStoragePhotoCount` photos fit, or
    /// "Storage Full" when the next one doesn't (issue #44).
    ///
    /// - Parameters:
    ///   - context: The model and settings.
    ///   - lastSignature: Not used.
    static func storage(_ context: CameraControlContext, lastSignature: SignatureStatus?) -> CameraWarning? {
        switch context.model.storageWarning {
        case nil:
            return nil
        case .low(let photosThatFit):
            return CameraWarning(
                id: "storage",
                title: Text("Storage Low", bundle: .module, comment: "Warning chip on the camera: the device is almost out of storage for photos."),
                explanation: Text("Photos that still fit on this device: about \(photosThatFit).", bundle: .module, comment: "Explanation of the Storage Low warning on the camera. The number is an estimate of how many more photos, with the chosen formats, fit in the device's free storage."))
        case .full:
            return CameraWarning(
                id: "storage",
                title: Text("Storage Full", bundle: .module, comment: "Warning chip on the camera: the device has no room for another photo."),
                explanation: Text("The next photo won't fit. Free up storage on this device to keep taking photos.", bundle: .module, comment: "Explanation of the Storage Full warning on the camera: saving another photo would fail until the person frees storage."))
        }
    }

    /// "Battery Low" at 3% or less while the device isn't plugged in (issue #44,
    /// ``DeviceStatus/lowBatteryLevel``).
    ///
    /// - Parameters:
    ///   - context: The model and settings.
    ///   - lastSignature: Not used.
    static func battery(_ context: CameraControlContext, lastSignature: SignatureStatus?) -> CameraWarning? {
        guard let warning = context.model.deviceStatus.batteryWarning else { return nil }
        let percent = (Double(warning.percent) / 100).formatted(.percent)
        let explanation =
            warning.isLowPowerMode
            ? Text("Battery at \(percent). Low Power Mode is on.", bundle: .module, comment: "Explanation of the Battery Low warning on the camera while Low Power Mode is on. The value is the battery charge as a percentage, such as 3%, formatted by the system. Low Power Mode is Apple's name for the iPhone and iPad setting.")
            : Text("Battery at \(percent). Charge the device soon to keep taking photos.", bundle: .module, comment: "Explanation of the Battery Low warning on the camera. The value is the battery charge as a percentage, such as 3%, formatted by the system.")
        return CameraWarning(
            id: "battery",
            title: Text("Battery Low", bundle: .module, comment: "Warning chip on the camera: the battery is low and the device isn't charging."),
            explanation: explanation)
    }
}

/// Announces the storage and battery warnings to VoiceOver when they first appear or change,
/// so a person who isn't looking at the screen hears them (issue #44).
struct ResourceWarningAnnouncements: ViewModifier {
    /// The camera model.
    let model: CameraModel

    /// Creates the announcements.
    ///
    /// - Parameter model: The camera model.
    init(model: CameraModel) {
        self.model = model
    }

    /// The content with the announcements attached.
    ///
    /// - Parameter content: The camera.
    func body(content: Content) -> some View {
        content
            // Only a change between none, low and full is announced, not each photo that lowers
            // the count.
            .onChange(of: isStorageFull) { _, _ in
                switch model.storageWarning {
                case nil:
                    break
                case .low(let photosThatFit):
                    Self.announce(String(localized: "Storage low. Photos that still fit on this device: about \(photosThatFit).", bundle: .module, comment: "Announced to VoiceOver when the device is almost out of storage. The number is an estimate of how many more photos fit."))
                case .full:
                    Self.announce(String(localized: "Storage full. The next photo won't fit.", bundle: .module, comment: "Announced to VoiceOver when the device has no room for another photo."))
                }
            }
            .onChange(of: model.deviceStatus.batteryWarning != nil) { _, isLow in
                if isLow {
                    Self.announce(String(localized: "The battery is low.", bundle: .module, comment: "Announced to VoiceOver when the battery is low and the device isn't charging."))
                }
            }
    }

    /// `nil` without a storage warning, `false` when storage is low, `true` when it is full.
    private var isStorageFull: Bool? {
        model.storageWarning.map { $0 == .full }
    }

    /// Posts a VoiceOver announcement.
    ///
    /// - Parameter message: What to say.
    private static func announce(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }
}

extension View {
    /// Announces storage and battery warnings (``ResourceWarningAnnouncements``).
    ///
    /// - Parameter model: The camera model.
    func announcesResourceWarnings(_ model: CameraModel) -> some View {
        modifier(ResourceWarningAnnouncements(model: model))
    }
}
