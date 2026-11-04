// LeakPeekScanResult.swift
// Per-credential breach scan status for LeakPeek (Have I Been Pwned k-anonymity).
// Flow: scan stores compromised flag per credential id → UI shows Safe or Compromised badges.

import Foundation

enum LeakPeekSiteStatus: Equatable {
    case unknown
    case safe
    case compromised
}

struct LeakPeekCredentialStatus: Codable, Equatable {
    let credentialID: UUID
    let isCompromised: Bool
    let checkedAt: Date

    var siteStatus: LeakPeekSiteStatus {
        isCompromised ? .compromised : .safe
    }
}
