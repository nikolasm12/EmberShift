import Foundation
import Observation

enum ScheduleMode: String, CaseIterable, Identifiable, Codable {
    case off
    case manual
    case sun

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .manual: "Custom Times"
        case .sun: "Sunset to Sunrise"
        }
    }
}

struct StoredCoordinate: Equatable, Codable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
}

@MainActor
@Observable
final class AppSettings {
    var isFilterEnabled: Bool { didSet { save() } }
    var selectedPreset: FilterPreset { didSet { save() } }
    var intensity: Double { didSet { save() } }
    var dimming: Double { didSet { save() } }
    var customRed: Double { didSet { save() } }
    var customGreen: Double { didSet { save() } }
    var customBlue: Double { didSet { save() } }
    var transitionDuration: Double { didSet { save() } }
    var rendererMode: FilterRendererMode { didSet { save() } }
    var highClarityFrameRate: Int { didSet { save() } }

    var scheduleMode: ScheduleMode { didSet { save() } }
    var manualStartMinutes: Int { didSet { save() } }
    var manualEndMinutes: Int { didSet { save() } }
    var useCivilTwilight: Bool { didSet { save() } }
    var sunsetOffsetMinutes: Int { didSet { save() } }
    var sunriseOffsetMinutes: Int { didSet { save() } }

    var storedCoordinate: StoredCoordinate? { didSet { save() } }
    var launchAtLogin: Bool { didSet { save() } }
    var hasConfiguredAutomaticLaunch: Bool { didSet { save() } }
    var hotKeyCode: UInt32 { didSet { save() } }
    var hotKeyModifiers: UInt32 { didSet { save() } }
    var hasCompletedOnboarding: Bool { didSet { save() } }

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var isLoading = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isFilterEnabled = defaults.object(forKey: Keys.isFilterEnabled) as? Bool ?? false
        selectedPreset = FilterPreset(rawValue: defaults.string(forKey: Keys.selectedPreset) ?? "") ?? .twilight
        intensity = defaults.object(forKey: Keys.intensity) as? Double ?? FilterPreset.twilight.profile.intensity
        dimming = defaults.object(forKey: Keys.dimming) as? Double ?? FilterPreset.twilight.profile.dimming
        customRed = defaults.object(forKey: Keys.customRed) as? Double ?? 0.46
        customGreen = defaults.object(forKey: Keys.customGreen) as? Double ?? 0.05
        customBlue = defaults.object(forKey: Keys.customBlue) as? Double ?? 0.01
        transitionDuration = defaults.object(forKey: Keys.transitionDuration) as? Double ?? 1.5
        rendererMode = FilterRendererMode(
            rawValue: defaults.string(forKey: Keys.rendererMode) ?? ""
        ) ?? .compatibility
        highClarityFrameRate = defaults.object(forKey: Keys.highClarityFrameRate) as? Int ?? 60
        scheduleMode = ScheduleMode(rawValue: defaults.string(forKey: Keys.scheduleMode) ?? "") ?? .off
        manualStartMinutes = defaults.object(forKey: Keys.manualStartMinutes) as? Int ?? 20 * 60
        manualEndMinutes = defaults.object(forKey: Keys.manualEndMinutes) as? Int ?? 7 * 60
        useCivilTwilight = defaults.object(forKey: Keys.useCivilTwilight) as? Bool ?? false
        sunsetOffsetMinutes = defaults.object(forKey: Keys.sunsetOffsetMinutes) as? Int ?? 0
        sunriseOffsetMinutes = defaults.object(forKey: Keys.sunriseOffsetMinutes) as? Int ?? 0
        launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        hasConfiguredAutomaticLaunch = defaults.object(forKey: Keys.hasConfiguredAutomaticLaunch) as? Bool ?? false
        hotKeyCode = UInt32(defaults.object(forKey: Keys.hotKeyCode) as? Int ?? 15)
        hotKeyModifiers = UInt32(defaults.object(forKey: Keys.hotKeyModifiers) as? Int ?? 2304)
        hasCompletedOnboarding = defaults.object(forKey: Keys.hasCompletedOnboarding) as? Bool ?? false

        if let data = defaults.data(forKey: Keys.storedCoordinate) {
            storedCoordinate = try? JSONDecoder().decode(StoredCoordinate.self, from: data)
        } else {
            storedCoordinate = nil
        }
        isLoading = false
    }

    var activeProfile: FilterProfile {
        if selectedPreset == .custom {
            return FilterProfile(
                red: customRed,
                green: customGreen,
                blue: customBlue,
                intensity: intensity,
                dimming: dimming
            )
        }
        var profile = selectedPreset.profile
        profile.intensity = intensity
        profile.dimming = dimming
        return profile
    }

    func selectPreset(_ preset: FilterPreset) {
        selectedPreset = preset
        let profile = preset == .custom ? activeProfile : preset.profile
        intensity = profile.intensity
        dimming = profile.dimming
    }

    func reset() {
        let domain = Bundle.main.bundleIdentifier ?? "com.nick.RedLight"
        defaults.removePersistentDomain(forName: domain)
    }

    private func save() {
        guard !isLoading else { return }
        defaults.set(isFilterEnabled, forKey: Keys.isFilterEnabled)
        defaults.set(selectedPreset.rawValue, forKey: Keys.selectedPreset)
        defaults.set(intensity, forKey: Keys.intensity)
        defaults.set(dimming, forKey: Keys.dimming)
        defaults.set(customRed, forKey: Keys.customRed)
        defaults.set(customGreen, forKey: Keys.customGreen)
        defaults.set(customBlue, forKey: Keys.customBlue)
        defaults.set(transitionDuration, forKey: Keys.transitionDuration)
        defaults.set(rendererMode.rawValue, forKey: Keys.rendererMode)
        defaults.set(highClarityFrameRate, forKey: Keys.highClarityFrameRate)
        defaults.set(scheduleMode.rawValue, forKey: Keys.scheduleMode)
        defaults.set(manualStartMinutes, forKey: Keys.manualStartMinutes)
        defaults.set(manualEndMinutes, forKey: Keys.manualEndMinutes)
        defaults.set(useCivilTwilight, forKey: Keys.useCivilTwilight)
        defaults.set(sunsetOffsetMinutes, forKey: Keys.sunsetOffsetMinutes)
        defaults.set(sunriseOffsetMinutes, forKey: Keys.sunriseOffsetMinutes)
        defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
        defaults.set(hasConfiguredAutomaticLaunch, forKey: Keys.hasConfiguredAutomaticLaunch)
        defaults.set(Int(hotKeyCode), forKey: Keys.hotKeyCode)
        defaults.set(Int(hotKeyModifiers), forKey: Keys.hotKeyModifiers)
        defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
        if let storedCoordinate, let data = try? JSONEncoder().encode(storedCoordinate) {
            defaults.set(data, forKey: Keys.storedCoordinate)
        } else {
            defaults.removeObject(forKey: Keys.storedCoordinate)
        }
        onChange?()
    }

    private enum Keys {
        static let isFilterEnabled = "isFilterEnabled"
        static let selectedPreset = "selectedPreset"
        static let intensity = "intensity"
        static let dimming = "dimming"
        static let customRed = "customRed"
        static let customGreen = "customGreen"
        static let customBlue = "customBlue"
        static let transitionDuration = "transitionDuration"
        static let rendererMode = "rendererMode"
        static let highClarityFrameRate = "highClarityFrameRate"
        static let scheduleMode = "scheduleMode"
        static let manualStartMinutes = "manualStartMinutes"
        static let manualEndMinutes = "manualEndMinutes"
        static let useCivilTwilight = "useCivilTwilight"
        static let sunsetOffsetMinutes = "sunsetOffsetMinutes"
        static let sunriseOffsetMinutes = "sunriseOffsetMinutes"
        static let storedCoordinate = "storedCoordinate"
        static let launchAtLogin = "launchAtLogin"
        static let hasConfiguredAutomaticLaunch = "hasConfiguredAutomaticLaunch"
        static let hotKeyCode = "hotKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }
}
