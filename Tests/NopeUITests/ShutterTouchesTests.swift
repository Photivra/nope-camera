import NopeCore
import Testing

@testable import NopeUI

/// The shutter reports each touch's end exactly once: when it comes up, or when the shutter goes
/// away or stops reporting first (issues #100 and #101).
struct ShutterTouchesTests {
    @Test func aTouchEndsOnce() {
        var touches = ShutterTouches()
        #expect(touches.end(.released) == nil, "no touch is down")
        let press = touches.press(number: 3)
        #expect(press.0 == .pressed && press.1 == 3)
        #expect(touches.reported == 3)
        let end = touches.end(.cancelled)
        #expect(end?.0 == .cancelled && end?.1 == 3, "the shutter went away with the finger down")
        #expect(touches.end(.released) == nil, "the finger coming up later reports nothing more")
        #expect(touches.reported == nil)
    }

    @Test func aReleaseCarriesItsPressNumber() {
        var touches = ShutterTouches()
        _ = touches.press(number: 1)
        #expect(touches.end(.released)?.1 == 1)
        _ = touches.press(number: 2)
        #expect(touches.end(.released)?.1 == 2)
    }
}
