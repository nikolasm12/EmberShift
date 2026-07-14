import AppKit

enum FilterPreset: String, CaseIterable, Identifiable, Codable {
    case warm
    case twilight
    case textClarity
    case deepRed
    case redRoom
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .warm: "Warm"
        case .twilight: "Twilight"
        case .textClarity: "Text Clarity"
        case .deepRed: "Deep Red"
        case .redRoom: "Red Room"
        case .custom: "Custom"
        }
    }

    var subtitle: String {
        switch self {
        case .warm: "Gentle, all-day warmth"
        case .twilight: "Balanced evening comfort"
        case .textClarity: "Darker red with stronger text contrast"
        case .deepRed: "Strong blue suppression"
        case .redRoom: "Maximum practical suppression"
        case .custom: "Your own color balance"
        }
    }

    var symbolName: String {
        switch self {
        case .warm: "sun.horizon.fill"
        case .twilight: "moon.haze.fill"
        case .textClarity: "textformat"
        case .deepRed: "moon.fill"
        case .redRoom: "eye.fill"
        case .custom: "slider.horizontal.3"
        }
    }

    var profile: FilterProfile {
        switch self {
        case .warm:
            FilterProfile(red: 0.55, green: 0.18, blue: 0.04, intensity: 0.30, dimming: 0.02)
        case .twilight:
            FilterProfile(red: 0.46, green: 0.06, blue: 0.01, intensity: 0.52, dimming: 0.08)
        case .textClarity:
            FilterProfile(red: 0.30, green: 0.0, blue: 0.0, intensity: 0.68, dimming: 0.02)
        case .deepRed:
            FilterProfile(red: 0.38, green: 0.0, blue: 0.0, intensity: 0.70, dimming: 0.10)
        case .redRoom:
            FilterProfile(red: 0.38, green: 0.0, blue: 0.0, intensity: 0.85, dimming: 0.20)
        case .custom:
            FilterProfile(red: 0.46, green: 0.05, blue: 0.01, intensity: 0.60, dimming: 0.10)
        }
    }
}

struct FilterProfile: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var intensity: Double
    var dimming: Double

    init(red: Double, green: Double, blue: Double, intensity: Double, dimming: Double) {
        self.red = red.clamped(to: 0...1)
        self.green = green.clamped(to: 0...1)
        self.blue = blue.clamped(to: 0...1)
        self.intensity = intensity.clamped(to: 0...0.98)
        self.dimming = dimming.clamped(to: 0...0.90)
    }

    var tintColor: NSColor {
        NSColor(
            colorSpace: .extendedSRGB,
            components: [CGFloat(red), CGFloat(green), CGFloat(blue), 1],
            count: 4
        )
    }

    /// Approximate fraction of the original blue channel that remains after
    /// source-over tinting and dimming. It excludes panel spectral leakage.
    var estimatedBlueTransmission: Double {
        ((1 - intensity) + intensity * blue) * (1 - dimming)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
