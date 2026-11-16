import NopeCore
import SwiftUI
import Testing

@testable import NopeUI

/// The appearance rule (owner decision for 0.3.0, "Follow light/dark"): the camera is always
/// dark, other screens follow the system, and night mode is dark everywhere.
struct ScreenAppearanceTests {
    @Test func theCameraIsDarkInEitherSystemSetting() {
        for system in [ColorScheme.light, .dark, nil] {
            #expect(ScreenAppearance.camera.colorScheme(isNightMode: false, system: system) == .dark)
        }
    }

    @Test func otherScreensFollowTheSystemSetting() {
        #expect(ScreenAppearance.system.colorScheme(isNightMode: false, system: .light) == .light)
        #expect(ScreenAppearance.system.colorScheme(isNightMode: false, system: .dark) == .dark)
        // Not known: no preference, so a window follows the system by itself.
        #expect(ScreenAppearance.system.colorScheme(isNightMode: false, system: nil) == nil)
    }

    @Test func nightModeIsDarkEverywhere() {
        for appearance in [ScreenAppearance.camera, .system] {
            for system in [ColorScheme.light, .dark, nil] {
                #expect(appearance.colorScheme(isNightMode: true, system: system) == .dark)
            }
        }
    }

    @Test func firstRunAndTheAccessScreensFollowTheSystemAndTheCameraIsDark() {
        #expect(ScreenAppearance.of(.needsPermission) == .system)
        #expect(ScreenAppearance.of(.permissionDenied) == .system)
        #expect(ScreenAppearance.of(.unavailable) == .system)
        #expect(ScreenAppearance.of(.starting) == .camera)
        #expect(ScreenAppearance.of(.ready(DeviceCapabilities(lenses: []))) == .camera)
    }
}
