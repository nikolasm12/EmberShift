import Foundation
import Observation

enum FilterRendererMode: String, CaseIterable, Identifiable, Codable {
    case compatibility
    case highClarity
    case automatic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compatibility: "Compatibility Overlay"
        case .highClarity: "High Clarity (Experimental)"
        case .automatic: "Automatic"
        }
    }

    var detail: String {
        switch self {
        case .compatibility:
            "The proven low-energy overlay. No screen access required."
        case .highClarity:
            "Converts captured luminance to red for clearer text."
        case .automatic:
            "Uses High Clarity when permission is available, otherwise the overlay."
        }
    }
}

enum ActiveFilterRenderer: String {
    case compatibility
    case highClarity

    var title: String {
        switch self {
        case .compatibility: "Compatibility Overlay"
        case .highClarity: "High Clarity"
        }
    }
}

@MainActor
protocol DisplayFilterRenderer: AnyObject {
    var isEnabled: Bool { get }
    func start()
    func setEnabled(
        _ enabled: Bool,
        profile: FilterProfile,
        transitionDuration: Double,
        animated: Bool
    )
    func updateProfile(_ profile: FilterProfile, transitionDuration: Double)
    func stop()
}

@MainActor
protocol HighClarityRendererProtocol: DisplayFilterRenderer {
    var onReady: (() -> Void)? { get set }
    var onFailure: ((String) -> Void)? { get set }
    var targetFrameRate: Int { get set }
}

@MainActor
protocol ScreenCapturePermissionProviding: AnyObject {
    var isGranted: Bool { get }
}

@MainActor
@Observable
final class FilterRendererCoordinator {
    private(set) var activeRenderer: ActiveFilterRenderer = .compatibility
    private(set) var fallbackReason: String?

    @ObservationIgnored private let overlay: DisplayFilterRenderer
    @ObservationIgnored private let highClarity: HighClarityRendererProtocol
    @ObservationIgnored private let permission: ScreenCapturePermissionProviding
    @ObservationIgnored private var desiredMode: FilterRendererMode = .compatibility
    @ObservationIgnored private var desiredEnabled = false
    @ObservationIgnored private var profile = FilterPreset.twilight.profile
    @ObservationIgnored private var transitionDuration = 1.5

    init(
        overlay: DisplayFilterRenderer,
        highClarity: HighClarityRendererProtocol,
        permission: ScreenCapturePermissionProviding
    ) {
        self.overlay = overlay
        self.highClarity = highClarity
        self.permission = permission

        highClarity.onReady = { [weak self] in
            self?.highClarityBecameReady()
        }
        highClarity.onFailure = { [weak self] message in
            self?.fallBackToOverlay(reason: message)
        }
    }

    var statusText: String {
        if let fallbackReason {
            return "\(activeRenderer.title): \(fallbackReason)"
        }
        return activeRenderer.title
    }

    func start() {
        overlay.start()
        highClarity.start()
    }

    func apply(
        enabled: Bool,
        profile: FilterProfile,
        transitionDuration: Double,
        mode: FilterRendererMode,
        frameRate: Int,
        animated: Bool = true
    ) {
        desiredEnabled = enabled
        desiredMode = mode
        self.profile = profile
        self.transitionDuration = transitionDuration
        highClarity.targetFrameRate = frameRate

        guard enabled else {
            highClarity.setEnabled(
                false,
                profile: profile,
                transitionDuration: transitionDuration,
                animated: animated
            )
            overlay.setEnabled(
                false,
                profile: profile,
                transitionDuration: transitionDuration,
                animated: animated
            )
            fallbackReason = nil
            activeRenderer = .compatibility
            return
        }

        let shouldTryHighClarity = mode == .highClarity
            || (mode == .automatic && permission.isGranted)
        guard shouldTryHighClarity, permission.isGranted else {
            highClarity.setEnabled(
                false,
                profile: profile,
                transitionDuration: transitionDuration,
                animated: false
            )
            overlay.setEnabled(
                true,
                profile: profile,
                transitionDuration: transitionDuration,
                animated: animated
            )
            activeRenderer = .compatibility
            fallbackReason = mode == .highClarity
                ? "Screen Recording permission is not available."
                : nil
            return
        }

        // Keep the stable overlay visible until every capture display has
        // produced a rendered frame. This prevents an unfiltered flash.
        overlay.setEnabled(
            true,
            profile: profile,
            transitionDuration: transitionDuration,
            animated: animated
        )
        activeRenderer = .compatibility
        fallbackReason = "Starting High Clarity…"
        highClarity.setEnabled(
            true,
            profile: profile,
            transitionDuration: transitionDuration,
            animated: false
        )
    }

    func updateProfile(_ profile: FilterProfile, transitionDuration: Double) {
        self.profile = profile
        self.transitionDuration = transitionDuration
        overlay.updateProfile(profile, transitionDuration: transitionDuration)
        highClarity.updateProfile(profile, transitionDuration: transitionDuration)
    }

    func refreshPermissionAndRenderer(frameRate: Int) {
        apply(
            enabled: desiredEnabled,
            profile: profile,
            transitionDuration: transitionDuration,
            mode: desiredMode,
            frameRate: frameRate,
            animated: false
        )
    }

    func stop() {
        highClarity.stop()
        overlay.stop()
    }

    private func highClarityBecameReady() {
        guard desiredEnabled,
              (
                desiredMode == .highClarity
                    || (desiredMode == .automatic && permission.isGranted)
              )
        else { return }

        activeRenderer = .highClarity
        fallbackReason = nil
        overlay.setEnabled(
            false,
            profile: profile,
            transitionDuration: min(transitionDuration, 0.35),
            animated: true
        )
    }

    private func fallBackToOverlay(reason: String) {
        guard desiredEnabled else { return }
        highClarity.setEnabled(
            false,
            profile: profile,
            transitionDuration: transitionDuration,
            animated: false
        )
        overlay.setEnabled(
            true,
            profile: profile,
            transitionDuration: min(transitionDuration, 0.35),
            animated: true
        )
        activeRenderer = .compatibility
        fallbackReason = reason
    }
}
