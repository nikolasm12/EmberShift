import AppKit
import QuartzCore

@MainActor
final class ScreenOverlayController: NSObject, DisplayFilterRenderer {
    private var panels: [CGDirectDisplayID: OverlayPanel] = [:]
    private(set) var isEnabled = false
    private var profile = FilterPreset.twilight.profile
    private var transitionDuration = 1.5

    var panelCount: Int { panels.count }
    var visiblePanelCount: Int { panels.values.filter(\.isVisible).count }
    var panelAlphaValues: [CGFloat] { panels.values.map(\.alphaValue) }
    var panelFramesByDisplay: [CGDirectDisplayID: NSRect] {
        panels.mapValues(\.frame)
    }
    var allPanelsIgnoreMouseEvents: Bool { panels.values.allSatisfy(\.ignoresMouseEvents) }
    var allPanelsAvoidKeyStatus: Bool {
        panels.values.allSatisfy { !$0.canBecomeKey && !$0.canBecomeMain }
    }

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(displayDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(displayDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
    }

    func start() {
        rebuildPanels()
    }

    func setEnabled(
        _ enabled: Bool,
        profile: FilterProfile,
        transitionDuration: Double,
        animated: Bool = true
    ) {
        self.profile = profile
        self.transitionDuration = transitionDuration
        let wasEnabled = isEnabled
        isEnabled = enabled

        if panels.isEmpty {
            rebuildPanels()
        }

        for panel in panels.values {
            panel.overlayView.apply(
                profile: profile,
                duration: animated ? transitionDuration : 0
            )

            if enabled {
                if !wasEnabled {
                    panel.alphaValue = animated ? 0 : 1
                    panel.orderFrontRegardless()
                    animate(panel: panel, to: 1, duration: animated ? transitionDuration : 0)
                } else {
                    panel.alphaValue = 1
                    if !panel.isVisible {
                        panel.orderFrontRegardless()
                    }
                }
            } else if wasEnabled {
                animate(panel: panel, to: 0, duration: animated ? transitionDuration : 0) { [weak self, weak panel] in
                    guard self?.isEnabled == false else { return }
                    panel?.orderOut(nil)
                }
            } else {
                panel.orderOut(nil)
            }
        }
    }

    func updateProfile(_ profile: FilterProfile, transitionDuration: Double) {
        self.profile = profile
        self.transitionDuration = transitionDuration
        guard isEnabled else { return }
        for panel in panels.values {
            panel.overlayView.apply(profile: profile, duration: transitionDuration)
        }
    }

    func stop() {
        isEnabled = false
        for panel in panels.values {
            panel.orderOut(nil)
            panel.close()
        }
        panels.removeAll()
    }

    @objc private func screenConfigurationChanged() {
        rebuildPanels()
    }

    @objc private func activeSpaceChanged() {
        guard isEnabled else { return }
        for panel in panels.values {
            panel.orderFrontRegardless()
        }
    }

    @objc private func displayDidWake() {
        rebuildPanels()
        activeSpaceChanged()
    }

    private func rebuildPanels() {
        let screensByID = Dictionary(
            uniqueKeysWithValues: NSScreen.screens.compactMap { screen in
                screen.displayID.map { ($0, screen) }
            }
        )

        for (displayID, panel) in panels where screensByID[displayID] == nil {
            panel.orderOut(nil)
            panel.close()
            panels.removeValue(forKey: displayID)
        }

        for (displayID, screen) in screensByID {
            if let panel = panels[displayID] {
                panel.setFrame(screen.frame, display: false)
                panel.overlayView.frame = NSRect(origin: .zero, size: screen.frame.size)
            } else {
                let panel = makePanel(for: screen)
                panels[displayID] = panel
                panel.overlayView.apply(profile: profile, duration: 0)
                panel.alphaValue = isEnabled ? 1 : 0
                if isEnabled {
                    panel.orderFrontRegardless()
                }
            }
        }
    }

    private func makePanel(for screen: NSScreen) -> OverlayPanel {
        let panel = OverlayPanel(
            contentRect: NSRect(origin: .zero, size: screen.frame.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        // The screen-aware initializer incorrectly scales a global origin when
        // a Retina main display is paired with a non-Retina external display.
        // Position explicitly in AppKit's global point coordinate space.
        panel.setFrame(screen.frame, display: false)
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.tabbingMode = .disallowed

        let overlayView = FilterOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        panel.contentView = overlayView
        return panel
    }

    private func animate(
        panel: NSPanel,
        to alpha: CGFloat,
        duration: Double,
        completion: (@MainActor @Sendable () -> Void)? = nil
    ) {
        guard duration > 0, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.alphaValue = alpha
            completion?()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = alpha
        } completionHandler: {
            Task { @MainActor in
                completion?()
            }
        }
    }
}

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    var overlayView: FilterOverlayView {
        contentView as! FilterOverlayView
    }
}

private final class FilterOverlayView: NSView {
    private let tintLayer = CALayer()
    private let dimLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.isGeometryFlipped = true
        tintLayer.actions = ["backgroundColor": NSNull(), "opacity": NSNull()]
        dimLayer.actions = ["backgroundColor": NSNull(), "opacity": NSNull()]
        layer?.addSublayer(tintLayer)
        layer?.addSublayer(dimLayer)
        dimLayer.backgroundColor = NSColor.black.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        tintLayer.frame = bounds
        dimLayer.frame = bounds
    }

    func apply(profile: FilterProfile, duration: Double) {
        animate(layer: tintLayer, keyPath: "backgroundColor", to: profile.tintColor.cgColor, duration: duration)
        animate(layer: tintLayer, keyPath: "opacity", to: Float(profile.intensity), duration: duration)
        animate(layer: dimLayer, keyPath: "opacity", to: Float(profile.dimming), duration: duration)
    }

    private func animate(layer: CALayer, keyPath: String, to value: Any, duration: Double) {
        if duration > 0, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let animation = CABasicAnimation(keyPath: keyPath)
            animation.fromValue = layer.presentation()?.value(forKeyPath: keyPath) ?? layer.value(forKeyPath: keyPath)
            animation.toValue = value
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(animation, forKey: keyPath)
        }
        layer.setValue(value, forKeyPath: keyPath)
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }
}
