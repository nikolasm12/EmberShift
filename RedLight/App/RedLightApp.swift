import AppKit
import Observation
import ServiceManagement
import SwiftUI

@main
struct RedLightApp: App {
    @NSApplicationDelegateAdaptor(RedLightAppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(model)
        } label: {
            Image(systemName: model.scheduler.isFilterOn ? "sun.horizon.fill" : "sun.horizon")
                .symbolRenderingMode(.monochrome)
                .accessibilityLabel(model.scheduler.isFilterOn ? "RedLight is on" : "RedLight is off")
        }
        .menuBarExtraStyle(.window)
    }
}

struct RedLightMenuLogo: View {
    let isActive: Bool
    var size: CGFloat = 18

    var body: some View {
        RedLightMarkShape()
            .fill(.primary)
            .frame(width: size, height: size)
            .opacity(isActive ? 1 : 0.55)
    }
}

private struct RedLightMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height

        path.addEllipse(in: CGRect(
            x: rect.minX + width * 0.27,
            y: rect.minY + height * 0.08,
            width: width * 0.46,
            height: height * 0.46
        ))

        path.move(to: CGPoint(x: rect.minX + width * 0.07, y: rect.minY + height * 0.82))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + width * 0.93, y: rect.minY + height * 0.82),
            control: CGPoint(x: rect.midX, y: rect.minY + height * 0.46)
        )
        path.addLine(to: CGPoint(x: rect.minX + width * 0.90, y: rect.minY + height * 0.94))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + width * 0.10, y: rect.minY + height * 0.94),
            control: CGPoint(x: rect.midX, y: rect.minY + height * 0.68)
        )
        path.closeSubpath()
        return path
    }
}

@MainActor
final class RedLightAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppModel.shared.start()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppModel.shared.refreshScreenCapturePermission()
    }
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let settings: AppSettings
    let overlayController: ScreenOverlayController
    let highClarityRenderer: HighClarityRenderer
    let screenCapturePermission: ScreenCapturePermission
    let rendererCoordinator: FilterRendererCoordinator
    let locationManager: LocationManager
    let scheduler: ScheduleController
    let globalHotKey: GlobalHotKey

    private(set) var loginItemError: String?
    private var started = false
    private var onboardingWindow: NSWindow?
    private var onboardingWindowDelegate: ManagedWindowDelegate?
    private var settingsWindow: NSWindow?
    private var settingsWindowDelegate: ManagedWindowDelegate?
    private var registeredHotKey: (code: UInt32, modifiers: UInt32)?
    private var lastAttemptedHotKey: (code: UInt32, modifiers: UInt32)?
    private var lastAppearanceSignature: AppearanceSignature?
    private var lastScheduleSignature: ScheduleSignature?
    private var lastRendererSignature: RendererSignature?
    private var isBatchingSettings = false

    init(defaults: UserDefaults = .standard) {
        let settings = AppSettings(defaults: defaults)
        let overlayController = ScreenOverlayController()
        let highClarityRenderer = HighClarityRenderer()
        let screenCapturePermission = ScreenCapturePermission()
        self.settings = settings
        self.overlayController = overlayController
        self.highClarityRenderer = highClarityRenderer
        self.screenCapturePermission = screenCapturePermission
        rendererCoordinator = FilterRendererCoordinator(
            overlay: overlayController,
            highClarity: highClarityRenderer,
            permission: screenCapturePermission
        )
        locationManager = LocationManager()
        scheduler = ScheduleController(settings: settings)
        globalHotKey = GlobalHotKey()
        lastAppearanceSignature = AppearanceSignature(settings)
        lastScheduleSignature = ScheduleSignature(settings)
        lastRendererSignature = RendererSignature(settings)

        settings.onChange = { [weak self] in
            self?.settingsDidChange()
        }
        locationManager.onLocationChange = { [weak self] coordinate in
            self?.settings.storedCoordinate = coordinate
        }
        scheduler.onStateChange = { [weak self] enabled in
            guard let self else { return }
            self.rendererCoordinator.apply(
                enabled: enabled,
                profile: self.settings.activeProfile,
                transitionDuration: self.settings.transitionDuration,
                mode: self.settings.rendererMode,
                frameRate: self.settings.highClarityFrameRate
            )
        }
        globalHotKey.onPressed = { [weak self] in
            self?.scheduler.toggle()
        }
    }

    func start() {
        guard !started else { return }
        started = true
        screenCapturePermission.refresh()
        rendererCoordinator.start()
        registerHotKeyIfNeeded()
        scheduler.start()
        rendererCoordinator.apply(
            enabled: scheduler.isFilterOn,
            profile: settings.activeProfile,
            transitionDuration: settings.transitionDuration,
            mode: settings.rendererMode,
            frameRate: settings.highClarityFrameRate,
            animated: false
        )
        let isInstalledInApplications = Bundle.main.bundleURL.path.contains("/Applications/")
        if isInstalledInApplications, !settings.hasConfiguredAutomaticLaunch {
            settings.hasConfiguredAutomaticLaunch = true
            setLaunchAtLogin(true)
        } else {
            synchronizeLoginItemStatus()
        }
        if settings.scheduleMode == .sun {
            locationManager.requestLocationAccess()
        }

        if !settings.hasCompletedOnboarding {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                self?.showOnboarding()
            }
        }
    }

    func toggleFilter() {
        scheduler.toggle()
    }

    func setFilterEnabled(_ enabled: Bool) {
        guard scheduler.isFilterOn != enabled else { return }
        scheduler.toggle()
    }

    func selectPreset(_ preset: FilterPreset) {
        settings.selectPreset(preset)
    }

    func enableSolarSchedule() {
        setScheduleMode(.sun)
    }

    func setScheduleMode(_ mode: ScheduleMode) {
        guard settings.scheduleMode != mode else {
            if mode == .sun {
                locationManager.requestLocationAccess()
            }
            return
        }

        let effectiveState = scheduler.isFilterOn
        isBatchingSettings = true
        scheduler.clearOverride(reevaluate: false)
        if mode == .off {
            settings.isFilterEnabled = effectiveState
        }
        settings.scheduleMode = mode
        isBatchingSettings = false
        settingsDidChange()
        if mode == .sun {
            locationManager.requestLocationAccess()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            settings.launchAtLogin = enabled
            loginItemError = nil
        } catch {
            settings.launchAtLogin = SMAppService.mainApp.status == .enabled
            loginItemError = "macOS couldn’t update the login item. Check System Settings › General › Login Items."
        }
    }

    func openLocationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func setRendererMode(_ mode: FilterRendererMode) {
        if mode == .highClarity, !screenCapturePermission.isGranted {
            screenCapturePermission.request()
        }
        settings.rendererMode = mode
    }

    func requestScreenCapturePermission() {
        screenCapturePermission.request()
        rendererCoordinator.refreshPermissionAndRenderer(
            frameRate: settings.highClarityFrameRate
        )
    }

    func openScreenCaptureSettings() {
        screenCapturePermission.openSystemSettings()
    }

    func refreshScreenCapturePermission() {
        screenCapturePermission.refresh()
        guard started else { return }
        rendererCoordinator.refreshPermissionAndRenderer(
            frameRate: settings.highClarityFrameRate
        )
    }

    func updateHotKey(keyCode: UInt32, modifiers: UInt32) {
        settings.hotKeyCode = keyCode
        settings.hotKeyModifiers = modifiers
        registerHotKeyIfNeeded(force: true)
    }

    func setHotKeyRecordingActive(_ active: Bool) {
        if active {
            globalHotKey.stop()
            registeredHotKey = nil
        } else {
            registerHotKeyIfNeeded(force: true)
        }
    }

    func showOnboarding() {
        if let onboardingWindow {
            onboardingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = OnboardingView { [weak self] in
            self?.completeOnboarding()
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 500),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to RedLight"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(
            rawValue: NSWindow.Level.statusBar.rawValue + 1
        )
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        window.contentViewController = NSHostingController(rootView: view.environment(self))
        let delegate = ManagedWindowDelegate { [weak self] in
            self?.settings.hasCompletedOnboarding = true
            self?.onboardingWindow = nil
            self?.onboardingWindowDelegate = nil
        }
        window.delegate = delegate
        onboardingWindowDelegate = delegate
        window.center()
        window.makeKeyAndOrderFront(nil)
        onboardingWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 500),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "RedLight Settings"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(
            rawValue: NSWindow.Level.statusBar.rawValue + 1
        )
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        window.contentViewController = NSHostingController(
            rootView: SettingsView().environment(self)
        )
        let delegate = ManagedWindowDelegate { [weak self] in
            self?.settingsWindow = nil
            self?.settingsWindowDelegate = nil
        }
        window.delegate = delegate
        settingsWindowDelegate = delegate
        settingsWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func completeOnboarding() {
        settings.hasCompletedOnboarding = true
        onboardingWindow?.close()
        onboardingWindow = nil
    }

    func quit() {
        rendererCoordinator.stop()
        scheduler.stop()
        globalHotKey.stop()
        NSApp.terminate(nil)
    }

    private func settingsDidChange() {
        guard !isBatchingSettings else { return }

        let appearanceSignature = AppearanceSignature(settings)
        if appearanceSignature != lastAppearanceSignature {
            lastAppearanceSignature = appearanceSignature
            rendererCoordinator.updateProfile(
                settings.activeProfile,
                transitionDuration: settings.transitionDuration
            )
        }

        let scheduleSignature = ScheduleSignature(settings)
        if scheduleSignature != lastScheduleSignature {
            lastScheduleSignature = scheduleSignature
            scheduler.refresh()
        }

        let rendererSignature = RendererSignature(settings)
        if rendererSignature != lastRendererSignature {
            lastRendererSignature = rendererSignature
            rendererCoordinator.apply(
                enabled: scheduler.isFilterOn,
                profile: settings.activeProfile,
                transitionDuration: settings.transitionDuration,
                mode: settings.rendererMode,
                frameRate: settings.highClarityFrameRate
            )
        }

        registerHotKeyIfNeeded()
    }

    private func registerHotKeyIfNeeded(force: Bool = false) {
        let desired = (settings.hotKeyCode, settings.hotKeyModifiers)
        guard force || lastAttemptedHotKey?.code != desired.0 || lastAttemptedHotKey?.modifiers != desired.1 else {
            return
        }
        lastAttemptedHotKey = desired
        globalHotKey.register(keyCode: desired.0, modifiers: desired.1)
        registeredHotKey = globalHotKey.isRegistered ? desired : nil
    }

    private func synchronizeLoginItemStatus() {
        let actual = SMAppService.mainApp.status == .enabled
        if settings.launchAtLogin != actual {
            settings.launchAtLogin = actual
        }
    }

    private struct AppearanceSignature: Equatable {
        let preset: FilterPreset
        let intensity: Double
        let dimming: Double
        let red: Double
        let green: Double
        let blue: Double
        let transitionDuration: Double

        @MainActor
        init(_ settings: AppSettings) {
            preset = settings.selectedPreset
            intensity = settings.intensity
            dimming = settings.dimming
            red = settings.customRed
            green = settings.customGreen
            blue = settings.customBlue
            transitionDuration = settings.transitionDuration
        }
    }

    private struct ScheduleSignature: Equatable {
        let isFilterEnabled: Bool
        let mode: ScheduleMode
        let manualStart: Int
        let manualEnd: Int
        let usesCivilTwilight: Bool
        let sunsetOffset: Int
        let sunriseOffset: Int
        let coordinate: StoredCoordinate?

        @MainActor
        init(_ settings: AppSettings) {
            isFilterEnabled = settings.isFilterEnabled
            mode = settings.scheduleMode
            manualStart = settings.manualStartMinutes
            manualEnd = settings.manualEndMinutes
            usesCivilTwilight = settings.useCivilTwilight
            sunsetOffset = settings.sunsetOffsetMinutes
            sunriseOffset = settings.sunriseOffsetMinutes
            coordinate = settings.storedCoordinate
        }
    }

    private struct RendererSignature: Equatable {
        let mode: FilterRendererMode
        let frameRate: Int

        @MainActor
        init(_ settings: AppSettings) {
            mode = settings.rendererMode
            frameRate = settings.highClarityFrameRate
        }
    }
}

@MainActor
private final class ManagedWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
