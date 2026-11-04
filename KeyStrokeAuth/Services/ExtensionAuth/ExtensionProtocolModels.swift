// ExtensionProtocolModels.swift
// Codable request and response types for the extension auth protocol (M5).
//
// Flow: versioned JSON bodies on POST; GET status is unauthenticated health check.

import Foundation

// MARK: - Shared

struct ExtensionAPIErrorResponse: Codable, Equatable {
    let protocolVersion: Int
    let error: String
    let message: String
}

enum ExtensionDenialReason: String, Codable, Equatable {
    case wrongPassword
    case rhythmMismatch
    case emptyInput
    case lockedOut
    case untrustedContext
}

// MARK: - Status

struct ExtensionStatusResponse: Codable, Equatable {
    let protocolVersion: Int
    let serviceState: String
    let hasProfile: Bool
    let passThreshold: Int
    let pairedClientCount: Int
    let lockoutActive: Bool
    let serviceUptimeSeconds: Int
    /// Last Mac or extension rhythm verification (from audit log), ISO8601 when present.
    let lastVerifiedAt: Date?
    /// Bumps when DynamicShield trusted senders change — extension uses this to pull list sync.
    let dynamicShieldTrustedRevision: Int
    /// When true, extension may offer Touch ID instead of rhythm for verify (24-hour Safe Mode).
    let safeModeActive: Bool
    /// ISO8601 end time for Safe Mode when active.
    let safeModeExpiresAt: Date?
    /// Live countdown label shared with the Mac app (e.g. "23:59:12").
    let safeModeRemainingLabel: String?
}

// MARK: - Pair

struct ExtensionPairRequest: Codable, Equatable {
    let protocolVersion: Int
    let pairingCode: String
    let clientName: String?
    let browserFamily: String?
}

struct ExtensionPairResponse: Codable, Equatable {
    let protocolVersion: Int
    let accessToken: String
    let clientId: String
    let clientName: String?
}

// MARK: - Verify

struct ExtensionVerifyRequest: Codable, Equatable {
    let protocolVersion: Int
    let requestId: String
    let origin: String
    let password: String
    let keystrokes: [KeystrokeData]
    /// Username typed on the page form, used when auto-generating site credentials (W3.5).
    let username: String?
    /// Website form intent: login, signup, or changePassword (W4.3).
    let formIntent: String?
}

struct ExtensionVerifyResponse: Codable, Equatable {
    let protocolVersion: Int
    let requestId: String
    let granted: Bool
    let matchPercentage: Int
    let denialReason: ExtensionDenialReason?
    let lockoutRemainingSeconds: Int?
    /// Whether a site credential exists (or was created) for this origin after grant (W3.5).
    let siteCredentialReady: Bool?
    /// True when this verify created a new generated site password (W3.5).
    let credentialCreated: Bool?
    /// True when login was granted but no site credential exists on the Mac (W4.3).
    let missingSiteCredential: Bool?
}

// MARK: - Fill approve

struct ExtensionFillApproveRequest: Codable, Equatable {
    let protocolVersion: Int
    let requestId: String
    let origin: String
    let verificationRequestId: String
    /// Fallback username for auto-provision if verify did not include one (W3.5).
    let username: String?
    /// Website form intent captured by the extension (W4.3).
    let formIntent: String?
    /// When true, replace the stored site password during fill (real reset/change forms only).
    let rotateSitePassword: Bool?
}

struct ExtensionFillApproveResponse: Codable, Equatable {
    let protocolVersion: Int
    let requestId: String
    let approved: Bool
    let expiresAt: Date?
    let message: String?
    let credentials: ExtensionFillCredentials?
}

struct ExtensionFillCredentials: Codable, Equatable {
    let username: String
    /// New site password (signup, login reuse, or change-password new field).
    let password: String
    /// Existing site password for change-password "current" fields (LeakPeek Fix It).
    let currentPassword: String?

    init(username: String, password: String, currentPassword: String? = nil) {
        self.username = username
        self.password = password
        self.currentPassword = currentPassword
    }
}

// MARK: - Reset lockout (testing)

struct ExtensionResetLockoutResponse: Codable, Equatable {
    let protocolVersion: Int
    let cleared: Bool
}

// MARK: - Safe Mode

struct ExtensionSafeModeResponse: Codable, Equatable {
    let protocolVersion: Int
    let active: Bool
    let expiresAt: Date?
    let remainingSeconds: Int?
    let formattedRemainingTime: String?
}

// MARK: - Allowlist (W4.2)

struct ExtensionAllowlistCheckRequest: Codable, Equatable {
    let protocolVersion: Int
    let origin: String
}

struct ExtensionAllowlistCheckResponse: Codable, Equatable {
    let protocolVersion: Int
    let origin: String
    let normalizedOrigin: String
    let allowed: Bool
    /// True when the Mac app has a non-empty allowlist (restrict mode).
    let allowlistActive: Bool
}

struct ExtensionAllowlistAddRequest: Codable, Equatable {
    let protocolVersion: Int
    let origin: String
}

struct ExtensionAllowlistAddResponse: Codable, Equatable {
    let protocolVersion: Int
    let added: Bool
    let normalizedOrigin: String
    let message: String?
}

struct ExtensionAllowlistIgnoreRequest: Codable, Equatable {
    let protocolVersion: Int
    let origin: String
}

struct ExtensionAllowlistIgnoreResponse: Codable, Equatable {
    let protocolVersion: Int
    let ignored: Bool
    let normalizedOrigin: String
}

// MARK: - DynamicShield trusted senders

struct ExtensionDynamicShieldTrustRequest: Codable, Equatable {
    let protocolVersion: Int
    let senderDomain: String
}

struct ExtensionDynamicShieldTrustResponse: Codable, Equatable {
    let protocolVersion: Int
    let added: Bool
    let normalizedSenderDomain: String
    let message: String?
}

struct ExtensionDynamicShieldListRequest: Codable, Equatable {
    let protocolVersion: Int
}

struct ExtensionDynamicShieldListResponse: Codable, Equatable {
    let protocolVersion: Int
    let trustedSenderDomains: [String]
}

struct ExtensionDynamicShieldEventRequest: Codable, Equatable {
    let protocolVersion: Int
    let event: String
    let senderDomain: String?
    let flagSummary: String?
}

struct ExtensionDynamicShieldEventResponse: Codable, Equatable {
    let protocolVersion: Int
    let logged: Bool
}

// MARK: - Credential check (popup dashboard)

struct ExtensionCredentialCheckRequest: Codable, Equatable {
    let protocolVersion: Int
    let origin: String
}

struct ExtensionCredentialCheckResponse: Codable, Equatable {
    let protocolVersion: Int
    let origin: String
    let normalizedOrigin: String
    let hasCredential: Bool
    let displayHost: String
}

// MARK: - Open Mac app flow

struct ExtensionOpenAppRequest: Codable, Equatable {
    let protocolVersion: Int
    let intent: String
}

struct ExtensionOpenAppResponse: Codable, Equatable {
    let protocolVersion: Int
    let opened: Bool
    let intent: String
}

// MARK: - Pairing persistence

struct PendingPairingCode: Codable, Equatable {
    let code: String
    let expiresAt: Date
}

struct PairedExtensionClient: Codable, Equatable, Identifiable {
    let id: String
    let accessToken: String
    let clientName: String?
    let browserFamily: String?
    let pairedAt: Date
}

// MARK: - Mapping helpers

extension ExtensionDenialReason {
    /// Maps internal denial reasons to API-safe enum values.
    static func from(_ reason: DenialReason?) -> ExtensionDenialReason? {
        guard let reason else { return nil }
        switch reason {
        case .wrongPassword: return .wrongPassword
        case .rhythmMismatch: return .rhythmMismatch
        case .emptyInput: return .emptyInput
        case .lockedOut: return .lockedOut
        case .untrustedKeyboard, .untrustedNetwork: return .untrustedContext
        }
    }
}

extension ExtensionVerifyResponse {
    /// Builds a verify response from the Mac app login engine.
    static func from(
        requestId: String,
        result: LoginVerificationResult,
        siteCredentialReady: Bool? = nil,
        credentialCreated: Bool? = nil,
        missingSiteCredential: Bool? = nil
    ) -> ExtensionVerifyResponse {
        let lockoutSeconds: Int?
        if case .lockedOut(let remaining) = result.denialReason {
            lockoutSeconds = remaining
        } else {
            lockoutSeconds = nil
        }

        return ExtensionVerifyResponse(
            protocolVersion: ExtensionAuthConfig.protocolVersion,
            requestId: requestId,
            granted: result.granted,
            matchPercentage: result.matchPercentage,
            denialReason: ExtensionDenialReason.from(result.denialReason),
            lockoutRemainingSeconds: lockoutSeconds,
            siteCredentialReady: siteCredentialReady,
            credentialCreated: credentialCreated,
            missingSiteCredential: missingSiteCredential
        )
    }
}
