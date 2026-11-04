// AccountProfile.swift
// SwiftData model for the user's DynamicKey profile (display name + metadata).
// Flow: created on first launch → synced across the user's Macs via CloudKit (when available) →
//       vault secrets (master password, rhythm, site passwords) are NEVER stored here.
//
// CloudKit compatibility (important): NSPersistentCloudKitContainer requires every stored property
// to be optional or have a default value, and forbids unique constraints. This model follows both
// rules so it can mirror to CloudKit without a schema migration when the capability is enabled.

import Foundation
import SwiftData

@Model
final class AccountProfile {
    // Stable identifier for this profile record (no `.unique` attribute — CloudKit disallows it).
    var id: UUID = UUID()

    // Human-facing name shown in the sidebar/account UI. Empty → UI falls back to a "DK######" name.
    var displayName: String = ""

    // When the profile was first created on any of the user's Macs.
    var createdAt: Date = Date()

    // All properties defaulted so CloudKit mirroring is satisfied.
    init(id: UUID = UUID(), displayName: String = "", createdAt: Date = Date()) {
        self.id = id
        self.displayName = displayName
        self.createdAt = createdAt
    }
}
