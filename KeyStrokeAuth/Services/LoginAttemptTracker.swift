// LoginAttemptTracker.swift
// Rate limiting and exponential lockout after repeated failed sign-in attempts (M3.1, M3.2).

import Foundation

enum LockoutStatus: Equatable {
    case available(remainingAttempts: Int)
    case locked(until: Date)

    var isLocked: Bool {
        if case .locked = self { return true }
        return false
    }

    var remainingSeconds: Int? {
        guard case .locked(let until) = self else { return nil }
        return max(0, Int(ceil(until.timeIntervalSinceNow)))
    }
}

final class LoginAttemptTracker {
    static let shared = LoginAttemptTracker()

    private let failuresKey = "LeDigital.KeyStrokeAuth.loginFailures"
    private let lockoutUntilKey = "LeDigital.KeyStrokeAuth.lockoutUntil"
    private let lockoutLevelKey = "LeDigital.KeyStrokeAuth.lockoutLevel"

    private init() {}

    func status(now: Date = Date()) -> LockoutStatus {
        if let lockoutUntil = lockoutUntilDate(), lockoutUntil > now {
            return .locked(until: lockoutUntil)
        }

        if lockoutUntilDate() != nil {
            clearExpiredLockout(now: now)
        }

        let recentFailures = recentFailureDates(now: now)
        let remaining = max(0, SecurityConfig.maxFailedAttemptsBeforeLockout - recentFailures.count)
        return .available(remainingAttempts: remaining)
    }

    func recordFailure(now: Date = Date()) {
        var failures = loadFailureDates()
        failures.append(now)
        failures = prune(failures, now: now)
        saveFailureDates(failures)

        if failures.count >= SecurityConfig.maxFailedAttemptsBeforeLockout {
            activateLockout(now: now)
        }
    }

    func recordSuccess() {
        UserDefaults.standard.removeObject(forKey: failuresKey)
        UserDefaults.standard.removeObject(forKey: lockoutUntilKey)
        UserDefaults.standard.set(0, forKey: lockoutLevelKey)
    }

    func reset() {
        recordSuccess()
    }

    private func activateLockout(now: Date) {
        let level = UserDefaults.standard.integer(forKey: lockoutLevelKey) + 1
        UserDefaults.standard.set(level, forKey: lockoutLevelKey)

        let duration = min(
            SecurityConfig.baseLockoutSeconds * pow(2, Double(level - 1)),
            SecurityConfig.maxLockoutSeconds
        )
        let lockoutUntil = now.addingTimeInterval(duration)
        UserDefaults.standard.set(lockoutUntil.timeIntervalSince1970, forKey: lockoutUntilKey)
        saveFailureDates([])
    }

    private func clearExpiredLockout(now: Date) {
        guard let until = lockoutUntilDate(), until <= now else { return }
        UserDefaults.standard.removeObject(forKey: lockoutUntilKey)
    }

    private func recentFailureDates(now: Date) -> [Date] {
        prune(loadFailureDates(), now: now)
    }

    private func prune(_ failures: [Date], now: Date) -> [Date] {
        let cutoff = now.addingTimeInterval(-SecurityConfig.failureWindowSeconds)
        return failures.filter { $0 >= cutoff }
    }

    private func loadFailureDates() -> [Date] {
        let intervals = UserDefaults.standard.array(forKey: failuresKey) as? [TimeInterval] ?? []
        return intervals.map { Date(timeIntervalSince1970: $0) }
    }

    private func saveFailureDates(_ failures: [Date]) {
        let intervals = failures.map(\.timeIntervalSince1970)
        UserDefaults.standard.set(intervals, forKey: failuresKey)
    }

    private func lockoutUntilDate() -> Date? {
        let interval = UserDefaults.standard.double(forKey: lockoutUntilKey)
        guard interval > 0 else { return nil }
        return Date(timeIntervalSince1970: interval)
    }
}
