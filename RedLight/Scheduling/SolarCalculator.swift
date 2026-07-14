import Foundation

enum SolarCondition: Equatable, Sendable {
    case normal
    case polarDay
    case polarNight
}

struct SolarEvents: Equatable, Sendable {
    let sunrise: Date?
    let sunset: Date?
    let civilDawn: Date?
    let civilDusk: Date?
    let condition: SolarCondition
    let civilCondition: SolarCondition
}

enum SolarCalculator {
    private static let officialZenith = 90.833
    private static let civilZenith = 96.0

    static func events(
        for date: Date,
        coordinate: StoredCoordinate,
        timeZone: TimeZone = .current
    ) -> SolarEvents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = calendar.ordinality(of: .day, in: .year, for: date) ?? 1

        let sunriseResult = eventUTC(
            dayOfYear: day,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            zenith: officialZenith,
            isSunrise: true
        )
        let sunsetResult = eventUTC(
            dayOfYear: day,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            zenith: officialZenith,
            isSunrise: false
        )
        let civilDawnResult = eventUTC(
            dayOfYear: day,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            zenith: civilZenith,
            isSunrise: true
        )
        let civilDuskResult = eventUTC(
            dayOfYear: day,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            zenith: civilZenith,
            isSunrise: false
        )

        return SolarEvents(
            sunrise: eventDate(from: sunriseResult, localDayContaining: date, timeZone: timeZone),
            sunset: eventDate(from: sunsetResult, localDayContaining: date, timeZone: timeZone),
            civilDawn: eventDate(from: civilDawnResult, localDayContaining: date, timeZone: timeZone),
            civilDusk: eventDate(from: civilDuskResult, localDayContaining: date, timeZone: timeZone),
            condition: condition(from: sunriseResult, and: sunsetResult),
            civilCondition: condition(from: civilDawnResult, and: civilDuskResult)
        )
    }

    private enum EventResult {
        case hour(Double)
        case neverRises
        case neverSets
    }

    private static func condition(from morning: EventResult, and evening: EventResult) -> SolarCondition {
        switch (morning, evening) {
        case (.neverSets, _), (_, .neverSets): .polarDay
        case (.neverRises, _), (_, .neverRises): .polarNight
        default: .normal
        }
    }

    private static func eventUTC(
        dayOfYear: Int,
        latitude: Double,
        longitude: Double,
        zenith: Double,
        isSunrise: Bool
    ) -> EventResult {
        let longitudeHour = longitude / 15
        let approximateTime = Double(dayOfYear) + ((isSunrise ? 6 : 18) - longitudeHour) / 24
        let meanAnomaly = (0.9856 * approximateTime) - 3.289
        var trueLongitude = meanAnomaly
            + (1.916 * sinDegrees(meanAnomaly))
            + (0.020 * sinDegrees(2 * meanAnomaly))
            + 282.634
        trueLongitude = normalizedDegrees(trueLongitude)

        var rightAscension = radiansToDegrees(atan(0.91764 * tan(degreesToRadians(trueLongitude))))
        rightAscension = normalizedDegrees(rightAscension)
        let longitudeQuadrant = floor(trueLongitude / 90) * 90
        let ascensionQuadrant = floor(rightAscension / 90) * 90
        rightAscension = (rightAscension + longitudeQuadrant - ascensionQuadrant) / 15

        let sinDeclination = 0.39782 * sinDegrees(trueLongitude)
        let cosDeclination = cos(asin(sinDeclination))
        let latitudeRadians = degreesToRadians(latitude)
        let cosLocalHour = (
            cosDegrees(zenith) - sinDeclination * sin(latitudeRadians)
        ) / (cosDeclination * cos(latitudeRadians))

        if cosLocalHour > 1 { return .neverRises }
        if cosLocalHour < -1 { return .neverSets }

        let localHour: Double
        if isSunrise {
            localHour = (360 - radiansToDegrees(acos(cosLocalHour))) / 15
        } else {
            localHour = radiansToDegrees(acos(cosLocalHour)) / 15
        }

        let localMeanTime = localHour + rightAscension - (0.06571 * approximateTime) - 6.622
        return .hour(normalizedHours(localMeanTime - longitudeHour))
    }

    private static func eventDate(
        from result: EventResult,
        localDayContaining targetDate: Date,
        timeZone: TimeZone
    ) -> Date? {
        guard case let .hour(utcHour) = result else { return nil }

        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = timeZone
        let targetComponents = localCalendar.dateComponents([.year, .month, .day], from: targetDate)

        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let utcMidnight = utcCalendar.date(from: targetComponents) else { return nil }
        var candidate = utcMidnight.addingTimeInterval(utcHour * 3600)

        for _ in 0..<2 {
            let candidateComponents = localCalendar.dateComponents([.year, .month, .day], from: candidate)
            if candidateComponents == targetComponents { break }
            if let candidateDay = localCalendar.date(from: candidateComponents),
               let targetDay = localCalendar.date(from: targetComponents) {
                candidate = candidate.addingTimeInterval(candidateDay < targetDay ? 86_400 : -86_400)
            }
        }
        return candidate
    }

    private static func normalizedDegrees(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }

    private static func normalizedHours(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: 24)
        return remainder >= 0 ? remainder : remainder + 24
    }

    private static func degreesToRadians(_ value: Double) -> Double { value * .pi / 180 }
    private static func radiansToDegrees(_ value: Double) -> Double { value * 180 / .pi }
    private static func sinDegrees(_ value: Double) -> Double { sin(degreesToRadians(value)) }
    private static func cosDegrees(_ value: Double) -> Double { cos(degreesToRadians(value)) }
}
