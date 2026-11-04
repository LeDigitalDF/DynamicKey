// LeakPeekIdentityStore.swift
// Orchestrates email breach checks and drives the fullscreen LeakPeek overlay.
// Flow: Check Breaches → throttle per email → publish progress → show in-app results.

import Combine
import Foundation

@MainActor
final class LeakPeekIdentityStore: ObservableObject {
    static let shared = LeakPeekIdentityStore()

    @Published private(set) var statuses: [String: LeakPeekIdentityStatus] = [:]
    @Published private(set) var phase: LeakPeekBreachCheckPhase = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var statusMessage = ""
    @Published private(set) var radarBlips: [LeakPeekRadarBlip] = []
    @Published private(set) var dismissedBreaches: Set<LeakPeekDismissedBreach> = []
    @Published private(set) var lastIdentityCheckDate: Date?

    var isChecking: Bool {
        if case .running = phase { return true }
        return false
    }

    var showsOverlay: Bool {
        phase != .idle
    }

    var hasCompromisedIdentities: Bool {
        statuses.values.contains { hasActiveCompromises(for: $0) }
    }

    private enum Keys {
        static let statuses = "dynamicKey.leakPeek.identityStatuses"
        static let lastCheckDate = "dynamicKey.leakPeek.lastIdentityCheckDate"
        static let dismissedBreaches = "dynamicKey.leakPeek.dismissedBreaches"
    }

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        statuses = Self.loadStatuses()
        lastIdentityCheckDate = UserDefaults.standard.object(forKey: Keys.lastCheckDate) as? Date
        dismissedBreaches = Self.loadDismissedBreaches()
    }

    func identityStatus(for email: String) -> LeakPeekIdentityDisplayStatus {
        let key = LeakPeekEmailValidator.normalized(email)
        guard let record = statuses[key] else { return .unknown }
        if !record.isCompromised { return .safe }
        return hasActiveCompromises(for: record) ? .compromised : .safe
    }

    /// Breach names for one email that are not dismissed or marked resolved.
    func activeBreachNames(for status: LeakPeekIdentityStatus) -> [String] {
        status.breachNames.filter { breachName in
            !isBreachDismissed(email: status.email, breachName: breachName)
        }
    }

    func activeBreachNames(forEmail email: String) -> [String] {
        let key = LeakPeekEmailValidator.normalized(email)
        guard let record = statuses[key] else { return [] }
        return activeBreachNames(for: record)
    }

    func hasActiveCompromises(for status: LeakPeekIdentityStatus) -> Bool {
        status.isCompromised && !activeBreachNames(for: status).isEmpty
    }

    func activeCompromisedStatuses() -> [LeakPeekIdentityStatus] {
        statuses.values
            .filter(hasActiveCompromises)
            .sorted { $0.email.localizedCaseInsensitiveCompare($1.email) == .orderedAscending }
    }

    func dismissBreach(email: String, breachName: String) {
        let entry = LeakPeekDismissedBreach(
            email: LeakPeekEmailValidator.normalized(email),
            breachName: breachName
        )
        guard dismissedBreaches.insert(entry).inserted else { return }
        persistDismissedBreaches()
        refreshStatusMessage()
    }

    /// Clears every breach for one email from the action list (already fixed elsewhere).
    func markEmailResolved(_ email: String) {
        let key = LeakPeekEmailValidator.normalized(email)
        guard let record = statuses[key] else { return }

        var updated = dismissedBreaches
        for breachName in record.breachNames {
            updated.insert(LeakPeekDismissedBreach(email: key, breachName: breachName))
        }
        dismissedBreaches = updated
        persistDismissedBreaches()
        refreshStatusMessage()
    }

    private func isBreachDismissed(email: String, breachName: String) -> Bool {
        dismissedBreaches.contains(
            LeakPeekDismissedBreach(
                email: LeakPeekEmailValidator.normalized(email),
                breachName: breachName
            )
        )
    }

    private func refreshStatusMessage() {
        let activeCount = activeCompromisedStatuses().count
        statusMessage = activeCount > 0
            ? "\(activeCount) email\(activeCount == 1 ? "" : "s") still need attention"
            : "All known breaches are resolved or dismissed"
    }

    func identityRecord(for email: String) -> LeakPeekIdentityStatus? {
        statuses[LeakPeekEmailValidator.normalized(email)]
    }

    /// Dismisses the overlay and returns to the LeakPeek screen.
    func dismissOverlay() {
        phase = .idle
        progress = 0
        statusMessage = ""
        radarBlips = []
    }

    /// Checks unique email usernames from saved credentials without opening a browser.
    func checkBreaches(credentials: [SiteCredential]) async {
        guard !isChecking else { return }

        let emails = LeakPeekEmailValidator.uniqueEmails(from: credentials)
        guard !emails.isEmpty else {
            phase = .failed("No email addresses found in your saved usernames.")
            progress = 0
            return
        }

        phase = .running
        progress = 0
        statusMessage = "Preparing breach check…"
        radarBlips = LeakPeekRadarBlip.layout(for: emails)

        var updated = statuses
        var results: [LeakPeekIdentityStatus] = []
        var encounteredError: String?

        for (index, email) in emails.enumerated() {
            if Task.isCancelled { return }

            let normalized = LeakPeekEmailValidator.normalized(email)
            statusMessage = "Checking \(email) (\(index + 1) of \(emails.count))"
            progress = Double(index) / Double(emails.count)

            do {
                let breachNames = try await EmailBreachCheckService.checkEmail(email)
                let record = LeakPeekIdentityStatus(
                    email: normalized,
                    isCompromised: !breachNames.isEmpty,
                    breachNames: breachNames,
                    checkedAt: Date()
                )
                updated[normalized] = record
                results.append(record)
                statuses = updated
                updateRadarBlip(id: normalized, isCompromised: record.isCompromised)
            } catch {
                encounteredError = error.localizedDescription
                break
            }

            progress = Double(index + 1) / Double(emails.count)

            if index < emails.count - 1 {
                await EmailBreachCheckService.throttleBetweenChecks()
            }
        }

        if let encounteredError {
            phase = .failed(encounteredError)
            return
        }

        let summary = LeakPeekBreachCheckSummary(results: results, checkedAt: Date())
        statuses = updated
        lastIdentityCheckDate = summary.checkedAt
        persistStatuses()
        persistLastCheckDate()

        statusMessage = summary.compromisedCount > 0
            ? "\(summary.compromisedCount) email\(summary.compromisedCount == 1 ? "" : "s") found in known breaches"
            : "No breaches found for your saved emails"

        phase = .finished(summary)
    }

    private func updateRadarBlip(id: String, isCompromised: Bool) {
        guard let index = radarBlips.firstIndex(where: { $0.id == id }) else { return }
        radarBlips[index].isChecked = true
        radarBlips[index].isCompromised = isCompromised
    }

    private func persistStatuses() {
        let records = Array(statuses.values)
        guard let data = try? encoder.encode(records) else { return }
        UserDefaults.standard.set(data, forKey: Keys.statuses)
    }

    private func persistLastCheckDate() {
        UserDefaults.standard.set(lastIdentityCheckDate, forKey: Keys.lastCheckDate)
    }

    private static func loadStatuses() -> [String: LeakPeekIdentityStatus] {
        guard let data = UserDefaults.standard.data(forKey: Keys.statuses),
              let records = try? JSONDecoder().decode([LeakPeekIdentityStatus].self, from: data) else {
            return [:]
        }

        return Dictionary(uniqueKeysWithValues: records.map { ($0.email, $0) })
    }

    private func persistDismissedBreaches() {
        let records = Array(dismissedBreaches)
        guard let data = try? encoder.encode(records) else { return }
        UserDefaults.standard.set(data, forKey: Keys.dismissedBreaches)
    }

    private static func loadDismissedBreaches() -> Set<LeakPeekDismissedBreach> {
        guard let data = UserDefaults.standard.data(forKey: Keys.dismissedBreaches),
              let records = try? JSONDecoder().decode([LeakPeekDismissedBreach].self, from: data) else {
            return []
        }
        return Set(records)
    }
}
