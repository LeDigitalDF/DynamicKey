// WiFiLocationAccessService.swift
// Requests Location Services access so CoreWLAN can read the current Wi-Fi SSID on macOS.
// Flow: Settings opens → requestWhenInUseAuthorization → user grants → SSID becomes readable.

import Combine
import CoreLocation
import Foundation

@MainActor
final class WiFiLocationAccessService: NSObject, ObservableObject {
    static let shared = WiFiLocationAccessService()

    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    private let locationManager = CLLocationManager()

    private override init() {
        authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
    }

    /// Prompts for Location access the first time; no-op when already decided.
    func requestAccessIfNeeded() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        default:
            break
        }
    }

    /// Whether the user has granted enough access to read Wi-Fi names.
    var canReadWiFiName: Bool {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            return false
        }
    }

    /// Settings footnote when the Wi-Fi name cannot be read yet.
    var ssidUnavailableFootnote: String {
        switch authorizationStatus {
        case .notDetermined:
            return "DynamicKey needs Location access to read your Wi-Fi name. Approve the prompt, or use the + button."
        case .denied, .restricted:
            return HardwareContextService.wiFiUnavailableGuidance
        default:
            return "Connect to Wi-Fi, then tap + to add this network."
        }
    }
}

extension WiFiLocationAccessService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
        }
    }
}
