import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    let onComplete: () -> Void
    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case 0: welcome
                case 1: choosePreset
                default: automation
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(36)

            Divider()

            HStack {
                if page > 0 {
                    Button("Back") {
                        withAnimation { page -= 1 }
                    }
                } else {
                    Button("Skip") {
                        onComplete()
                    }
                }
                Spacer()
                HStack(spacing: 7) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(index == page ? Color.accentColor : Color.secondary.opacity(0.25))
                            .frame(width: 7, height: 7)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step \(page + 1) of 3")
                Spacer()
                Button(page == 2 ? "Start Using RedLight" : "Continue") {
                    if page == 2 {
                        onComplete()
                    } else {
                        withAnimation { page += 1 }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(minWidth: 620, minHeight: 500)
    }

    private var welcome: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.orange, .red, .black.opacity(0.9)],
                            center: .topLeading,
                            startRadius: 8,
                            endRadius: 70
                        )
                    )
                Image(systemName: "sun.horizon.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 112, height: 112)
            .shadow(color: .red.opacity(0.3), radius: 22)

            VStack(spacing: 8) {
                Text("Welcome to RedLight")
                    .font(.largeTitle.bold())
                Text("Comfortable color, exactly when you want it.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 24) {
                feature("Instant", symbol: "switch.2", detail: "Toggle from the menu bar")
                feature("Automatic", symbol: "sunset.fill", detail: "Follow local sun times")
                feature("Private", symbol: "hand.raised.fill", detail: "No screen or network access")
            }
        }
    }

    private var choosePreset: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Choose your starting color")
                    .font(.title.bold())
                Text("You can fine-tune strength and dimming at any time.")
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(FilterPreset.allCases.filter { $0 != .custom }) { preset in
                    Button {
                        model.selectPreset(preset)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: preset.symbolName)
                                .font(.title2)
                                .foregroundStyle(preset == .warm ? .orange : .red)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.title)
                                    .font(.headline)
                                Text(preset.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.settings.selectedPreset == preset {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .padding(14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(
                        model.settings.selectedPreset == preset ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(model.settings.selectedPreset == preset ? Color.accentColor : .clear, lineWidth: 1)
                    }
                }
            }

            Text("Red Room offers the strongest practical digital suppression. It intentionally changes contrast and color accuracy.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Choosing a preset does not turn the filter on. Use the menu-bar switch whenever you’re ready.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var automation: some View {
        @Bindable var settings = model.settings

        return VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Make it effortless")
                    .font(.title.bold())
                Text("These options can be changed later in Settings.")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                Toggle(isOn: Binding(
                    get: { settings.scheduleMode == .sun },
                    set: { enabled in
                        if enabled {
                            model.enableSolarSchedule()
                        } else {
                            model.setScheduleMode(.off)
                        }
                    }
                )) {
                    settingLabel(
                        "Follow sunset and sunrise",
                        symbol: "sunrise.fill",
                        detail: "Uses a coarse location and calculates sun times entirely offline."
                    )
                }
                .accessibilityLabel("Follow sunset and sunrise")
                .padding(16)

                Divider().padding(.leading, 58)

                Toggle(isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                )) {
                    settingLabel(
                        "Launch at login",
                        symbol: "power",
                        detail: "Keeps your schedule and global shortcut ready."
                    )
                }
                .accessibilityLabel("Launch RedLight at login")
                .padding(16)
            }
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))

            HStack(spacing: 12) {
                Image(systemName: "keyboard")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Global toggle")
                        .font(.headline)
                    Text(HotKeyDisplay.string(
                        keyCode: settings.hotKeyCode,
                        modifiers: settings.hotKeyModifiers
                    ))
                    .font(.title3.monospaced())
                }
                Spacer()
                Text("No Accessibility permission")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))

            if let error = model.locationManager.lastError ?? model.loginItemError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func feature(_ title: String, symbol: String, detail: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 145)
    }

    private func settingLabel(_ title: String, symbol: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
