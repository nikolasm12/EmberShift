import XCTest
@testable import RedLight

final class RedLuminanceMathTests: XCTestCase {
    func testBlackRemainsBlackAndBlueGreenAreAlwaysZero() {
        let output = RedLuminanceMath.transform(
            red: 0,
            green: 0,
            blue: 0,
            strength: 1,
            dimming: 0
        )

        XCTAssertEqual(output, SIMD3(0, 0, 0))
    }

    func testWhiteBecomesRedOnly() {
        let output = RedLuminanceMath.transform(
            red: 1,
            green: 1,
            blue: 1,
            strength: 1,
            dimming: 0
        )

        XCTAssertGreaterThan(output.x, 0.9)
        XCTAssertEqual(output.y, 0)
        XCTAssertEqual(output.z, 0)
    }

    func testPerceivedGreenIsBrighterThanBlue() {
        let green = RedLuminanceMath.transform(
            red: 0,
            green: 1,
            blue: 0,
            strength: 0.7,
            dimming: 0
        )
        let blue = RedLuminanceMath.transform(
            red: 0,
            green: 0,
            blue: 1,
            strength: 0.7,
            dimming: 0
        )

        XCTAssertGreaterThan(green.x, blue.x)
    }

    func testStrengthAndDimmingRemainClampedAndMonotonic() {
        let dim = RedLuminanceMath.transform(
            red: 1,
            green: 1,
            blue: 1,
            strength: -4,
            dimming: 0.5
        )
        let bright = RedLuminanceMath.transform(
            red: 1,
            green: 1,
            blue: 1,
            strength: 4,
            dimming: 0
        )

        XCTAssertGreaterThan(bright.x, dim.x)
        XCTAssertLessThanOrEqual(bright.x, 1)
        XCTAssertEqual(bright.y, 0)
        XCTAssertEqual(bright.z, 0)
    }

    func testSRGBRoundTrip() {
        for value in stride(from: 0.0, through: 1.0, by: 0.05) {
            let roundTrip = RedLuminanceMath.linearToSRGB(
                RedLuminanceMath.srgbToLinear(value)
            )
            XCTAssertEqual(roundTrip, value, accuracy: 0.000_001)
        }
    }
}
