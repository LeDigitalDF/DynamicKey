// SiteFormIntent.swift
// Extension-reported website form intent for credential generation policy (W4.3).
//
// Flow: signup/changePassword may generate site passwords; login reuses stored credentials only.

import Foundation

enum SiteFormIntent: String, Codable, Equatable {
    case login
    case signup
    case changePassword

    /// Parses extension payload; defaults to login when missing or unknown.
    static func from(_ raw: String?) -> SiteFormIntent {
        guard let raw else { return .login }
        return SiteFormIntent(rawValue: raw) ?? .login
    }
}
