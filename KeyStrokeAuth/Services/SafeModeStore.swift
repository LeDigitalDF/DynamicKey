// SafeModeStore.swift
// 24-hour Safe Mode — shared by Mac app and browser extension via localhost API.
// Flow: activate from Settings, Home sidebar, or extension → expiresAt persisted → both UIs show countdown → deactivate from either side.

import Combine
import Foundation

@MainActor
final class SafeModeStore: ObservableObject {
    static let shared = SafeModeStore()

    /// How long each activation lasts before returning to default rhythm-only extension unlock.
    static let activationDuration: TimeInterval = 24 * 60 * 60

    @Published private(set) var expiresAt: Date?
    @Published private(set) var now = Date()

    private var countdownTimer: AnyCancellable?

    var isActive: Bool {
        guard let expiresAt else { return false }
        return expiresAt > now
    }

    var remainingTimeInterval: TimeInterval {
        guard let expiresAt, expiresAt > now else { return 0 }
        return expiresAt.timeIntervalSince(now)
    }

    /// Hours : minutes : seconds remaining — shown on the Safe Mode card while active.
    var formattedRemainingTime: String {
        let total = max(0, Int(remainingTimeInterval.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }

    /// Activates Safe Mode for 24 hours. No-op while already active — use `deactivate()` to end early.
    func activate() {
        guard !isActive else { return }
        expiresAt = Date().addingTimeInterval(Self.activationDuration)
        persist()
        now = Date()
        startCountdownTimerIfNeeded()
        AuditLogService.shared.append(AuditEvent(type: .safeModeEngaged))
    }

    /// Ends Safe Mode immediately before the 24-hour window expires.
    func deactivate() {
        guard isActive else { return }
        expiresAt = nil
        persist()
        now = Date()
        stopCountdownTimer()
        AuditLogService.shared.append(AuditEvent(type: .safeModeEnded))
    }

    /// Drops expired sessions so `isActive` and the countdown stay accurate.
    func refreshExpiryIfNeeded() {
        now = Date()
        guard let expiresAt, expiresAt <= now else { return }
        self.expiresAt = nil
        persist()
        stopCountdownTimer()
        AuditLogService.shared.append(AuditEvent(type: .safeModeEnded))
    }

    private init() {
        let storedInterval = UserDefaults.standard.double(forKey: Keys.expiresAt)
        if storedInterval > 0 {
            expiresAt = Date(timeIntervalSince1970: storedInterval)
        } else {
            // Migrate legacy Emergency Lock expiry into Safe Mode (unified feature).
            let legacyInterval = UserDefaults.standard.double(forKey: Keys.legacyEmergencyLockExpiresAt)
            if legacyInterval > 0 {
                expiresAt = Date(timeIntervalSince1970: legacyInterval)
                UserDefaults.standard.removeObject(forKey: Keys.legacyEmergencyLockExpiresAt)
                persist()
            }
        }
        refreshExpiryIfNeeded()
        startCountdownTimerIfNeeded()
    }

    private func persist() {
        if let expiresAt {
            UserDefaults.standard.set(expiresAt.timeIntervalSince1970, forKey: Keys.expiresAt)
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.expiresAt)
        }

        // Legacy toggle from the old Touch ID Fallback card — no longer used.
        UserDefaults.standard.removeObject(forKey: Keys.legacyFallbackAuthenticationEnabled)
    }

    private func startCountdownTimerIfNeeded() {
        stopCountdownTimer()
        guard isActive else { return }

        countdownTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in
                guard let self else { return }
                self.now = date
                self.refreshExpiryIfNeeded()
            }
    }

    private func stopCountdownTimer() {
        countdownTimer = nil
    }

    private enum Keys {
        static let expiresAt = "dynamicKeySafeModeExpiresAt"
        static let legacyFallbackAuthenticationEnabled = "dynamicKeyFallbackAuthenticationEnabled"
        static let legacyEmergencyLockExpiresAt = "dynamicKeyEmergencyLockExpiresAt"
    }
}
