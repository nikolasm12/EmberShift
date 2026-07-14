import AppKit
import Metal
import Observation
@preconcurrency import ScreenCaptureKit

@MainActor
@Observable
final class HighClarityRenderer: NSObject, HighClarityRendererProtocol {
    var onReady: (() -> Void)?
    var onFailure: ((String) -> Void)?
    var targetFrameRate = 60
    private(set) var isEnabled = false

    @ObservationIgnored private var sessions: [CGDirectDisplayID: HighClarityDisplaySession] = [:]
    @ObservationIgnored private var readyDisplays: Set<CGDirectDisplayID> = []
    @ObservationIgnored private var operationTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var profile = FilterPreset.twilight.profile

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displayConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(displayConfigurationChanged),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(displayConfigurationChanged),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
    }

    func start() {}

    func setEnabled(
        _ enabled: Bool,
        profile: FilterProfile,
        transitionDuration: Double,
        animated: Bool = true
    ) {
        self.profile = profile
        guard enabled != isEnabled || enabled && sessions.isEmpty else {
            updateProfile(profile, transitionDuration: transitionDuration)
            return
        }

        isEnabled = enabled
        generation += 1
        operationTask?.cancel()
        let currentGeneration = generation

        if enabled {
            operationTask = Task { @MainActor [weak self] in
                await self?.startSessions(generation: currentGeneration)
            }
        } else {
            let oldSessions = sessions.values
            sessions.removeAll()
            readyDisplays.removeAll()
            operationTask = Task { @MainActor in
                for session in oldSessions {
                    await session.stop()
                }
            }
        }
    }

    func updateProfile(_ profile: FilterProfile, transitionDuration: Double) {
        self.profile = profile
        for session in sessions.values {
            session.update(profile: profile)
        }
    }

    func stop() {
        isEnabled = false
        generation += 1
        operationTask?.cancel()
        let oldSessions = sessions.values
        sessions.removeAll()
        readyDisplays.removeAll()
        Task { @MainActor in
            for session in oldSessions {
                await session.stop()
            }
        }
    }

    @objc private func displayConfigurationChanged() {
        guard isEnabled else { return }
        setEnabled(
            false,
            profile: profile,
            transitionDuration: 0,
            animated: false
        )
        setEnabled(
            true,
            profile: profile,
            transitionDuration: 0,
            animated: false
        )
    }

    private func startSessions(generation expectedGeneration: Int) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            guard isEnabled,
                  generation == expectedGeneration,
                  !Task.isCancelled
            else { return }

            let ownApplications = content.applications.filter {
                $0.bundleIdentifier == Bundle.main.bundleIdentifier
            }
            let displaysByID = Dictionary(
                uniqueKeysWithValues: content.displays.map {
                    (CGDirectDisplayID($0.displayID), $0)
                }
            )
            var newSessions: [CGDirectDisplayID: HighClarityDisplaySession] = [:]

            for screen in NSScreen.screens {
                guard let displayID = screen.captureDisplayID,
                      let display = displaysByID[displayID]
                else { continue }

                let session = try HighClarityDisplaySession(
                    screen: screen,
                    display: display,
                    excludingApplications: ownApplications,
                    frameRate: targetFrameRate,
                    profile: profile,
                    onFirstFrame: { [weak self] in
                        self?.displayBecameReady(
                            displayID,
                            generation: expectedGeneration
                        )
                    },
                    onFailure: { [weak self] message in
                        guard let self,
                              self.generation == expectedGeneration,
                              self.isEnabled
                        else { return }
                        self.onFailure?("High Clarity stopped: \(message)")
                    }
                )
                newSessions[displayID] = session
            }

            guard !newSessions.isEmpty else {
                throw HighClaritySessionError.noDisplays
            }
            sessions = newSessions
            readyDisplays.removeAll()

            for session in newSessions.values {
                guard generation == expectedGeneration,
                      isEnabled,
                      !Task.isCancelled
                else { return }
                try await session.start()
            }
        } catch {
            guard generation == expectedGeneration, isEnabled else { return }
            onFailure?(error.localizedDescription)
        }
    }

    private func displayBecameReady(
        _ displayID: CGDirectDisplayID,
        generation expectedGeneration: Int
    ) {
        guard generation == expectedGeneration, isEnabled else { return }
        readyDisplays.insert(displayID)
        if readyDisplays.count == sessions.count {
            onReady?()
        }
    }
}

private enum HighClaritySessionError: LocalizedError {
    case noDisplays

    var errorDescription: String? {
        "No capturable displays were found."
    }
}

@MainActor
private final class HighClarityDisplaySession {
    private let panel: HighClarityPanel
    private let metalView: MetalFilterView
    private var captureSession: DisplayCaptureSession!
    private var isVisible = false

    init(
        screen: NSScreen,
        display: SCDisplay,
        excludingApplications: [SCRunningApplication],
        frameRate: Int,
        profile: FilterProfile,
        onFirstFrame: @escaping @MainActor () -> Void,
        onFailure: @escaping @MainActor (String) -> Void
    ) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw HighClarityMetalError.metalUnavailable
        }
        metalView = try MetalFilterView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            device: device
        )
        metalView.frameRenderer.update(profile: profile)

        panel = HighClarityPanel(
            contentRect: NSRect(origin: .zero, size: screen.frame.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.setFrame(screen.frame, display: false)
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.backgroundColor = .black
        panel.isOpaque = true
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.tabbingMode = .disallowed
        panel.contentView = metalView

        captureSession = DisplayCaptureSession(
            display: display,
            excludingApplications: excludingApplications,
            captureWidth: Int(screen.frame.width),
            captureHeight: Int(screen.frame.height),
            frameRate: frameRate,
            frameRenderer: metalView.frameRenderer,
            onFirstFrame: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    if !self.isVisible {
                        self.isVisible = true
                        self.panel.orderFrontRegardless()
                    }
                    onFirstFrame()
                }
            },
            onFailure: { message in
                Task { @MainActor in
                    onFailure(message)
                }
            }
        )
    }

    func start() async throws {
        try await captureSession.start()
    }

    func stop() async {
        panel.orderOut(nil)
        panel.close()
        await captureSession.stop()
    }

    func update(profile: FilterProfile) {
        metalView.frameRenderer.update(profile: profile)
    }
}

private final class HighClarityPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private extension NSScreen {
    var captureDisplayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }
}
