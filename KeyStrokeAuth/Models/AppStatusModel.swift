// AppStatusModel.swift
// Menu bar status for profile readiness.

import Foundation
import Combine

@MainActor
final class AppStatusModel: ObservableObject {
    @Published private(set) var statusText: String = "Checking profile…"

    private let profileStore = ProfileStore.shared

    init() {
        Task { @MainActor in
            refresh()
        }
    }

    func refresh() {
        let profileReady = profileStore.hasProfile
        let serviceRunning = LocalAuthServiceManager.shared.isRunning
        let pausedByUser = LocalAuthServiceManager.shared.isPausedByUser

        switch (profileReady, serviceRunning, pausedByUser) {
        case (true, true, false):
            statusText = "Profile ready — extension API listening on localhost."
        case (true, _, true):
            statusText = "Profile ready — extension API paused by user."
        case (true, false, false):
            statusText = "Profile ready — extension API is stopped."
        case (false, _, _):
            statusText = "No profile enrolled yet."
        }
    }
}
