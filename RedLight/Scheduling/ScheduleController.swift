import AppKit
import Foundation
import Observation

struct ScheduleEvaluation: Equatable {
    let shouldEnable: Bool
    let nextTransition: Date?
    let explanation: String
}

@MainActor
@Observable
final class ScheduleController: NSObject {
    private(set) var isFilterOn = false
    private(set) var nextTransition: Date?
    private(set) var statusText = "Off"
    private(set) var hasTemporaryOverride = false

    @ObservationIgnored var onStateChange: ((Bool) -> Void)?
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let nowProvider: () -> Date
    @ObservationIgnored private let timeZoneProvider: () -> TimeZone
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var temporaryOverride: TemporaryOverride?

    private struct TemporaryOverride {
        let enabled: Bool
        let expiresAt: Date
    }

    init(
        settings: AppSettings,
        now: @escaping () -> Date = Date.init,
        timeZone: @escaping () -> TimeZone = { .current }
    ) {
        self.settings = settings
        nowProvider = now
        timeZoneProvider = timeZone
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemTimeChanged),
            name: .NSSystemClockDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemTimeChanged),
            name: .NSSystemTimeZoneDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemTimeChanged),
            name: .NSCalendarDayChanged,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemTimeChanged),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    func start() {
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func toggle() {
        let now = nowProvider()
        if settings.scheduleMode == .off {
            temporaryOverride = nil
            settings.isFilterEnabled = !isFilterOn
            refresh()
            return
        }

        let base = evaluation(at: now)
        let expiry = base.nextTransition
            ?? Calendar.current.date(byAdding: .day, value: 1, to: now)
            ?? now.addingTimeInterval(86_400)
        temporaryOverride = TemporaryOverride(enabled: !isFilterOn, expiresAt: expiry)
        refresh()
    }

    func setTemporaryOverride(enabled: Bool, duration: TimeInterval) {
        guard duration > 0 else { return }
        temporaryOverride = TemporaryOverride(
            enabled: enabled,
            expiresAt: nowProvider().addingTimeInterval(duration)
        )
        refresh()
    }

    func setTemporaryOverrideUntilNextChange(enabled: Bool) {
        let now = nowProvider()
        let base = evaluation(at: now)
        let expiry = base.nextTransition
            ?? Calendar.current.date(byAdding: .day, value: 1, to: now)
            ?? now.addingTimeInterval(86_400)
        temporaryOverride = TemporaryOverride(enabled: enabled, expiresAt: expiry)
        refresh()
    }

    func clearOverride(reevaluate: Bool = true) {
        temporaryOverride = nil
        if reevaluate {
            refresh()
        }
    }

    func refresh() {
        let now = nowProvider()
        let base = evaluation(at: now)
        let previousState = isFilterOn
        if let override = temporaryOverride, override.expiresAt <= now {
            temporaryOverride = nil
        }

        if let override = temporaryOverride {
            isFilterOn = override.enabled
            nextTransition = override.expiresAt
            statusText = override.enabled ? "On temporarily" : "Paused temporarily"
            hasTemporaryOverride = true
        } else {
            isFilterOn = base.shouldEnable
            nextTransition = base.nextTransition
            statusText = base.explanation
            hasTemporaryOverride = false
        }

        scheduleTimer(from: now)
        if previousState != isFilterOn {
            onStateChange?(isFilterOn)
        }
    }

    func evaluation(at date: Date) -> ScheduleEvaluation {
        switch settings.scheduleMode {
        case .off:
            return ScheduleEvaluation(
                shouldEnable: settings.isFilterEnabled,
                nextTransition: nil,
                explanation: settings.isFilterEnabled ? "On manually" : "Off"
            )
        case .manual:
            return manualEvaluation(at: date)
        case .sun:
            return solarEvaluation(at: date)
        }
    }

    @objc private func systemTimeChanged() {
        refresh()
    }

    @objc private func timerFired() {
        refresh()
    }

    private func manualEvaluation(at date: Date) -> ScheduleEvaluation {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZoneProvider()
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let start = settings.manualStartMinutes
        let end = settings.manualEndMinutes

        if start == end {
            let next = calendar.date(byAdding: .day, value: 1, to: dateFor(minutes: end, on: date, calendar: calendar))
            return ScheduleEvaluation(shouldEnable: true, nextTransition: next, explanation: "On all day")
        }

        let active: Bool
        let next: Date?
        if start < end {
            active = minute >= start && minute < end
            if active {
                next = dateFor(minutes: end, on: date, calendar: calendar)
            } else if minute < start {
                next = dateFor(minutes: start, on: date, calendar: calendar)
            } else {
                next = calendar.date(byAdding: .day, value: 1, to: dateFor(minutes: start, on: date, calendar: calendar))
            }
        } else {
            active = minute >= start || minute < end
            if active, minute < end {
                next = dateFor(minutes: end, on: date, calendar: calendar)
            } else if active {
                next = calendar.date(byAdding: .day, value: 1, to: dateFor(minutes: end, on: date, calendar: calendar))
            } else {
                next = dateFor(minutes: start, on: date, calendar: calendar)
            }
        }

        return ScheduleEvaluation(
            shouldEnable: active,
            nextTransition: next,
            explanation: active ? "On by schedule" : "Waiting for schedule"
        )
    }

    private func solarEvaluation(at date: Date) -> ScheduleEvaluation {
        guard let coordinate = settings.storedCoordinate else {
            return ScheduleEvaluation(
                shouldEnable: settings.isFilterEnabled,
                nextTransition: nil,
                explanation: "Location needed"
            )
        }

        let timeZone = timeZoneProvider()
        let events = SolarCalculator.events(for: date, coordinate: coordinate, timeZone: timeZone)
        let selectedCondition = settings.useCivilTwilight ? events.civilCondition : events.condition
        switch selectedCondition {
        case .polarDay:
            let explanation = settings.useCivilTwilight ? "No civil darkness" : "Polar daylight"
            return ScheduleEvaluation(shouldEnable: false, nextTransition: nextMidnight(after: date, timeZone: timeZone), explanation: explanation)
        case .polarNight:
            let explanation = settings.useCivilTwilight ? "Civil darkness" : "Polar night"
            return ScheduleEvaluation(shouldEnable: true, nextTransition: nextMidnight(after: date, timeZone: timeZone), explanation: explanation)
        case .normal:
            break
        }

        let morningBase = settings.useCivilTwilight ? events.civilDawn : events.sunrise
        let eveningBase = settings.useCivilTwilight ? events.civilDusk : events.sunset
        guard let morningBase, let eveningBase else {
            return ScheduleEvaluation(
                shouldEnable: settings.isFilterEnabled,
                nextTransition: nextMidnight(after: date, timeZone: timeZone),
                explanation: "Sun times unavailable"
            )
        }

        let morning = morningBase.addingTimeInterval(Double(settings.sunriseOffsetMinutes * 60))
        let evening = eveningBase.addingTimeInterval(Double(settings.sunsetOffsetMinutes * 60))
        if date < morning {
            return ScheduleEvaluation(shouldEnable: true, nextTransition: morning, explanation: "On until sunrise")
        }
        if date < evening {
            return ScheduleEvaluation(shouldEnable: false, nextTransition: evening, explanation: "Waiting for sunset")
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
        let tomorrowEvents = SolarCalculator.events(for: tomorrow, coordinate: coordinate, timeZone: timeZone)
        let tomorrowMorning = (settings.useCivilTwilight ? tomorrowEvents.civilDawn : tomorrowEvents.sunrise)?
            .addingTimeInterval(Double(settings.sunriseOffsetMinutes * 60))
        return ScheduleEvaluation(shouldEnable: true, nextTransition: tomorrowMorning, explanation: "On until sunrise")
    }

    private func scheduleTimer(from now: Date) {
        timer?.invalidate()
        timer = nil
        guard let nextTransition else { return }
        let interval = max(1, nextTransition.timeIntervalSince(now) + 0.25)
        let timer = Timer(
            timeInterval: interval,
            target: self,
            selector: #selector(timerFired),
            userInfo: nil,
            repeats: false
        )
        timer.tolerance = min(30, max(0.5, interval * 0.01))
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func dateFor(minutes: Int, on date: Date, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = minutes / 60
        components.minute = minutes % 60
        components.second = 0
        if let result = calendar.date(from: components) {
            return result
        }

        let start = calendar.startOfDay(for: date)
        return calendar.nextDate(
            after: start,
            matching: DateComponents(hour: minutes / 60, minute: minutes % 60),
            matchingPolicy: .nextTime
        ) ?? start
    }

    private func nextMidnight(after date: Date, timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.nextDate(
            after: date,
            matching: DateComponents(hour: 0, minute: 0, second: 1),
            matchingPolicy: .nextTime
        )
    }
}
