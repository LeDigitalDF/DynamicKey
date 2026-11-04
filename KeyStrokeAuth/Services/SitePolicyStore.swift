// SitePolicyStore.swift
// User-controlled protected-site list for extension verify/autofill (W3.3).
//
// Flow: empty list = no protected sites (extension stays off); listed + enabled origins may verify/autofill.

import Foundation

final class SitePolicyStore {
    static let shared = SitePolicyStore()

    private let storageKey = "LeDigital.KeyStrokeAuth.allowedOrigins"
    private let disabledStorageKey = "LeDigital.KeyStrokeAuth.allowlistDisabledOrigins"
    private let addedDatesStorageKey = "LeDigital.KeyStrokeAuth.allowlistAddedDates"

    private init() {}

    /// Origins the user explicitly protects. Empty means the extension stays off for every site.
    func allowedOrigins() -> [String] {
        guard let stored = UserDefaults.standard.stringArray(forKey: storageKey) else {
            return []
        }
        return stored.map { SiteCredential.normalizeOrigin($0) }.sorted()
    }

    /// Origins on the list that the user has toggled off (red dot) while keeping the row.
    func disabledOrigins() -> [String] {
        guard let stored = UserDefaults.standard.stringArray(forKey: disabledStorageKey) else {
            return []
        }
        return stored.map { SiteCredential.normalizeOrigin($0) }.sorted()
    }

    /// Whether a listed origin is actively allowed (green) vs paused (red).
    func isOriginEnabled(_ origin: String) -> Bool {
        let disabled = disabledOrigins()
        return !disabled.contains { SiteCredential.sameSiteGroup($0, origin) }
    }

    /// When the origin was added to the allowlist, if recorded.
    func allowedAt(for origin: String) -> Date? {
        let dates = loadAddedDates()
        let key = SiteCredential.storageKey(for: origin)

        if let interval = dates[key] ?? dates[origin] {
            return Date(timeIntervalSince1970: interval)
        }
        if let match = dates.first(where: { SiteCredential.sameSiteGroup($0.key, key) }) {
            return Date(timeIntervalSince1970: match.value)
        }

        guard allowedOrigins().contains(where: { SiteCredential.sameSiteGroup($0, origin) }) else {
            return nil
        }

        saveAddedDate(for: key)
        return Date(timeIntervalSince1970: loadAddedDates()[key] ?? Date().timeIntervalSince1970)
    }

    /// Replaces the protected websites list. Pass an empty array when none are protected.
    func setAllowedOrigins(_ origins: [String]) {
        let normalized = origins
            .map { SiteCredential.normalizeOrigin($0) }
            .filter { !$0.isEmpty }
        UserDefaults.standard.set(normalized, forKey: storageKey)
        pruneAddedDates(keeping: normalized)
        NotificationCenter.default.post(name: .sitePolicyDidChange, object: nil)
    }

    /// Adds one origin to the allowlist if its site group is not already present.
    func addAllowedOrigin(_ origin: String) {
        let key = SiteCredential.storageKey(for: origin)
        guard !key.isEmpty else { return }
        var current = allowedOrigins()
        guard !current.contains(where: { SiteCredential.sameSiteGroup($0, key) }) else { return }
        current.append(key)
        saveAddedDate(for: key)
        setAllowedOrigins(current)
    }

    /// Removes one origin and any entries in the same site group.
    func removeAllowedOrigin(_ origin: String) {
        setAllowedOrigins(allowedOrigins().filter { !SiteCredential.sameSiteGroup($0, origin) })
        clearDisabledState(for: origin)
        removeAddedDate(for: origin)
    }

    /// Toggles whether a listed origin is actively allowed (green) or paused (red).
    func setOriginEnabled(_ origin: String, enabled: Bool) {
        let key = SiteCredential.storageKey(for: origin)
        guard !key.isEmpty else { return }

        var disabled = disabledOrigins()
        if enabled {
            disabled.removeAll { SiteCredential.sameSiteGroup($0, key) }
        } else if !disabled.contains(where: { SiteCredential.sameSiteGroup($0, key) }) {
            disabled.append(key)
        }

        UserDefaults.standard.set(disabled, forKey: disabledStorageKey)
        NotificationCenter.default.post(name: .sitePolicyDidChange, object: nil)
    }

    private func clearDisabledState(for origin: String) {
        var disabled = disabledOrigins()
        disabled.removeAll { SiteCredential.sameSiteGroup($0, origin) }
        UserDefaults.standard.set(disabled, forKey: disabledStorageKey)
    }

    /// Returns whether verify/autofill is permitted for the given page origin.
    /// Opt-in model: the site must appear on the protected list and be enabled (green dot).
    func isOriginAllowed(_ origin: String) -> Bool {
        if disabledOrigins().contains(where: { SiteCredential.sameSiteGroup($0, origin) }) {
            return false
        }

        let allowed = allowedOrigins()
        guard !allowed.isEmpty else { return false }
        return allowed.contains(where: { SiteCredential.sameSiteGroup($0, origin) })
    }

    /// Adds an origin to the allowlist and marks it not allowed (red dot) for extension dismiss.
    func ignoreOrigin(_ origin: String) {
        addAllowedOrigin(origin)
        setOriginEnabled(origin, enabled: false)
    }

    private func loadAddedDates() -> [String: Double] {
        UserDefaults.standard.dictionary(forKey: addedDatesStorageKey) as? [String: Double] ?? [:]
    }

    private func saveAddedDate(for origin: String) {
        var dates = loadAddedDates()
        dates[origin] = Date().timeIntervalSince1970
        UserDefaults.standard.set(dates, forKey: addedDatesStorageKey)
    }

    private func removeAddedDate(for origin: String) {
        var dates = loadAddedDates()
        dates = dates.filter { !SiteCredential.sameSiteGroup($0.key, origin) }
        UserDefaults.standard.set(dates, forKey: addedDatesStorageKey)
    }

    private func pruneAddedDates(keeping origins: [String]) {
        var dates = loadAddedDates()
        dates = dates.filter { entry in
            origins.contains { SiteCredential.sameSiteGroup($0, entry.key) }
        }
        UserDefaults.standard.set(dates, forKey: addedDatesStorageKey)
    }
}
