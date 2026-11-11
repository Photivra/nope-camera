import AVFoundation
import NopeCapture
import NopeCore
import Testing

struct CameraPermissionMappingTests {
    @Test(arguments: [
        (AVAuthorizationStatus.notDetermined, CameraPermission.notDetermined),
        (.authorized, .authorized),
        (.denied, .denied),
        (.restricted, .restricted),
    ])
    func mapsKnownStatuses(status: AVAuthorizationStatus, expected: CameraPermission) {
        #expect(CameraPermission(status) == expected)
    }

    @Test func unknownFutureStatusIsRestricted() throws {
        // Imported C enums accept any raw value, which stands in for a status added by a later iOS.
        let future = try #require(AVAuthorizationStatus(rawValue: 99))
        #expect(CameraPermission(future) == .restricted)
    }
}
