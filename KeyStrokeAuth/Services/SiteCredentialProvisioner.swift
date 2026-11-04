// SiteCredentialProvisioner.swift
// Creates or reuses per-origin site credentials based on form intent (W3.5 / W4.3).
//
// Flow: login → reuse only; signup → generate if missing; changePassword → reuse or generate when resetting without a stored password.

import Foundation

struct SiteCredentialProvisionResult: Equatable {
    let credential: SiteCredential
    let created: Bool
}

enum SiteCredentialProvisionerError: Error, LocalizedError {
    case saveFailed(Error)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let error):
            return "Could not save generated site credential: \(error.localizedDescription)"
        }
    }
}

final class SiteCredentialProvisioner {
    static let shared = SiteCredentialProvisioner()

    private let credentialStore = CredentialStore.shared

    private init() {}

    /// Applies credential policy for the given website form intent after rhythm grant.
    func prepareCredential(
        forOrigin origin: String,
        username: String?,
        intent: SiteFormIntent
    ) throws -> SiteCredentialProvisionResult? {
        switch intent {
        case .login:
            return try reuseExisting(forOrigin: origin, username: username)
        case .signup:
            return try generateForSignup(forOrigin: origin, username: username)
        case .changePassword:
            if let existing = try reuseExisting(forOrigin: origin, username: username) {
                return existing
            }
            // Password-reset flows may have no stored site password (user forgot it or removed the credential).
            return try generateForSignup(forOrigin: origin, username: username)
        }
    }

    /// Change-password autofill: keep the stored password for the current field, generate a new one for new/confirm fields.
    func regenerateForPasswordChangeAtFill(
        forOrigin origin: String,
        username: String?
    ) throws -> SiteCredentialProvisionResult? {
        let normalizedOrigin = SiteCredential.normalizeOrigin(origin)
        let trimmedUsername = username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard let existing = credentialStore.credential(forOrigin: normalizedOrigin) else {
            return nil
        }

        let resolvedUsername = trimmedUsername.isEmpty ? existing.username : trimmedUsername
        let updated = SiteCredential(
            id: existing.id,
            origin: existing.origin,
            username: resolvedUsername,
            password: SitePasswordGenerator.generate(),
            createdAt: existing.createdAt,
            isGenerated: true
        )
        try credentialStore.save(updated)
        return SiteCredentialProvisionResult(credential: updated, created: true)
    }

    /// Returns the stored site password before a change-password fill replaces it on the Mac.
    func storedPassword(forOrigin origin: String) -> String? {
        credentialStore.credential(forOrigin: SiteCredential.normalizeOrigin(origin))?.password
    }

    /// Login: returns stored credential only; never generates a new site password.
    private func reuseExisting(forOrigin origin: String, username: String?) throws -> SiteCredentialProvisionResult? {
        let normalizedOrigin = SiteCredential.normalizeOrigin(origin)
        let trimmedUsername = username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard let existing = credentialStore.credential(forOrigin: normalizedOrigin) else {
            return nil
        }

        if existing.username.isEmpty, !trimmedUsername.isEmpty {
            let updated = SiteCredential(
                id: existing.id,
                origin: existing.origin,
                username: trimmedUsername,
                password: existing.password,
                createdAt: existing.createdAt,
                isGenerated: existing.isGenerated
            )
            try credentialStore.save(updated)
            return SiteCredentialProvisionResult(credential: updated, created: false)
        }

        if !trimmedUsername.isEmpty,
           Self.isEmail(trimmedUsername),
           !Self.isEmail(existing.username) {
            let updated = SiteCredential(
                id: existing.id,
                origin: existing.origin,
                username: trimmedUsername,
                password: existing.password,
                createdAt: existing.createdAt,
                isGenerated: existing.isGenerated
            )
            try credentialStore.save(updated)
            return SiteCredentialProvisionResult(credential: updated, created: false)
        }

        return SiteCredentialProvisionResult(credential: existing, created: false)
    }

    private static func isEmail(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let atIndex = trimmed.firstIndex(of: "@"),
              trimmed.distance(from: atIndex, to: trimmed.endIndex) > 1 else {
            return false
        }
        let domain = trimmed[trimmed.index(after: atIndex)...]
        return domain.contains(".")
    }

    /// Sign up: generates a site password only when none exists for this origin.
    private func generateForSignup(forOrigin origin: String, username: String?) throws -> SiteCredentialProvisionResult {
        if let existing = try reuseExisting(forOrigin: origin, username: username) {
            return existing
        }

        return try saveGenerated(origin: origin, username: username)
    }

    private func saveGenerated(origin: String, username: String?) throws -> SiteCredentialProvisionResult {
        let trimmedUsername = username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let generated = SiteCredential(
            origin: origin,
            username: trimmedUsername,
            password: SitePasswordGenerator.generate(),
            isGenerated: true
        )

        do {
            try credentialStore.save(generated)
        } catch {
            throw SiteCredentialProvisionerError.saveFailed(error)
        }

        return SiteCredentialProvisionResult(credential: generated, created: true)
    }
}
