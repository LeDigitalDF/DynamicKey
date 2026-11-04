// TrustedKeyboard.swift
// Persisted record for an approved physical keyboard used in context trust checks.
// Flow: user adds current device fingerprint → stored in TrustContextStore → matched at unlock.

import Foundation

struct TrustedKeyboard: Codable, Identifiable, Equatable {
    let id: UUID
    let fingerprint: String
    let displayName: String
    let addedAt: Date

    init(id: UUID = UUID(), fingerprint: String, displayName: String, addedAt: Date = Date()) {
        self.id = id
        self.fingerprint = fingerprint
        self.displayName = displayName
        self.addedAt = addedAt
    }
}
