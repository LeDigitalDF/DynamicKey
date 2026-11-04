// LeakPeekIdentityModels.swift
// Models for email / identity breach checks (LeakPeek v2-lite).
// Flow: collect emails from credentials → remote lookup → persist Safe / Compromised per address.

import CoreGraphics
import Foundation

/// UI phase for the fullscreen breach-check overlay.
enum LeakPeekBreachCheckPhase: Equatable {
    case idle
    case running
    case finished(LeakPeekBreachCheckSummary)
    case failed(String)
}

/// Aggregated outcome shown when an identity breach scan completes.
struct LeakPeekBreachCheckSummary: Equatable {
    let results: [LeakPeekIdentityStatus]
    let checkedAt: Date

    var compromisedCount: Int {
        results.filter(\.isCompromised).count
    }

    var safeCount: Int {
        results.filter { !$0.isCompromised }.count
    }

    var compromisedResults: [LeakPeekIdentityStatus] {
        results.filter(\.isCompromised)
    }
}

/// Persisted breach status for one monitored email address.
struct LeakPeekIdentityStatus: Codable, Equatable, Identifiable {
    let email: String
    let isCompromised: Bool
    let breachNames: [String]
    let checkedAt: Date

    var id: String { email }

    var displayStatus: LeakPeekIdentityDisplayStatus {
        isCompromised ? .compromised : .safe
    }
}

/// A single dot on the sonar radar — angle and distance are fixed; state updates as checks complete.
struct LeakPeekRadarBlip: Identifiable, Equatable {
    let id: String
    let angle: Double
    let distance: CGFloat
    var isChecked: Bool
    var isCompromised: Bool

    /// Places blips evenly around the radar for each email being scanned.
    static func layout(for emails: [String]) -> [LeakPeekRadarBlip] {
        guard !emails.isEmpty else { return [] }

        return emails.enumerated().map { index, email in
            let normalized = LeakPeekEmailValidator.normalized(email)
            let angle = (Double(index) / Double(emails.count)) * (2 * .pi) - (.pi / 2)
            let ring = CGFloat(index % 3)
            let distance = 0.34 + ring * 0.17

            return LeakPeekRadarBlip(
                id: normalized,
                angle: angle,
                distance: distance,
                isChecked: false,
                isCompromised: false
            )
        }
    }
}

/// User-dismissed breach row — email + service name (e.g. LinkedIn 2012 already fixed).
struct LeakPeekDismissedBreach: Codable, Equatable, Hashable {
    let email: String
    let breachName: String
}

enum LeakPeekIdentityDisplayStatus: Equatable {
    case unknown
    case safe
    case compromised
}

enum LeakPeekEmailValidator {
    /// Returns true when the username looks like an email we can check.
    static func isEmail(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 5, trimmed.count <= 254 else { return false }

        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2,
              !parts[0].isEmpty,
              parts[1].contains(".") else {
            return false
        }

        return trimmed.range(
            of: #"^[A-Z0-9a-z._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#,
            options: .regularExpression
        ) != nil
    }

    /// Normalizes an email for deduplication and storage keys.
    static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Unique email addresses from saved credential usernames.
    static func uniqueEmails(from credentials: [SiteCredential]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for credential in credentials {
            let username = credential.username.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isEmail(username) else { continue }

            let key = normalized(username)
            guard seen.insert(key).inserted else { continue }
            ordered.append(username)
        }

        return ordered
    }
}
