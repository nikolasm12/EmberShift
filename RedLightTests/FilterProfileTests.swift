import AppKit
import XCTest
@testable import RedLight

final class FilterProfileTests: XCTestCase {
    func testPresetsIncreaseBlueSuppression() {
        let warm = FilterPreset.warm.profile.estimatedBlueTransmission
        let twilight = FilterPreset.twilight.profile.estimatedBlueTransmission
        let textClarity = FilterPreset.textClarity.profile.estimatedBlueTransmission
        let deepRed = FilterPreset.deepRed.profile.estimatedBlueTransmission
        let redRoom = FilterPreset.redRoom.profile.estimatedBlueTransmission

        XCTAssertGreaterThan(warm, twilight)
        XCTAssertGreaterThan(twilight, textClarity)
        XCTAssertGreaterThan(textClarity, deepRed)
        XCTAssertGreaterThan(deepRed, redRoom)
        XCTAssertLessThan(redRoom, 0.15)
    }

    func testProfileValuesAreClampedToSafeRanges() {
        let profile = FilterProfile(
            red: 2,
            green: -1,
            blue: 4,
            intensity: 3,
            dimming: -2
        )

        XCTAssertEqual(profile.red, 1)
        XCTAssertEqual(profile.green, 0)
        XCTAssertEqual(profile.blue, 1)
        XCTAssertEqual(profile.intensity, 0.98)
        XCTAssertEqual(profile.dimming, 0)
    }
}

@MainActor
final class ScreenOverlayControllerTests: XCTestCase {
    func testPanelsCoverEveryScreenWithoutInterceptingInput() {
        let controller = ScreenOverlayController()
        let transparentProfile = FilterProfile(red: 1, green: 0, blue: 0, intensity: 0, dimming: 0)

        controller.start()
        XCTAssertEqual(controller.panelCount, NSScreen.screens.count)
        XCTAssertTrue(controller.allPanelsIgnoreMouseEvents)
        XCTAssertTrue(controller.allPanelsAvoidKeyStatus)
        for screen in NSScreen.screens {
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            let displayID = number.map { CGDirectDisplayID($0.uint32Value) }
            XCTAssertEqual(
                displayID.flatMap { controller.panelFramesByDisplay[$0] },
                screen.frame,
                "Overlay must exactly match display \(String(describing: displayID)) in global AppKit coordinates"
            )
        }

        controller.setEnabled(false, profile: transparentProfile, transitionDuration: 0, animated: false)
        XCTAssertEqual(controller.visiblePanelCount, 0)

        controller.setEnabled(true, profile: transparentProfile, transitionDuration: 0, animated: false)
        XCTAssertEqual(controller.visiblePanelCount, NSScreen.screens.count)
        controller.setEnabled(true, profile: FilterPreset.deepRed.profile, transitionDuration: 2, animated: true)
        XCTAssertTrue(controller.panelAlphaValues.allSatisfy { $0 == 1 })
        controller.stop()
    }
}
