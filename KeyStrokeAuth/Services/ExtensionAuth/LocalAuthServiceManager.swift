// LocalAuthServiceManager.swift
// MainActor coordinator for the extension auth server lifecycle and pairing UI (M5).
//
// Flow: start on app launch → expose pairing codes in Settings → stop on quit/sleep.

import Foundation
import Combine
import AppKit

@MainActor
final class LocalAuthServiceManager: ObservableObject {
    static let shared = LocalAuthServiceManager()

    @Published private(set) var isRunning = false
    @Published private(set) var isPausedByUser = false
    @Published private(set) var lastError: String?
    @Published private(set) var activePairingCode: String?
    @Published private(set) var pairingCodeExpiresAt: Date?
    @Published private(set) var pairedClients: [PairedExtensionClient] = []

    var pairedClientCount: Int {
        pairedClients.count
    }

    var serviceAddress: String {
        ExtensionAuthConfig.baseURL
    }

    private let server = LocalAuthHTTPServer()
    private let pairingStore = ExtensionPairingStore.shared
    private static let userPauseDefaultsKey = "dynamicKey.extensionAPIPausedByUser"
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var activateObserver: NSObjectProtocol?

    private init() {
        isPausedByUser = UserDefaults.standard.bool(forKey: Self.userPauseDefaultsKey)
        refreshPairingCodeState()
        refreshPairedClients()

        NotificationCenter.default.addObserver(
            forName: .extensionPairingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPairedClients()
                self?.refreshPairingCodeState()
            }
        }

        activateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPairedClients()
                self?.refreshPairingCodeState()
            }
        }
    }

    /// Starts the localhost server and registers sleep/wake observers.
    func start() {
        guard !isRunning else { return }
        guard !isPausedByUser else { return }

        do {
            try server.start()
            isRunning = true
            lastError = nil
            registerWorkspaceObservers()
        } catch {
            isRunning = false
            lastError = error.localizedDescription
            NSLog("KeyStrokeAuth: local auth server failed to start: \(error.localizedDescription)")
        }
    }

    /// Stops the server and removes workspace observers.
    func stop(keepWorkspaceObservers: Bool = false) {
        if !keepWorkspaceObservers {
            unregisterWorkspaceObservers()
        }
        server.stop()
        isRunning = false
    }

    /// Restarts the server after wake or a failed start attempt.
    func restart() {
        stop(keepWorkspaceObservers: true)
        start()
    }

    /// Temporarily pauses extension API responses until the user resumes from the menu bar.
    func pauseByUser() {
        isPausedByUser = true
        UserDefaults.standard.set(true, forKey: Self.userPauseDefaultsKey)
        server.stop()
        isRunning = false
    }

    /// Resumes extension API service after a user-initiated pause.
    func resumeByUser() {
        isPausedByUser = false
        UserDefaults.standard.set(false, forKey: Self.userPauseDefaultsKey)
        start()
    }

    /// Creates a short-lived pairing code the user can give to the browser extension.
    func generatePairingCode() {
        let code = Self.makePairingCode()
        let expiresAt = Date().addingTimeInterval(ExtensionAuthConfig.pairingCodeLifetimeSeconds)
        let pending = PendingPairingCode(code: code, expiresAt: expiresAt)

        do {
            try pairingStore.savePendingCode(pending)
            activePairingCode = code
            pairingCodeExpiresAt = expiresAt
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Revokes all paired extensions and clears any pending pairing code.
    func revokeAllPairings() {
        pairingStore.revokeAllPairings()
        activePairingCode = nil
        pairingCodeExpiresAt = nil
        refreshPairedClients()
        AuditLogService.shared.append(AuditEvent(type: .extensionPairingsRevoked))
    }

    /// Unpairs one extension client from the MenuBar or Settings.
    func unpairClient(id: String) {
        let name = pairedClients.first(where: { $0.id == id }).map {
            PairedBrowserDisplay.browserLabel(for: $0).name
        }
        pairingStore.revokeClient(id: id)
        refreshPairedClients()
        AuditLogService.shared.append(
            AuditEvent(
                type: .extensionPairingsRevoked,
                detail: name.map { "Unpaired \($0)" }
            )
        )
    }

    /// Reloads paired clients from Keychain, migrates legacy rows, and dedupes by browser family.
    func refreshPairedClients() {
        let raw = pairingStore.pairedClients()
        let normalized = PairedBrowserDisplay.normalizedClients(raw)

        if normalized != raw {
            try? pairingStore.replacePairedClients(normalized)
        }

        pairedClients = normalized
    }

    /// Syncs published pairing code state with Keychain expiry.
    func refreshPairingCodeState() {
        if let pending = pairingStore.activePendingCode() {
            activePairingCode = pending.code
            pairingCodeExpiresAt = pending.expiresAt
        } else {
            activePairingCode = nil
            pairingCodeExpiresAt = nil
        }
    }

    /// Builds an 8-character pairing code excluding ambiguous characters.
    private static func makePairingCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<8).map { _ in alphabet.randomElement()! })
    }

    /// Pauses the server while the Mac sleeps to avoid stale listeners.
    private func registerWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter

        sleepObserver = center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.stop(keepWorkspaceObservers: true)
        }

        wakeObserver = center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.isPausedByUser else { return }
            self.start()
        }
    }

    /// Removes sleep/wake observers when the service stops.
    private func unregisterWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        if let sleepObserver {
            center.removeObserver(sleepObserver)
            self.sleepObserver = nil
        }
        if let wakeObserver {
            center.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }
}
