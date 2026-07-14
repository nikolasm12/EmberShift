import XCTest
@testable import RedLight

@MainActor
final class RendererCoordinatorTests: XCTestCase {
    func testCompatibilityModeUsesOnlyOverlay() {
        let harness = makeHarness(permissionGranted: false)

        harness.coordinator.start()
        harness.coordinator.apply(
            enabled: true,
            profile: .test,
            transitionDuration: 0,
            mode: .compatibility,
            frameRate: 60
        )

        XCTAssertTrue(harness.overlay.isEnabled)
        XCTAssertFalse(harness.highClarity.isEnabled)
        XCTAssertEqual(harness.coordinator.activeRenderer, .compatibility)
        XCTAssertNil(harness.coordinator.fallbackReason)
    }

    func testDeniedHighClarityFallsBackImmediately() {
        let harness = makeHarness(permissionGranted: false)

        harness.coordinator.apply(
            enabled: true,
            profile: .test,
            transitionDuration: 0,
            mode: .highClarity,
            frameRate: 60
        )

        XCTAssertTrue(harness.overlay.isEnabled)
        XCTAssertFalse(harness.highClarity.isEnabled)
        XCTAssertNotNil(harness.coordinator.fallbackReason)
    }

    func testHighClarityKeepsOverlayUntilReady() {
        let harness = makeHarness(permissionGranted: true)

        harness.coordinator.apply(
            enabled: true,
            profile: .test,
            transitionDuration: 0,
            mode: .highClarity,
            frameRate: 120
        )

        XCTAssertTrue(harness.overlay.isEnabled)
        XCTAssertTrue(harness.highClarity.isEnabled)
        XCTAssertEqual(harness.highClarity.targetFrameRate, 120)
        XCTAssertEqual(harness.coordinator.activeRenderer, .compatibility)

        harness.highClarity.onReady?()

        XCTAssertFalse(harness.overlay.isEnabled)
        XCTAssertTrue(harness.highClarity.isEnabled)
        XCTAssertEqual(harness.coordinator.activeRenderer, .highClarity)
        XCTAssertNil(harness.coordinator.fallbackReason)
    }

    func testStreamFailureRestoresOverlay() {
        let harness = makeHarness(permissionGranted: true)
        harness.coordinator.apply(
            enabled: true,
            profile: .test,
            transitionDuration: 0,
            mode: .highClarity,
            frameRate: 60
        )
        harness.highClarity.onReady?()

        harness.highClarity.onFailure?("stream stopped")

        XCTAssertTrue(harness.overlay.isEnabled)
        XCTAssertFalse(harness.highClarity.isEnabled)
        XCTAssertEqual(harness.coordinator.activeRenderer, .compatibility)
        XCTAssertEqual(harness.coordinator.fallbackReason, "stream stopped")
    }

    func testDisablingStopsBothRenderers() {
        let harness = makeHarness(permissionGranted: true)
        harness.coordinator.apply(
            enabled: true,
            profile: .test,
            transitionDuration: 0,
            mode: .highClarity,
            frameRate: 60
        )
        harness.coordinator.apply(
            enabled: false,
            profile: .test,
            transitionDuration: 0,
            mode: .highClarity,
            frameRate: 60
        )

        XCTAssertFalse(harness.overlay.isEnabled)
        XCTAssertFalse(harness.highClarity.isEnabled)
    }

    private func makeHarness(permissionGranted: Bool) -> Harness {
        let overlay = FakeRenderer()
        let highClarity = FakeHighClarityRenderer()
        let permission = FakeScreenCapturePermission(isGranted: permissionGranted)
        return Harness(
            coordinator: FilterRendererCoordinator(
                overlay: overlay,
                highClarity: highClarity,
                permission: permission
            ),
            overlay: overlay,
            highClarity: highClarity
        )
    }

    private struct Harness {
        let coordinator: FilterRendererCoordinator
        let overlay: FakeRenderer
        let highClarity: FakeHighClarityRenderer
    }
}

@MainActor
private class FakeRenderer: DisplayFilterRenderer {
    private(set) var isEnabled = false
    private(set) var profile = FilterProfile.test

    func start() {}

    func setEnabled(
        _ enabled: Bool,
        profile: FilterProfile,
        transitionDuration: Double,
        animated: Bool
    ) {
        isEnabled = enabled
        self.profile = profile
    }

    func updateProfile(_ profile: FilterProfile, transitionDuration: Double) {
        self.profile = profile
    }

    func stop() {
        isEnabled = false
    }
}

@MainActor
private final class FakeHighClarityRenderer: FakeRenderer, HighClarityRendererProtocol {
    var onReady: (() -> Void)?
    var onFailure: ((String) -> Void)?
    var targetFrameRate = 60
}

@MainActor
private final class FakeScreenCapturePermission: ScreenCapturePermissionProviding {
    var isGranted: Bool

    init(isGranted: Bool) {
        self.isGranted = isGranted
    }
}

private extension FilterProfile {
    static let test = FilterProfile(
        red: 0.3,
        green: 0,
        blue: 0,
        intensity: 0.7,
        dimming: 0
    )
}
