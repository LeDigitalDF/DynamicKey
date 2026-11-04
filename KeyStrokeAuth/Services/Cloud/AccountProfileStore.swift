// AccountProfileStore.swift
// Observable manager for the SwiftData AccountProfile (display name + iCloud sync availability).
// Flow: load-or-create the single profile record from the shared container → publish displayName →
//       persist edits (mirrored to CloudKit when available) → expose whether iCloud sync is on so
//       Settings can show a friendly "sync disabled" badge.
//
// Privacy: only non-secret profile fields live here. The master password, typing rhythm, and site
//          passwords stay in Keychain and never sync.

import Combine
import Foundation
import SwiftData

@MainActor
final class AccountProfileStore: ObservableObject {
    static let shared = AccountProfileStore()

    // Current display name (empty → account UI falls back to a generated "DK######" name).
    @Published private(set) var displayName: String = ""

    // Whether iCloud sync is actually active (CloudKit capability present + iCloud signed in).
    @Published private(set) var isCloudSyncAvailable: Bool = CloudSyncAvailability.isSyncEnabled

    private let context: ModelContext
    private var profile: AccountProfile?

    // Device-local placeholder name ("DK######") shown when the profile has no display name.
    // Kept in UserDefaults (not synced) so each Mac keeps a stable placeholder until a real name is set.
    private let fallbackNameKey = "dynamicKeyAccountNameFallback"

    // Uses the shared container so the store works without SwiftUI environment injection.
    private init() {
        context = ModelContext(AppModelContainer.shared)
        loadOrCreateProfile()
        ensureFallbackName()
    }

    // Loads the existing profile, or creates a single empty record on first launch.
    private func loadOrCreateProfile() {
        let descriptor = FetchDescriptor<AccountProfile>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        if let existing = try? context.fetch(descriptor).first {
            profile = existing
        } else {
            let created = AccountProfile()
            context.insert(created)
            try? context.save()
            profile = created
        }
        displayName = profile?.displayName ?? ""
    }

    // Updates the display name and persists it (syncs when iCloud is available).
    func updateDisplayName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile?.displayName = trimmed
        displayName = trimmed
        try? context.save()
    }

    // Refreshes the cached iCloud availability flag (call on launch / when Settings appears).
    func refreshCloudSyncAvailability() {
        isCloudSyncAvailable = CloudSyncAvailability.isSyncEnabled
    }

    // MARK: - Account name resolution

    /// Name shown in the account UI, in priority order:
    /// 1) the user's saved display name, 2) this Mac's account full name (from the Apple ID / macOS
    /// account), 3) the stable "DK######" placeholder as a last resort.
    var resolvedDisplayName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let systemName = Self.systemFullName()
        if !systemName.isEmpty { return systemName }
        let fallback = fallbackName
        return fallback.isEmpty ? Self.makeRandomDKName() : fallback
    }

    /// The persisted device-local placeholder name (empty only if generation somehow failed).
    var fallbackName: String {
        UserDefaults.standard.string(forKey: fallbackNameKey) ?? ""
    }

    /// This Mac's account full name (typically the Apple ID name). Empty when unavailable/placeholder.
    static func systemFullName() -> String {
        let name = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name.caseInsensitiveCompare("unknown") == .orderedSame { return "" }
        return name
    }

    // Generates and persists the "DK######" placeholder once, so it stays stable across launches.
    private func ensureFallbackName() {
        if (UserDefaults.standard.string(forKey: fallbackNameKey) ?? "").isEmpty {
            UserDefaults.standard.set(Self.makeRandomDKName(), forKey: fallbackNameKey)
        }
    }

    // Builds a random name of the form "DK######" (six digits).
    static func makeRandomDKName() -> String {
        let digits = (0..<6).map { _ in String(Int.random(in: 0...9)) }.joined()
        return "DK\(digits)"
    }
}
