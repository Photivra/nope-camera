#if DEBUG
// Debug-only: fixed storage and battery values for the UI tests, which can't change the
// Simulator's free storage or battery. Compiled only in the Debug configuration.

import Foundation
import NopeCore

/// Chooses fixed storage and battery values from the launch arguments
/// (`-NopeSimulatedDeviceStatus <state>`), so the UI tests can show each warning (issue #44).
enum SimulatedDeviceStatus: String {
    /// The launch argument: `-NopeSimulatedDeviceStatus`.
    static let argument = "-NopeSimulatedDeviceStatus"

    /// Room for about 15 more photos of the `noRAW` scenario's camera (HEIF at 12 MP), and 5 of
    /// RAW and HEIF.
    case lowStorage
    /// Room for no more photos.
    case fullStorage
    /// 15% battery, unplugged.
    case lowBattery
    /// 15% battery, unplugged, with Low Power Mode on.
    case lowBatteryLowPower

    /// The state in the launch arguments, or `nil` without one.
    static var current: SimulatedDeviceStatus? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: argument), index + 1 < arguments.count else { return nil }
        return SimulatedDeviceStatus(rawValue: arguments[index + 1])
    }

    /// The reader for the state in the launch arguments, or `nil` without one.
    @MainActor static func reader() -> (any DeviceStatusReading)? {
        current.map(Reader.init(status:))
    }

    /// Returns the state's fixed values.
    @MainActor struct Reader: DeviceStatusReading {
        /// The state.
        let status: SimulatedDeviceStatus

        /// The free bytes: plenty unless storage is low or full.
        func availableStorageBytes() -> Int64? {
            switch status {
            case .lowStorage: 200_000_000
            case .fullStorage: 10_000_000
            case .lowBattery, .lowBatteryLowPower: 100_000_000_000
            }
        }

        /// The battery: full and plugged in unless it is low.
        func battery() -> BatteryReading? {
            switch status {
            case .lowStorage, .fullStorage: BatteryReading(level: 1, isCharging: true, isLowPowerMode: false)
            case .lowBattery: BatteryReading(level: 0.15, isCharging: false, isLowPowerMode: false)
            case .lowBatteryLowPower: BatteryReading(level: 0.15, isCharging: false, isLowPowerMode: true)
            }
        }
    }
}
#endif
