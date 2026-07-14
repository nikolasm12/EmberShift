import AppKit
import CoreGraphics
import Observation

enum ScreenCapturePermissionStatus: String {
    case granted
    case notGranted

    var title: String {
        switch self {
        case .granted: "Granted"
        case .notGranted: "Not Granted"
        }
    }
}

@MainActor
@Observable
final class ScreenCapturePermission: ScreenCapturePermissionProviding {
    private(set) var status: ScreenCapturePermissionStatus = .notGranted

    init() {
        refresh()
    }

    var isGranted: Bool {
        status == .granted
    }

    func refresh() {
        status = CGPreflightScreenCaptureAccess() ? .granted : .notGranted
    }

    @discardableResult
    func request() -> Bool {
        let granted = CGRequestScreenCaptureAccess()
        refresh()
        return granted
    }

    func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
