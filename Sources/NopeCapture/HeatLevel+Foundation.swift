import Foundation
import NopeCore

extension HeatLevel {
    /// Converts the system thermal state.
    ///
    /// A state added in a later iOS becomes `HeatLevel.serious`: high enough to be noted, but it
    /// doesn't stop the camera on a value nope. can't interpret.
    ///
    /// - Parameter state: `ProcessInfo.processInfo.thermalState`.
    public init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .serious
        }
    }
}
