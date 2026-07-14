import XCTest
@testable import RedLight

final class SolarCalculatorTests: XCTestCase {
    func testNewYorkSummerSunTimesAreWithinReferenceTolerance() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let date = try makeDate(2026, 7, 13, 12, 0, timeZone: zone)
        let coordinate = StoredCoordinate(latitude: 40.713, longitude: -74.006, timestamp: date)

        let events = SolarCalculator.events(for: date, coordinate: coordinate, timeZone: zone)
        let sunrise = try XCTUnwrap(events.sunrise)
        let sunset = try XCTUnwrap(events.sunset)
        let expectedSunrise = try makeDate(2026, 7, 13, 5, 37, timeZone: zone)
        let expectedSunset = try makeDate(2026, 7, 13, 20, 26, timeZone: zone)

        XCTAssertEqual(events.condition, .normal)
        XCTAssertEqual(sunrise.timeIntervalSince(expectedSunrise), 0, accuracy: 12 * 60)
        XCTAssertEqual(sunset.timeIntervalSince(expectedSunset), 0, accuracy: 12 * 60)
        XCTAssertLessThan(try XCTUnwrap(events.civilDawn), sunrise)
        XCTAssertGreaterThan(try XCTUnwrap(events.civilDusk), sunset)
    }

    func testSolarEventsStayOnRequestedLocalDayAcrossDateLine() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Australia/Sydney"))
        let date = try makeDate(2026, 1, 15, 12, 0, timeZone: zone)
        let coordinate = StoredCoordinate(latitude: -33.869, longitude: 151.209, timestamp: date)
        let events = SolarCalculator.events(for: date, coordinate: coordinate, timeZone: zone)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone

        for event in [events.sunrise, events.sunset, events.civilDawn, events.civilDusk].compactMap({ $0 }) {
            XCTAssertEqual(
                calendar.dateComponents([.year, .month, .day], from: event),
                calendar.dateComponents([.year, .month, .day], from: date)
            )
        }
    }

    func testTromsoPolarDayAndNight() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))
        let coordinate = StoredCoordinate(latitude: 69.649, longitude: 18.956, timestamp: Date())
        let summer = try makeDate(2026, 6, 21, 12, 0, timeZone: zone)
        let winter = try makeDate(2026, 12, 21, 12, 0, timeZone: zone)

        XCTAssertEqual(SolarCalculator.events(for: summer, coordinate: coordinate, timeZone: zone).condition, .polarDay)
        XCTAssertEqual(SolarCalculator.events(for: winter, coordinate: coordinate, timeZone: zone).condition, .polarNight)
    }

    func testCivilTwilightCanRemainAllNightWhereSunStillSets() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Europe/Helsinki"))
        let date = try makeDate(2026, 6, 21, 12, 0, timeZone: zone)
        let coordinate = StoredCoordinate(latitude: 65.012, longitude: 25.465, timestamp: date)
        let events = SolarCalculator.events(for: date, coordinate: coordinate, timeZone: zone)

        XCTAssertEqual(events.condition, .normal)
        XCTAssertEqual(events.civilCondition, .polarDay)
        XCTAssertNil(events.civilDawn)
        XCTAssertNil(events.civilDusk)
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
