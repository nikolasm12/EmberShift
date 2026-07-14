import XCTest
@testable import RedLight

@MainActor
final class ScheduleControllerTests: XCTestCase {
    func testOvernightManualSchedule() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let settings = makeSettings()
        settings.scheduleMode = .manual
        settings.manualStartMinutes = 20 * 60
        settings.manualEndMinutes = 7 * 60
        let controller = ScheduleController(settings: settings, timeZone: { zone })

        let late = try makeDate(2026, 7, 13, 22, 0, timeZone: zone)
        let midday = try makeDate(2026, 7, 13, 12, 0, timeZone: zone)

        XCTAssertTrue(controller.evaluation(at: late).shouldEnable)
        XCTAssertFalse(controller.evaluation(at: midday).shouldEnable)
        XCTAssertEqual(
            controller.evaluation(at: midday).nextTransition,
            try makeDate(2026, 7, 13, 20, 0, timeZone: zone)
        )
    }

    func testDaytimeManualSchedule() throws {
        let zone = TimeZone(secondsFromGMT: 0)!
        let settings = makeSettings()
        settings.scheduleMode = .manual
        settings.manualStartMinutes = 8 * 60
        settings.manualEndMinutes = 17 * 60
        let controller = ScheduleController(settings: settings, timeZone: { zone })

        XCTAssertTrue(controller.evaluation(at: try makeDate(2026, 7, 13, 9, 0, timeZone: zone)).shouldEnable)
        XCTAssertFalse(controller.evaluation(at: try makeDate(2026, 7, 13, 19, 0, timeZone: zone)).shouldEnable)
    }

    func testSunScheduleIsOnBeforeSunriseAndAfterSunset() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let settings = makeSettings()
        settings.scheduleMode = .sun
        settings.storedCoordinate = StoredCoordinate(
            latitude: 40.713,
            longitude: -74.006,
            timestamp: Date()
        )
        let controller = ScheduleController(settings: settings, timeZone: { zone })

        XCTAssertTrue(controller.evaluation(at: try makeDate(2026, 7, 13, 3, 0, timeZone: zone)).shouldEnable)
        XCTAssertFalse(controller.evaluation(at: try makeDate(2026, 7, 13, 12, 0, timeZone: zone)).shouldEnable)
        XCTAssertTrue(controller.evaluation(at: try makeDate(2026, 7, 13, 23, 0, timeZone: zone)).shouldEnable)
    }

    func testManualScheduleUsesCalendarAcrossDSTChange() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let settings = makeSettings()
        settings.scheduleMode = .manual
        settings.manualStartMinutes = 1 * 60 + 30
        settings.manualEndMinutes = 3 * 60 + 30
        let controller = ScheduleController(settings: settings, timeZone: { zone })
        let afterSpringForward = try makeDate(2026, 3, 8, 3, 5, timeZone: zone)
        let expectedEnd = try makeDate(2026, 3, 8, 3, 30, timeZone: zone)

        let evaluation = controller.evaluation(at: afterSpringForward)
        XCTAssertTrue(evaluation.shouldEnable)
        XCTAssertEqual(evaluation.nextTransition, expectedEnd)
    }

    func testScheduledToggleOverridesUntilBoundary() throws {
        let zone = TimeZone(secondsFromGMT: 0)!
        var now = try makeDate(2026, 7, 13, 12, 0, timeZone: zone)
        let settings = makeSettings()
        settings.scheduleMode = .manual
        settings.manualStartMinutes = 20 * 60
        settings.manualEndMinutes = 7 * 60
        let controller = ScheduleController(settings: settings, now: { now }, timeZone: { zone })

        controller.start()
        XCTAssertFalse(controller.isFilterOn)
        controller.toggle()
        XCTAssertTrue(controller.isFilterOn)
        XCTAssertEqual(controller.statusText, "On temporarily")

        now = try makeDate(2026, 7, 13, 20, 1, timeZone: zone)
        controller.refresh()
        XCTAssertTrue(controller.isFilterOn)
        XCTAssertEqual(controller.statusText, "On by schedule")
        controller.stop()
    }

    func testTimedPauseRestoresBaseStateAtExpiry() throws {
        let zone = TimeZone(secondsFromGMT: 0)!
        var now = try makeDate(2026, 7, 13, 12, 0, timeZone: zone)
        let settings = makeSettings()
        settings.scheduleMode = .off
        settings.isFilterEnabled = true
        let controller = ScheduleController(settings: settings, now: { now }, timeZone: { zone })

        controller.start()
        controller.setTemporaryOverride(enabled: false, duration: 15 * 60)
        XCTAssertFalse(controller.isFilterOn)
        XCTAssertTrue(controller.hasTemporaryOverride)

        now = now.addingTimeInterval(15 * 60 + 1)
        controller.refresh()
        XCTAssertTrue(controller.isFilterOn)
        XCTAssertFalse(controller.hasTemporaryOverride)
        controller.stop()
    }

    func testManualToggleEndsTimedOverride() {
        let settings = makeSettings()
        settings.scheduleMode = .off
        settings.isFilterEnabled = true
        let controller = ScheduleController(settings: settings)

        controller.start()
        controller.setTemporaryOverride(enabled: false, duration: 60 * 60)
        XCTAssertFalse(controller.isFilterOn)
        controller.toggle()
        XCTAssertTrue(controller.isFilterOn)
        XCTAssertFalse(controller.hasTemporaryOverride)
        controller.stop()
    }

    func testUnchangedRefreshDoesNotReemitFilterState() {
        let settings = makeSettings()
        settings.scheduleMode = .off
        settings.isFilterEnabled = false
        let controller = ScheduleController(settings: settings)
        var emittedStates: [Bool] = []
        controller.onStateChange = { emittedStates.append($0) }

        controller.start()
        controller.refresh()
        XCTAssertTrue(emittedStates.isEmpty)

        settings.isFilterEnabled = true
        controller.refresh()
        controller.refresh()
        XCTAssertEqual(emittedStates, [true])
        controller.stop()
    }

    func testMissingLocationUsesManualStateAndExplainsProblem() {
        let settings = makeSettings()
        settings.scheduleMode = .sun
        settings.isFilterEnabled = true
        settings.storedCoordinate = nil
        let controller = ScheduleController(settings: settings)

        let evaluation = controller.evaluation(at: Date())
        XCTAssertTrue(evaluation.shouldEnable)
        XCTAssertEqual(evaluation.explanation, "Location needed")
        XCTAssertNil(evaluation.nextTransition)
    }

    private func makeSettings() -> AppSettings {
        let suiteName = "ScheduleControllerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AppSettings(defaults: defaults)
    }

    private func makeDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        timeZone: TimeZone
    ) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return try XCTUnwrap(calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )))
    }
}
