// DynamicShieldPolicyStore.swift
// Trusted email sender domains for DynamicShield — extension sync lands here later.
//
// Flow: empty list = scan all senders; green = trusted; red = trust paused (scan again).

import Foundation

final class DynamicShieldPolicyStore {
    static let shared = DynamicShieldPolicyStore()

    private let storageKey = "LeDigital.KeyStrokeAuth.dynamicShieldTrustedDomains"
    private let disabledStorageKey = "LeDigital.KeyStrokeAuth.dynamicShieldDisabledDomains"
    private let addedDatesStorageKey = "LeDigital.KeyStrokeAuth.dynamicShieldAddedDates"
    private let revisionStorageKey = "LeDigital.KeyStrokeAuth.dynamicShieldPolicyRevision"

    private init() {}

    /// Monotonic revision bumped whenever trusted senders change — extension polls via status.
    func trustedPolicyRevision() -> Int {
        UserDefaults.standard.integer(forKey: revisionStorageKey)
    }

    /// Sender domains the user marked as safe (e.g. via extension "This is Safe").
    func trustedSenderDomains() -> [String] {
        guard let stored = UserDefaults.standard.stringArray(forKey: storageKey) else {
            return []
        }
        return stored.map(Self.normalizeSenderDomain).filter { !$0.isEmpty }.sorted()
    }

    /// Domains on the list that the user paused (red dot) while keeping the row.
    func disabledSenderDomains() -> [String] {
        guard let stored = UserDefaults.standard.stringArray(forKey: disabledStorageKey) else {
            return []
        }
        return stored.map(Self.normalizeSenderDomain).filter { !$0.isEmpty }.sorted()
    }

    /// Whether a listed sender domain is actively trusted (green) vs paused (red).
    func isSenderDomainEnabled(_ domain: String) -> Bool {
        let key = Self.normalizeSenderDomain(domain)
        guard !key.isEmpty else { return false }
        return !disabledSenderDomains().contains { Self.sameSenderDomain($0, key) }
    }

    /// When the sender domain was trusted, if recorded.
    func trustedAt(for domain: String) -> Date? {
        let key = Self.normalizeSenderDomain(domain)
        guard !key.isEmpty else { return nil }

        let dates = loadAddedDates()
        if let interval = dates[key] {
            return Date(timeIntervalSince1970: interval)
        }
        if let match = dates.first(where: { Self.sameSenderDomain($0.key, key) }) {
            return Date(timeIntervalSince1970: match.value)
        }

        guard trustedSenderDomains().contains(where: { Self.sameSenderDomain($0, key) }) else {
            return nil
        }

        saveAddedDate(for: key)
        return Date(timeIntervalSince1970: loadAddedDates()[key] ?? Date().timeIntervalSince1970)
    }

    /// Adds one sender domain if it is not already on the list.
    func addTrustedSenderDomain(_ domain: String) {
        let key = Self.normalizeSenderDomain(domain)
        guard !key.isEmpty else { return }

        var current = trustedSenderDomains()
        guard !current.contains(where: { Self.sameSenderDomain($0, key) }) else { return }

        current.append(key)
        saveAddedDate(for: key)
        setTrustedSenderDomains(current)
    }

    /// Removes one sender domain from the trusted list.
    func removeTrustedSenderDomain(_ domain: String) {
        let key = Self.normalizeSenderDomain(domain)
        guard !key.isEmpty else { return }

        setTrustedSenderDomains(
            trustedSenderDomains().filter { !Self.sameSenderDomain($0, key) }
        )
        clearDisabledState(for: key)
        removeAddedDate(for: key)
    }

    /// Toggles whether a listed sender is actively trusted (green) or paused (red).
    func setSenderDomainEnabled(_ domain: String, enabled: Bool) {
        let key = Self.normalizeSenderDomain(domain)
        guard !key.isEmpty else { return }

        var disabled = disabledSenderDomains()
        if enabled {
            disabled.removeAll { Self.sameSenderDomain($0, key) }
        } else if !disabled.contains(where: { Self.sameSenderDomain($0, key) }) {
            disabled.append(key)
        }

        UserDefaults.standard.set(disabled, forKey: disabledStorageKey)
        notifyPolicyDidChange()
    }

    /// Whether DynamicShield should skip phishing checks for this sender domain.
    func isSenderDomainTrusted(_ domain: String) -> Bool {
        let key = Self.normalizeSenderDomain(domain)
        guard !key.isEmpty else { return false }

        if disabledSenderDomains().contains(where: { Self.sameSenderDomain($0, key) }) {
            return false
        }

        return trustedSenderDomains().contains(where: { Self.sameSenderDomain($0, key) })
    }

    private func setTrustedSenderDomains(_ domains: [String]) {
        let normalized = domains
            .map(Self.normalizeSenderDomain)
            .filter { !$0.isEmpty }
        UserDefaults.standard.set(normalized, forKey: storageKey)
        pruneAddedDates(keeping: normalized)
        notifyPolicyDidChange()
    }

    private func notifyPolicyDidChange() {
        bumpTrustedPolicyRevision()
        if Thread.isMainThread {
            NotificationCenter.default.post(name: .dynamicShieldPolicyDidChange, object: nil)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .dynamicShieldPolicyDidChange, object: nil)
            }
        }
    }

    private func bumpTrustedPolicyRevision() {
        let next = trustedPolicyRevision() + 1
        UserDefaults.standard.set(next, forKey: revisionStorageKey)
    }

    private func clearDisabledState(for domain: String) {
        var disabled = disabledSenderDomains()
        disabled.removeAll { Self.sameSenderDomain($0, domain) }
        UserDefaults.standard.set(disabled, forKey: disabledStorageKey)
    }

    private func loadAddedDates() -> [String: Double] {
        UserDefaults.standard.dictionary(forKey: addedDatesStorageKey) as? [String: Double] ?? [:]
    }

    private func saveAddedDate(for domain: String) {
        var dates = loadAddedDates()
        dates[domain] = Date().timeIntervalSince1970
        UserDefaults.standard.set(dates, forKey: addedDatesStorageKey)
    }

    private func removeAddedDate(for domain: String) {
        var dates = loadAddedDates()
        dates = dates.filter { !Self.sameSenderDomain($0.key, domain) }
        UserDefaults.standard.set(dates, forKey: addedDatesStorageKey)
    }

    private func pruneAddedDates(keeping domains: [String]) {
        var dates = loadAddedDates()
        dates = dates.filter { entry in
            domains.contains { Self.sameSenderDomain($0, entry.key) }
        }
        UserDefaults.standard.set(dates, forKey: addedDatesStorageKey)
    }

    /// Normalizes `@company.com`, `user@company.com`, or `company.com` to `company.com`.
    static func normalizeSenderDomain(_ input: String) -> String {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("@") {
            value.removeFirst()
        }
        if let atIndex = value.lastIndex(of: "@") {
            value = String(value[value.index(after: atIndex)...])
        }
        return value
    }

    static func sameSenderDomain(_ lhs: String, _ rhs: String) -> Bool {
        normalizeSenderDomain(lhs) == normalizeSenderDomain(rhs)
    }
}
