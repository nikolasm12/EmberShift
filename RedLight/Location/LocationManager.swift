@preconcurrency import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
final class LocationManager: NSObject, @preconcurrency CLLocationManagerDelegate {
    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var isLocating = false
    private(set) var lastError: String?

    @ObservationIgnored var onLocationChange: ((StoredCoordinate) -> Void)?
    @ObservationIgnored private let manager: CLLocationManager

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = 10_000
    }

    var statusText: String {
        switch authorizationStatus {
        case .notDetermined: "Location not requested"
        case .restricted: "Location restricted"
        case .denied: "Location denied"
        case .authorizedAlways: "Location enabled"
        @unknown default: "Location unavailable"
        }
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedAlways
    }

    func requestLocationAccess() {
        lastError = nil
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways:
            refreshLocation()
        case .denied, .restricted:
            lastError = "Allow location access in System Settings, or use custom schedule times."
        @unknown default:
            lastError = "Location services are unavailable."
        }
    }

    func refreshLocation() {
        guard isAuthorized else {
            requestLocationAccess()
            return
        }
        isLocating = true
        lastError = nil
        manager.requestLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if isAuthorized {
            refreshLocation()
        } else if authorizationStatus == .denied || authorizationStatus == .restricted {
            isLocating = false
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        isLocating = false
        guard let location = locations
            .filter({ $0.horizontalAccuracy >= 0 })
            .max(by: { $0.timestamp < $1.timestamp })
        else {
            lastError = "No location fix was available. Try again, or use custom times."
            return
        }

        let coordinate = StoredCoordinate(
            latitude: rounded(location.coordinate.latitude),
            longitude: rounded(location.coordinate.longitude),
            timestamp: Date()
        )
        onLocationChange?(coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLocating = false
        if let locationError = error as? CLError, locationError.code == .denied {
            authorizationStatus = manager.authorizationStatus
            lastError = "Location access is denied. Custom schedule times remain available."
        } else {
            lastError = "Couldn’t update location. The last saved sunrise and sunset will still be used."
        }
    }

    private func rounded(_ value: Double) -> Double {
        (value * 1_000).rounded() / 1_000
    }
}
