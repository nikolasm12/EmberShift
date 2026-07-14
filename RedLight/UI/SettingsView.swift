import Carbon.HIToolbox
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            appearance
                .tabItem { Label("Appearance", systemImage: "paintpalette") }

            schedule
                .tabItem { Label("Schedule", systemImage: "clock") }

            shortcuts
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }

            rendering
                .tabItem { Label("Rendering", systemImage: "display") }

            general
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .padding(20)
        .frame(width: 620, height: 500)
    }

    private var appearance: some View {
        @Bindable var settings = model.settings

        return Form {
            Section("Filter profile") {
                Picker(
                    "Preset",
                    selection: Binding(
                        get: { settings.selectedPreset },
                        set: { model.selectPreset($0) }
                    )
                ) {
                    ForEach(FilterPreset.allCases) { preset in
                        VStack(alignment: .leading) {
                            Text(preset.title)
                            Text(preset.subtitle)
                        }
                        .tag(preset)
                    }
                }
                .accessibilityLabel("Filter preset")

                Text(settings.selectedPreset.subtitle)
                    .foregroundStyle(.secondary)
                Text("Selecting a preset restores its strength and dimming defaults.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Tint preview") {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.black)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(settings.activeProfile.tintColor).opacity(settings.intensity))
                        }
                        .frame(width: 92, height: 28)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.separator, lineWidth: 1)
                        }
                        Text(settings.activeProfile.estimatedBlueTransmission, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Estimated blue remaining")
                    }
                }

                if settings.selectedPreset == .custom {
                    colorSlider("Red", value: $settings.customRed, color: .red)
                    colorSlider("Green", value: $settings.customGreen, color: .green)
                    colorSlider("Blue", value: $settings.customBlue, color: .blue)
                }
            }

            Section("Fine tuning") {
                LabeledContent("Strength") {
                    HStack {
                        Slider(value: $settings.intensity, in: 0...0.98)
                            .accessibilityLabel("Filter strength")
                        Text(settings.intensity, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .frame(width: 44)
                    }
                    .frame(width: 280)
                }

                LabeledContent("Screen dimming") {
                    HStack {
                        Slider(value: $settings.dimming, in: 0...0.90)
                            .accessibilityLabel("Screen dimming")
                        Text(settings.dimming, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .frame(width: 44)
                    }
                    .frame(width: 280)
                }

                LabeledContent("Transition") {
                    HStack {
                        Slider(value: $settings.transitionDuration, in: 0...5, step: 0.25)
                            .accessibilityLabel("Transition duration")
                        Text("\(settings.transitionDuration, format: .number.precision(.fractionLength(1))) s")
                            .monospacedDigit()
                            .frame(width: 44)
                    }
                    .frame(width: 280)
                }

                LabeledContent("Estimated blue remaining") {
                    Text(settings.activeProfile.estimatedBlueTransmission, format: .percent.precision(.fractionLength(1)))
                        .monospacedDigit()
                }
            }

            Section {
                Text("The estimate describes digital RGB suppression, not a measurement of your panel’s emitted spectrum.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var schedule: some View {
        @Bindable var settings = model.settings
        @Bindable var location = model.locationManager

        return Form {
            Section("Automatic filtering") {
                Picker(
                    "Mode",
                    selection: Binding(
                        get: { settings.scheduleMode },
                        set: { mode in
                            model.setScheduleMode(mode)
                        }
                    )
                ) {
                    ForEach(ScheduleMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            if settings.scheduleMode == .manual {
                Section("Custom times") {
                    DatePicker(
                        "Turn on",
                        selection: timeBinding(for: $settings.manualStartMinutes),
                        displayedComponents: .hourAndMinute
                    )
                    .accessibilityLabel("Turn on time")
                    DatePicker(
                        "Turn off",
                        selection: timeBinding(for: $settings.manualEndMinutes),
                        displayedComponents: .hourAndMinute
                    )
                    .accessibilityLabel("Turn off time")
                    Text("Schedules that cross midnight are handled automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if settings.scheduleMode == .sun {
                Section("Sun times") {
                    LabeledContent("Location") {
                        HStack {
                            Text(location.statusText)
                                .foregroundStyle(.secondary)
                            Button(location.isLocating ? "Locating…" : "Update") {
                                location.requestLocationAccess()
                            }
                            .disabled(location.isLocating)
                        }
                    }

                    if let coordinate = settings.storedCoordinate {
                        LabeledContent("Saved locally") {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(coordinate.latitude, format: .number.precision(.fractionLength(2))), \(coordinate.longitude, format: .number.precision(.fractionLength(2)))")
                                Text("Updated \(coordinate.timestamp, format: .relative(presentation: .named))")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }

                        let preview = solarPreview(settings: settings, coordinate: coordinate)
                        if let onTime = preview.onTime, let offTime = preview.offTime {
                            LabeledContent("Turns on today") {
                                Text(onTime, format: .dateTime.hour().minute())
                            }
                            LabeledContent("Turns off today") {
                                Text(offTime, format: .dateTime.hour().minute())
                            }
                        } else if let status = preview.status {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Toggle("Use civil twilight instead of the sun horizon", isOn: $settings.useCivilTwilight)
                    Stepper(
                        "Evening offset: \(settings.sunsetOffsetMinutes) min",
                        value: $settings.sunsetOffsetMinutes,
                        in: -120...120,
                        step: 5
                    )
                    Stepper(
                        "Morning offset: \(settings.sunriseOffsetMinutes) min",
                        value: $settings.sunriseOffsetMinutes,
                        in: -120...120,
                        step: 5
                    )

                    if let error = location.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                        if location.authorizationStatus == .denied || location.authorizationStatus == .restricted {
                            Button("Open Location Settings") {
                                model.openLocationSettings()
                            }
                        }
                    }
                    Text("Your coarse coordinates never leave this Mac. Sun times are calculated offline.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Current status") {
                LabeledContent("Filter", value: model.scheduler.statusText)
                if let next = model.scheduler.nextTransition {
                    LabeledContent(model.scheduler.hasTemporaryOverride ? "Timer ends" : "Next change") {
                        Text(next, format: .dateTime.weekday().hour().minute())
                    }
                }
                if model.scheduler.hasTemporaryOverride {
                    Button(settings.scheduleMode == .off ? "End Timer" : "Return to Schedule") {
                        model.scheduler.clearOverride()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var shortcuts: some View {
        Form {
            Section("Global toggle") {
                LabeledContent("Current shortcut") {
                    Text(HotKeyDisplay.string(
                        keyCode: model.settings.hotKeyCode,
                        modifiers: model.settings.hotKeyModifiers
                    ))
                    .font(.title3.monospaced())
                }

                HotKeyRecorderView { keyCode, modifiers in
                    model.updateHotKey(keyCode: keyCode, modifiers: modifiers)
                } onRecordingChanged: { isRecording in
                    model.setHotKeyRecordingActive(isRecording)
                }
                Button("Restore Default Shortcut") {
                    model.updateHotKey(keyCode: 15, modifiers: 2304)
                }

                if let error = model.globalHotKey.registrationError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                } else if model.globalHotKey.isRegistered {
                    Label("Shortcut active", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }

                Text("The shortcut works globally without Accessibility or Input Monitoring access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var rendering: some View {
        @Bindable var settings = model.settings

        return Form {
            Section("Display renderer") {
                Picker(
                    "Mode",
                    selection: Binding(
                        get: { settings.rendererMode },
                        set: { model.setRendererMode($0) }
                    )
                ) {
                    ForEach(FilterRendererMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Text(settings.rendererMode.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Currently using") {
                    Text(model.rendererCoordinator.activeRenderer.title)
                }
                if let fallback = model.rendererCoordinator.fallbackReason {
                    Text(fallback)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("High Clarity") {
                LabeledContent("Screen Recording") {
                    Label(
                        model.screenCapturePermission.status.title,
                        systemImage: model.screenCapturePermission.isGranted
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(
                        model.screenCapturePermission.isGranted
                            ? Color.green
                            : Color.orange
                    )
                }

                if !model.screenCapturePermission.isGranted {
                    Button("Grant Screen Recording Access") {
                        model.requestScreenCapturePermission()
                    }
                    Button("Open Screen Recording Settings") {
                        model.openScreenCaptureSettings()
                    }
                }

                Picker("Frame rate", selection: $settings.highClarityFrameRate) {
                    Text("60 fps").tag(60)
                    Text("120 fps").tag(120)
                }
                .pickerStyle(.segmented)
                .disabled(settings.rendererMode == .compatibility)

                Text("High Clarity captures each display locally, excludes RedLight to prevent feedback, and converts luminance to red with Metal. It never uploads or stores frames.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("Experimental limitations: protected video may appear black, HDR can differ from SDR, and capture adds a small amount of latency. RedLight falls back to the compatibility overlay if capture stops.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var general: some View {
        @Bindable var settings = model.settings

        return Form {
            Section("Startup") {
                Toggle(
                    "Launch RedLight at login",
                    isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) }
                    )
                )
                .accessibilityLabel("Launch RedLight at login")
                if let error = model.loginItemError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            Section("Privacy and permissions") {
                LabeledContent("Screen access", value: "Not required")
                LabeledContent("Accessibility access", value: "Not required")
                LabeledContent("Network access", value: "Not used")
                LabeledContent("Location", value: "Optional, on-device only")
            }

            Section("About") {
                LabeledContent("Version", value: appVersion)
                Button("Show Welcome Guide") {
                    model.showOnboarding()
                }
                Text("RedLight uses public macOS APIs and a click-through color overlay. It does not alter display calibration or use private Night Shift controls.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func colorSlider(_ title: String, value: Binding<Double>, color: Color) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: 0...1)
                    .tint(color)
                    .accessibilityLabel(title)
                Text(value.wrappedValue, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .frame(width: 44)
            }
            .frame(width: 280)
        }
    }

    private func timeBinding(for minutes: Binding<Int>) -> Binding<Date> {
        Binding {
            let start = Calendar.current.startOfDay(for: Date())
            return Calendar.current.date(byAdding: .minute, value: minutes.wrappedValue, to: start) ?? start
        } set: { date in
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            minutes.wrappedValue = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        }
    }

    private struct SolarPreview {
        let onTime: Date?
        let offTime: Date?
        let status: String?
    }

    private func solarPreview(
        settings: AppSettings,
        coordinate: StoredCoordinate,
        date: Date = Date()
    ) -> SolarPreview {
        let events = SolarCalculator.events(
            for: date,
            coordinate: coordinate,
            timeZone: .current
        )
        let condition = settings.useCivilTwilight ? events.civilCondition : events.condition
        switch condition {
        case .polarDay:
            return SolarPreview(
                onTime: nil,
                offTime: nil,
                status: settings.useCivilTwilight ? "No civil darkness today." : "The sun does not set today."
            )
        case .polarNight:
            return SolarPreview(
                onTime: nil,
                offTime: nil,
                status: settings.useCivilTwilight ? "Civil darkness continues today." : "The sun does not rise today."
            )
        case .normal:
            let evening = settings.useCivilTwilight ? events.civilDusk : events.sunset
            let morning = settings.useCivilTwilight ? events.civilDawn : events.sunrise
            return SolarPreview(
                onTime: evening?.addingTimeInterval(Double(settings.sunsetOffsetMinutes * 60)),
                offTime: morning?.addingTimeInterval(Double(settings.sunriseOffsetMinutes * 60)),
                status: nil
            )
        }
    }
}

private struct HotKeyRecorderView: View {
    let onRecord: (UInt32, UInt32) -> Void
    let onRecordingChanged: (Bool) -> Void
    @StateObject private var recorder = HotKeyRecorderController()

    var body: some View {
        HStack {
            Button(recorder.isRecording ? "Press a shortcut…" : "Record New Shortcut") {
                recorder.toggle(
                    onRecord: onRecord,
                    onRecordingChanged: onRecordingChanged
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(recorder.isRecording ? .red : .accentColor)

            if recorder.isRecording {
                Text("Include ⌃ or ⌘. Esc cancels.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear {
            recorder.stop()
        }
    }
}

@MainActor
private final class HotKeyRecorderController: ObservableObject {
    @Published private(set) var isRecording = false
    private var eventMonitor: Any?
    private var onRecord: ((UInt32, UInt32) -> Void)?
    private var onRecordingChanged: ((Bool) -> Void)?

    func toggle(
        onRecord: @escaping (UInt32, UInt32) -> Void,
        onRecordingChanged: @escaping (Bool) -> Void
    ) {
        if isRecording {
            stop()
        } else {
            self.onRecord = onRecord
            self.onRecordingChanged = onRecordingChanged
            isRecording = true
            onRecordingChanged(true)
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                MainActor.assumeIsolated {
                    self?.handle(event)
                }
                return nil
            }
        }
    }

    func stop() {
        let wasRecording = isRecording
        let recordingChanged = onRecordingChanged
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        isRecording = false
        onRecord = nil
        onRecordingChanged = nil
        if wasRecording {
            recordingChanged?(false)
        }
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 53 {
            stop()
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbonModifiers: UInt32 = 0
        if flags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if flags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }

        guard flags.contains(.command) || flags.contains(.control) else {
            NSSound.beep()
            return
        }
        let callback = onRecord
        stop()
        callback?(UInt32(event.keyCode), carbonModifiers)
    }
}
