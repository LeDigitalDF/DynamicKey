// ExtensionAuthConfig.swift
// Fixed constants for the localhost extension auth API (M5).
//
// Flow: browser extension talks to 127.0.0.1 only; Mac app is the verifier.

import Foundation

enum ExtensionAuthConfig {
    /// Current protocol version shared by Mac app and browser extension.
    static let protocolVersion = 1

    /// Loopback-only port for the local auth HTTP server.
    static let port: UInt16 = 17_487

    /// Base URL extensions use when the Mac app is running.
    static var baseURL: String {
        "http://127.0.0.1:\(port)"
    }

    /// Pairing codes expire after this many seconds if unused.
    static let pairingCodeLifetimeSeconds: TimeInterval = 600

    /// Successful verify approvals remain valid for fill-approve this long.
    static let fillApprovalLifetimeSeconds: TimeInterval = 60

    /// API route paths (versioned).
    enum Route {
        static let status = "/v1/status"
        static let pair = "/v1/pair"
        static let verify = "/v1/verify"
        static let fillApprove = "/v1/fill-approve"
        static let resetLockout = "/v1/reset-lockout"
        static let allowlistCheck = "/v1/allowlist/check"
        static let allowlistAdd = "/v1/allowlist/add"
        static let allowlistIgnore = "/v1/allowlist/ignore"
        static let dynamicShieldTrust = "/v1/dynamic-shield/trust"
        static let dynamicShieldList = "/v1/dynamic-shield/list"
        static let dynamicShieldEvent = "/v1/dynamic-shield/event"
        static let credentialsCheck = "/v1/credentials/check"
        static let openApp = "/v1/app/open"
        static let safeModeActivate = "/v1/safe-mode/activate"
        static let safeModeDeactivate = "/v1/safe-mode/deactivate"
    }
}
