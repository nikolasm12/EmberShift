import SwiftUI

struct MenuBarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings

        VStack(spacing: 0) {
            header
                .padding(16)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                presetPicker

                VStack(spacing: 10) {
                    sliderRow(
                        title: "Strength",
                        value: $settings.intensity,
                        range: 0...0.98,
                        format: .percent
                    )
                    sliderRow(
                        title: "Dimming",
                        value: $settings.dimming,
                        range: 0...0.90,
                        format: .percent
                    )
                }

                scheduleCard
            }
            .padding(16)

            Divider()

            HStack {
                Button {
                    model.showSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.plain)

                Spacer()

                if let hotKeyError = model.globalHotKey.registrationError {
                    Image(systemName: "keyboard.badge.exclamationmark")
                        .foregroundStyle(.orange)
                        .help(hotKeyError)
                        .accessibilityLabel("Global shortcut unavailable")
                }

                Button("Quit RedLight") {
                    model.quit()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(12)
        }
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(model.scheduler.isFilterOn ? Color.red.gradient : Color.secondary.opacity(0.16).gradient)
                RedLightMenuLogo(isActive: model.scheduler.isFilterOn, size: 24)
                    .foregroundStyle(model.scheduler.isFilterOn ? .white : .secondary)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.scheduler.isFilterOn ? "RedLight is on" : "RedLight is off")
                    .font(.headline)
                Text(model.scheduler.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle(
                "Filter",
                isOn: Binding(
                    get: { model.scheduler.isFilterOn },
                    set: { model.setFilterEnabled($0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .accessibilityHint("Toggles the screen filter")
        }
    }

    private var presetPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Preset")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(
                "Preset",
                selection: Binding(
                    get: { model.settings.selectedPreset },
                    set: { model.selectPreset($0) }
                )
            ) {
                ForEach(FilterPreset.allCases) { preset in
                    Label(preset.title, systemImage: preset.symbolName)
                        .tag(preset)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .accessibilityLabel("Filter preset")
        }
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Menu {
                    ForEach(ScheduleMode.allCases) { mode in
                        Button(
                            model.settings.scheduleMode == mode
                                ? "✓ \(mode.title)"
                                : mode.title
                        ) {
                            model.setScheduleMode(mode)
                        }
                        .accessibilityLabel(mode.title)
                    }
                } label: {
                    Label(
                        model.settings.scheduleMode == .off ? "Manual control" : model.settings.scheduleMode.title,
                        systemImage: model.settings.scheduleMode == .sun ? "sunrise.fill" : "clock"
                    )
                    .font(.subheadline.weight(.medium))
                }
                .menuStyle(.borderlessButton)

                Spacer()
                if let transition = model.scheduler.nextTransition {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(
                            model.scheduler.hasTemporaryOverride
                                ? "Timer ends"
                                : (model.scheduler.isFilterOn ? "Turns off" : "Turns on")
                        )
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(transition, format: .dateTime.weekday(.abbreviated).hour().minute())
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if model.settings.scheduleMode == .sun, model.settings.storedCoordinate == nil {
                Button("Enable location for sun times") {
                    model.enableSolarSchedule()
                }
                .buttonStyle(.link)
                .font(.caption)
                if let error = model.locationManager.lastError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                    if model.locationManager.authorizationStatus == .denied
                        || model.locationManager.authorizationStatus == .restricted {
                        Button("Open Location Settings") {
                            model.openLocationSettings()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
            } else if model.settings.scheduleMode != .off {
                Text(
                    model.scheduler.hasTemporaryOverride
                        ? "Your temporary choice ends at the time shown."
                        : "A manual toggle lasts until the next scheduled change."
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Menu(model.scheduler.isFilterOn ? "Pause…" : "Turn On…") {
                    temporaryAction("For 15 Minutes", duration: 15 * 60)
                    temporaryAction("For 1 Hour", duration: 60 * 60)
                    temporaryAction("For 2 Hours", duration: 2 * 60 * 60)
                    if model.settings.scheduleMode != .off,
                       model.scheduler.nextTransition != nil {
                        Divider()
                        Button("Until Next Scheduled Change") {
                            model.scheduler.setTemporaryOverrideUntilNextChange(
                                enabled: !model.scheduler.isFilterOn
                            )
                        }
                    }
                }
                .menuStyle(.borderlessButton)

                if model.scheduler.hasTemporaryOverride {
                    Button(model.settings.scheduleMode == .off ? "End Timer" : "Return to Schedule") {
                        model.scheduler.clearOverride()
                    }
                    .buttonStyle(.link)
                }
            }
            .font(.caption)

            Divider()

            HStack {
                Text("Blue light estimate")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(model.settings.activeProfile.estimatedBlueTransmission, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if model.settings.rendererMode != .compatibility {
                HStack {
                    Text("Renderer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(model.rendererCoordinator.activeRenderer.title)
                        .font(.caption)
                        .foregroundStyle(
                            model.rendererCoordinator.fallbackReason == nil
                                ? Color.secondary
                                : Color.orange
                        )
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 9))
    }

    private func temporaryAction(_ title: String, duration: TimeInterval) -> some View {
        Button(title) {
            model.scheduler.setTemporaryOverride(
                enabled: !model.scheduler.isFilterOn,
                duration: duration
            )
        }
    }

    private enum SliderFormat {
        case percent
    }

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: SliderFormat
    ) -> some View {
        HStack {
            Text(title)
                .frame(width: 54, alignment: .leading)
            Slider(value: value, in: range)
                .accessibilityLabel(title)
                .accessibilityValue(Text(value.wrappedValue, format: .percent.precision(.fractionLength(0))))
            Text(value.wrappedValue, format: .percent.precision(.fractionLength(0)))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
        .font(.caption)
    }
}
