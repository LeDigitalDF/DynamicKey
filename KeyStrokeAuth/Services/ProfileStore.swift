// ProfileStore.swift
// Loads, saves, and verifies the persisted user profile.

import Foundation

enum ProfileStoreError: Error, LocalizedError {
    case saveFailed(Error)
    case invalidRhythmProfile
    case wrongPassword
    case profileNotFound
    case newPasswordSameAsCurrent

    var errorDescription: String? {
        switch self {
        case .saveFailed(let error):
            return "Could not save profile: \(error.localizedDescription)"
        case .invalidRhythmProfile:
            return "Enrollment did not produce a valid rhythm profile."
        case .wrongPassword:
            return "The password is incorrect."
        case .profileNotFound:
            return "No saved profile was found."
        case .newPasswordSameAsCurrent:
            return "The new password must be different from your current password."
        }
    }
}

final class ProfileStore {
    static let shared = ProfileStore()

    private let keychain = KeychainService()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let attemptTracker = LoginAttemptTracker.shared
    private let auditLog = AuditLogService.shared

    var hasProfile: Bool {
        loadProfile() != nil
    }

    func loadProfile() -> StoredProfile? {
        guard let data = keychain.load() else { return nil }
        return try? decoder.decode(StoredProfile.self, from: data)
    }

    func saveProfile(password: String, rhythmProfile: RhythmProfile) throws {
        let salt = PasswordHasher.generateSalt()
        let hash = PasswordHasher.hash(password: password, salt: salt)
        let profile = StoredProfile(
            passwordSalt: salt,
            passwordHash: hash,
            rhythmProfile: rhythmProfile
        )

        do {
            let data = try encoder.encode(profile)
            try keychain.save(data: data)
            auditLog.append(AuditEvent(type: .profileCreated))
        } catch {
            throw ProfileStoreError.saveFailed(error)
        }
    }

    /// Replaces the master password hash and rhythm profile after the user verifies their current password in Settings.
    func changeMasterPassword(
        currentPassword: String,
        newPassword: String,
        rhythmProfile: RhythmProfile
    ) throws {
        guard let existingProfile = loadProfile() else {
            throw ProfileStoreError.profileNotFound
        }

        let currentValid = PasswordHasher.verify(
            password: currentPassword,
            salt: existingProfile.passwordSalt,
            expectedHash: existingProfile.passwordHash
        )
        guard currentValid else {
            throw ProfileStoreError.wrongPassword
        }

        guard currentPassword != newPassword else {
            throw ProfileStoreError.newPasswordSameAsCurrent
        }

        let salt = PasswordHasher.generateSalt()
        let hash = PasswordHasher.hash(password: newPassword, salt: salt)
        let updatedProfile = StoredProfile(
            passwordSalt: salt,
            passwordHash: hash,
            rhythmProfile: rhythmProfile
        )

        do {
            let data = try encoder.encode(updatedProfile)
            try keychain.save(data: data)
            auditLog.append(AuditEvent(type: .masterPasswordChanged))
        } catch {
            throw ProfileStoreError.saveFailed(error)
        }
    }

    func updateRhythmProfile(_ rhythmProfile: RhythmProfile, verifyingPassword password: String) throws {
        guard let existingProfile = loadProfile() else {
            throw ProfileStoreError.profileNotFound
        }

        let passwordValid = PasswordHasher.verify(
            password: password,
            salt: existingProfile.passwordSalt,
            expectedHash: existingProfile.passwordHash
        )
        guard passwordValid else {
            throw ProfileStoreError.wrongPassword
        }

        let updatedProfile = StoredProfile(
            passwordSalt: existingProfile.passwordSalt,
            passwordHash: existingProfile.passwordHash,
            rhythmProfile: rhythmProfile
        )

        do {
            let data = try encoder.encode(updatedProfile)
            try keychain.save(data: data)
            auditLog.append(AuditEvent(type: .profileUpdated))
        } catch {
            throw ProfileStoreError.saveFailed(error)
        }
    }

    /// Adaptive learning: folds a genuine, margin-passing login into the stored rhythm profile.
    /// Re-verifies the password for safety, updates in place, and saves quietly (no audit spam —
    /// each login already logs a `.loginSuccess` event). Returns true when the profile was refined.
    @discardableResult
    func refineRhythmProfile(password: String, loginData: [KeystrokeData]) -> Bool {
        guard let existingProfile = loadProfile() else { return false }

        let passwordValid = PasswordHasher.verify(
            password: password,
            salt: existingProfile.passwordSalt,
            expectedHash: existingProfile.passwordHash
        )
        guard passwordValid else { return false }

        guard let refined = existingProfile.rhythmProfile.learning(from: loginData) else { return false }

        let updatedProfile = StoredProfile(
            passwordSalt: existingProfile.passwordSalt,
            passwordHash: existingProfile.passwordHash,
            rhythmProfile: refined
        )

        guard let data = try? encoder.encode(updatedProfile) else { return false }
        do {
            try keychain.save(data: data)
            return true
        } catch {
            return false
        }
    }

    func verifyPassword(_ password: String) -> Bool {
        guard let profile = loadProfile() else { return false }
        return PasswordHasher.verify(
            password: password,
            salt: profile.passwordSalt,
            expectedHash: profile.passwordHash
        )
    }

    func verifyLogin(
        password: String,
        loginData: [KeystrokeData],
        enforceSecurity: Bool = true
    ) -> LoginVerificationResult {
        if enforceSecurity {
            let lockoutStatus = attemptTracker.status()
            if case .locked(let until) = lockoutStatus {
                let remaining = max(0, Int(ceil(until.timeIntervalSinceNow)))
                auditLog.append(
                    AuditEvent(
                        type: .loginBlockedLockout,
                        detail: "Remaining lockout: \(remaining)s"
                    )
                )
                return LoginVerificationResult(
                    granted: false,
                    matchPercentage: 0,
                    denialReason: .lockedOut(remainingSeconds: remaining)
                )
            }
        }

        guard !password.isEmpty, !loginData.isEmpty else {
            if enforceSecurity {
                auditLog.append(AuditEvent(type: .loginFailedEmpty))
            }
            return LoginVerificationResult(granted: false, matchPercentage: 0, denialReason: .emptyInput)
        }

        guard let profile = loadProfile() else {
            return LoginVerificationResult(granted: false, matchPercentage: 0, denialReason: .emptyInput)
        }

        let passwordValid = PasswordHasher.verify(
            password: password,
            salt: profile.passwordSalt,
            expectedHash: profile.passwordHash
        )
        guard passwordValid else {
            if enforceSecurity {
                attemptTracker.recordFailure()
                auditLog.append(AuditEvent(type: .loginFailedPassword))
            }
            return LoginVerificationResult(granted: false, matchPercentage: 0, denialReason: .wrongPassword)
        }

        let matchPercentage = RhythmVerifier.matchPercentage(
            loginData: loginData,
            password: password,
            profile: profile.rhythmProfile
        )
        guard matchPercentage >= RhythmVerifier.passThreshold else {
            if enforceSecurity {
                attemptTracker.recordFailure()
                auditLog.append(
                    AuditEvent(
                        type: .loginFailedRhythm,
                        detail: "Match: \(matchPercentage)%"
                    )
                )
            }
            return LoginVerificationResult(
                granted: false,
                matchPercentage: matchPercentage,
                denialReason: .rhythmMismatch
            )
        }

        if enforceSecurity {
            attemptTracker.recordSuccess()
            auditLog.append(
                AuditEvent(
                    type: .loginSuccess,
                    detail: "Match: \(matchPercentage)%"
                )
            )
        }

        return LoginVerificationResult(
            granted: true,
            matchPercentage: matchPercentage,
            denialReason: nil
        )
    }

    /// Grants login after Touch ID fallback when the password is already known to be correct.
    func grantLoginWithBiometricFallback(password: String, enforceSecurity: Bool = true) -> LoginVerificationResult? {
        guard !password.isEmpty else { return nil }
        guard verifyPassword(password) else { return nil }

        if enforceSecurity {
            attemptTracker.recordSuccess()
            auditLog.append(
                AuditEvent(
                    type: .loginSuccess,
                    detail: "Touch ID fallback"
                )
            )
        }

        return LoginVerificationResult(granted: true, matchPercentage: 0, denialReason: nil)
    }

    func deleteProfile() throws {
        try keychain.delete()
        attemptTracker.reset()
        auditLog.append(AuditEvent(type: .profileDeleted))
    }

    func resetLockout() {
        attemptTracker.reset()
        auditLog.append(AuditEvent(type: .lockoutCleared, detail: "Failed attempts and lockout timer cleared"))
    }

    func lockoutStatus(now: Date = Date()) -> LockoutStatus {
        attemptTracker.status(now: now)
    }
}
