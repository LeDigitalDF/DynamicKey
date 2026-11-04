// CredentialStore.swift
// Keychain-backed per-origin website credentials for extension autofill (W3.1 / W3.5).
//
// Flow: auto-provisioned on rhythm grant, or saved manually in Settings for import/testing.

import Foundation

enum CredentialStoreError: Error, LocalizedError {
    case saveFailed(Error)
    case notFound

    var errorDescription: String? {
        switch self {
        case .saveFailed(let error):
            return "Could not save site credential: \(error.localizedDescription)"
        case .notFound:
            return "No saved credential for this website."
        }
    }
}

final class CredentialStore {
    static let shared = CredentialStore()

    private let keychain = KeychainService(account: "site.credentials")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    /// All saved site credentials.
    func credentials() -> [SiteCredential] {
        guard let data = keychain.load(),
              let decoded = try? decoder.decode([SiteCredential].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.origin < $1.origin }
    }

    /// Returns the credential for a page origin, matching subdomains of the same site.
    func credential(forOrigin origin: String) -> SiteCredential? {
        let all = credentials()
        for key in SiteCredential.equivalentOrigins(for: origin) {
            if let match = all.first(where: { $0.origin == key }) {
                return match
            }
        }
        if let match = all.first(where: { SiteCredential.sameSiteGroup($0.origin, origin) }) {
            return match
        }
        return all.first { sharesGoogleSignInGroup($0.origin, origin) }
    }

    /// Google sign-in spans google.com, gmail.com, and related hosts (e.g. mail.google.com ↔ gmail.com entry).
    private func sharesGoogleSignInGroup(_ lhs: String, _ rhs: String) -> Bool {
        let googleDomains: Set = ["google.com", "gmail.com", "googlemail.com"]
        guard let left = registrableDomain(fromOrigin: lhs),
              let right = registrableDomain(fromOrigin: rhs) else {
            return false
        }
        return googleDomains.contains(left) && googleDomains.contains(right)
    }

    private func registrableDomain(fromOrigin origin: String) -> String? {
        let normalized = SiteCredential.normalizeOrigin(origin)
        guard let host = URL(string: normalized)?.host else { return nil }
        return SiteCredential.registrableDomain(from: host)
    }

    /// Inserts or replaces the credential for the same site group.
    func save(_ credential: SiteCredential) throws {
        let storageOrigin = SiteCredential.storageKey(for: credential.origin)
        let existing = credentials().first { SiteCredential.sameSiteGroup($0.origin, storageOrigin) }

        let stored = SiteCredential(
            id: credential.id,
            origin: storageOrigin,
            username: credential.username,
            password: credential.password,
            createdAt: credential.createdAt,
            isGenerated: credential.isGenerated
        )

        var all = credentials().filter { !SiteCredential.sameSiteGroup($0.origin, storageOrigin) }
        all.append(stored)
        try persist(all)

        if existing?.password != stored.password {
            notifyLeakPeekPasswordChanged(credentialID: stored.id)
        }

        NotificationCenter.default.post(name: .siteCredentialsDidChange, object: nil)
    }

    /// Removes a credential by id.
    func delete(id: UUID) throws {
        let all = credentials().filter { $0.id != id }
        try persist(all)
        NotificationCenter.default.post(name: .siteCredentialsDidChange, object: nil)
    }

    /// Replaces the site password with a new generated secret and marks the entry as generated (W3.5).
    func regeneratePassword(id: UUID) throws -> SiteCredential {
        var all = credentials()
        guard let index = all.firstIndex(where: { $0.id == id }) else {
            throw CredentialStoreError.notFound
        }

        let existing = all[index]
        let updated = SiteCredential(
            id: existing.id,
            origin: existing.origin,
            username: existing.username,
            password: SitePasswordGenerator.generate(),
            createdAt: existing.createdAt,
            isGenerated: true
        )
        all[index] = updated
        try persist(all)
        notifyLeakPeekPasswordChanged(credentialID: updated.id)
        NotificationCenter.default.post(name: .siteCredentialsDidChange, object: nil)
        return updated
    }

    /// Removes every saved site credential.
    func deleteAll() throws {
        try keychain.delete()
        NotificationCenter.default.post(name: .siteCredentialsDidChange, object: nil)
    }

    private func notifyLeakPeekPasswordChanged(credentialID: UUID) {
        Task { @MainActor in
            LeakPeekStore.shared.clearStatus(for: credentialID)
        }
    }

    private func persist(_ credentials: [SiteCredential]) throws {
        do {
            let data = try encoder.encode(credentials)
            try keychain.save(data: data)
        } catch {
            throw CredentialStoreError.saveFailed(error)
        }
    }
}
