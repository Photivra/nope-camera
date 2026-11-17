import CoreGraphics
import Testing

@testable import NopeUI

/// The upright unit's measured size settles instead of following sub-point changes, which made a
/// sideways layout measure and move without end.
@MainActor
struct UprightUnitTests {
    @Test func theFirstMeasurementIsTakenRoundedUp() {
        #expect(UprightUnit.settledSize(.zero, measured: CGSize(width: 121, height: 58.33)) == CGSize(width: 121, height: 59))
    }

    @Test func theAlternatingMeasurementsSettle() {
        // The measurements seen alternating on a sideways iPhone at the largest text size.
        let measurements = [
            CGSize(width: 121.33, height: 58.33), CGSize(width: 121.33, height: 58.67),
            CGSize(width: 121, height: 58.67), CGSize(width: 121, height: 58.33),
        ]
        var size = CGSize.zero
        var sizes: [CGSize] = []
        for _ in 0..<3 {
            for measured in measurements {
                size = UprightUnit.settledSize(size, measured: measured)
                sizes.append(size)
            }
        }
        // It grows to the largest rounded size once and then stays.
        #expect(sizes.last == CGSize(width: 122, height: 59))
        #expect(Set(sizes.suffix(8).map { "\($0)" }).count == 1)
    }

    @Test func aRealChangeIsTaken() {
        let current = CGSize(width: 121, height: 58)
        #expect(UprightUnit.settledSize(current, measured: CGSize(width: 140, height: 58)) == CGSize(width: 140, height: 58))
        #expect(UprightUnit.settledSize(current, measured: CGSize(width: 121, height: 50)) == CGSize(width: 121, height: 50))
    }

    @Test func aSmallShrinkIsIgnored() {
        let current = CGSize(width: 122, height: 59)
        #expect(UprightUnit.settledSize(current, measured: CGSize(width: 121, height: 58.33)) == current)
    }
}
