// LeakPeekStore.swift
// Persists LeakPeek scan results, weekly auto-scan preference, and orchestrates breach checks.
// Flow: Scan Now → k-anonymity lookup per saved site password → publish Safe / Compromised badges.

import Combine
import Foundation

@MainActor
final class LeakPeekStore: ObservableObject {
    static let shared = LeakPeekStore()

    @Published private(set) var statuses: [UUID: LeakPeekCredentialStatus] = [:]
    @Published private(set) var lastScanDate: Date?
    @Published private(set) var isScanning = false
    @Published private(set) var lastScanError: String?
    @Published var weeklyAutoScanEnabled: Bool {
        didSet { UserDefaults.standard.set(weeklyAutoScanEnabled, forKey: Keys.weeklyAutoScanEnabled) }
    }

    var hasCompromisedPasswords: Bool {
        statuses.values.contains(where: \.isCompromised)
    }

    private enum Keys {
        static let weeklyAutoScanEnabled = "dynamicKey.leakPeek.weeklyAutoScanEnabled"
        static let lastScanDate = "dynamicKey.leakPeek.lastScanDate"
        static let statuses = "dynamicKey.leakPeek.statuses"
    }

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private static let weeklyInterval: TimeInterval = 7 * 24 * 60 * 60

    private init() {
        weeklyAutoScanEnabled = UserDefaults.standard.bool(forKey: Keys.weeklyAutoScanEnabled)
        lastScanDate = UserDefaults.standard.object(forKey: Keys.lastScanDate) as? Date
        statuses = Self.loadStatuses()
    }

    func siteStatus(for credentialID: UUID) -> LeakPeekSiteStatus {
        statuses[credentialID]?.siteStatus ?? .unknown
    }

    /// Drops scan rows for credentials that were deleted.
    func syncCredentialList(_ credentials: [SiteCredential]) {
        let validIDs = Set(credentials.map(\.id))
        let pruned = statuses.filter { validIDs.contains($0.key) }
        guard pruned.count != statuses.count else { return }
        statuses = pruned
        persistStatuses()
    }

    /// Clears breach status for one site so the UI shows Not scanned until the next check.
    func clearStatus(for credentialID: UUID) {
        guard statuses.removeValue(forKey: credentialID) != nil else { return }
        persistStatuses()
    }

    /// Runs a breach scan when weekly auto-scan is enabled and the interval has elapsed.
    func runWeeklyScanIfNeeded(credentials: [SiteCredential]) async {
        guard weeklyAutoScanEnabled else { return }
        guard !isScanning else { return }

        if let lastScanDate,
           Date().timeIntervalSince(lastScanDate) < Self.weeklyInterval {
            return
        }

        await scan(credentials: credentials)
    }

    /// Checks every saved site password against the Pwned Passwords range API.
    func scan(credentials: [SiteCredential]) async {
        guard !isScanning else { return }

        isScanning = true
        lastScanError = nil
        syncCredentialList(credentials)

        defer { isScanning = false }

        guard !credentials.isEmpty else {
            statuses = [:]
            lastScanDate = Date()
            persistStatuses()
            persistLastScanDate()
            return
        }

        var updated = statuses
        var encounteredError: String?

        for (index, credential) in credentials.enumerated() {
            if Task.isCancelled { return }

            do {
                let compromised = try await PwnedPasswordsService.isPasswordCompromised(credential.password)
                updated[credential.id] = LeakPeekCredentialStatus(
                    credentialID: credential.id,
                    isCompromised: compromised,
                    checkedAt: Date()
                )
                statuses = updated
            } catch {
                encounteredError = error.localizedDescription
            }

            if index < credentials.count - 1 {
                await PwnedPasswordsService.throttleBetweenChecks()
            }
        }

        lastScanError = encounteredError
        lastScanDate = Date()
        statuses = updated
        persistStatuses()
        persistLastScanDate()
    }

    private func persistStatuses() {
        let records = Array(statuses.values)
        guard let data = try? encoder.encode(records) else { return }
        UserDefaults.standard.set(data, forKey: Keys.statuses)
    }

    private func persistLastScanDate() {
        UserDefaults.standard.set(lastScanDate, forKey: Keys.lastScanDate)
    }

    private static func loadStatuses() -> [UUID: LeakPeekCredentialStatus] {
        guard let data = UserDefaults.standard.data(forKey: Keys.statuses),
              let records = try? JSONDecoder().decode([LeakPeekCredentialStatus].self, from: data) else {
            return [:]
        }

        return Dictionary(uniqueKeysWithValues: records.map { ($0.credentialID, $0) })
    }
}
