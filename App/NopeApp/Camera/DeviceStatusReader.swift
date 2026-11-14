import Foundation
import NopeCore
import UIKit

/// Reads the free storage and the battery with the system APIs, for the camera's warnings
/// (issue #44). The rules are in `NopeCore.DeviceStatus`; this only reads values.
///
/// Privacy rule (AGENTS.md, "Nothing tracks you"): the values stay on the device and are only
/// shown to the person. The free storage key is a required-reason API, declared in
/// `PrivacyInfo.xcprivacy` (disk space reasons E174.1 and 85F4.1).
@MainActor
struct SystemDeviceStatusReader: DeviceStatusReading {
    /// Turns on battery monitoring, without which UIKit reports the level as unknown
    /// (`UIDevice.isBatteryMonitoringEnabled`).
    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    /// The bytes free for important data on the app's volume, which is also where Photos stores
    /// what nope. adds (Foundation, `volumeAvailableCapacityForImportantUsageKey`).
    func availableStorageBytes() -> Int64? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// The battery level, whether it is plugged in, and Low Power Mode. UIKit reports a level
    /// of -1 when it doesn't know, as in the Simulator.
    func battery() -> BatteryReading? {
        let device = UIDevice.current
        let level = Double(device.batteryLevel)
        return BatteryReading(
            level: level < 0 ? nil : level,
            isCharging: device.batteryState == .charging || device.batteryState == .full,
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }
}

/// The screen's brightness and idle timer through UIKit, for interval shooting (issue #48).
@MainActor
final class SystemScreen: ScreenControlling {
    /// The screen of the app's window (`UIWindowScene.screen`), or `nil` before it appears.
    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes.lazy.compactMap { ($0 as? UIWindowScene)?.screen }.first
    }

    /// The brightness, from 0 to 1 (`UIScreen.brightness`). A change lasts until the device
    /// locks or the app puts it back.
    var brightness: Double {
        get { Double(screen?.brightness ?? 1) }
        set { screen?.brightness = CGFloat(newValue) }
    }

    /// Whether the idle timer is off (`UIApplication.isIdleTimerDisabled`).
    var isIdleTimerDisabled: Bool {
        get { UIApplication.shared.isIdleTimerDisabled }
        set { UIApplication.shared.isIdleTimerDisabled = newValue }
    }
}
