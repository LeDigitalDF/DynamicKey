// LaunchAtLoginService.swift
// Registers or unregisters DynamicKey as a login item using SMAppService.
// Flow: preference toggle → applyPreference → register/unregister main app service.

import Combine
import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginService: ObservableObject {
    static let shared = LaunchAtLoginService()

    @Published private(set) var lastErrorMessage: String?

    private init() {}

    /// Applies the stored user preference to the system login item registration.
    func applyPreference(_ enabled: Bool) {
        Task { @MainActor in
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
                lastErrorMessage = nil
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    /// Reads the actual login-item registration state from the system.
    var isRegistered: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Syncs the stored preference with the system login-item registration after launch.
    func reconcileStoredPreference(_ storedEnabled: Bool) {
        guard storedEnabled != isRegistered else { return }
        applyPreference(storedEnabled)
    }
}
