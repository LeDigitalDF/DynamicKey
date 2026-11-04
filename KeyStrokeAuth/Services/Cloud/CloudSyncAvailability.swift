// CloudSyncAvailability.swift
// Lightweight check for whether this Mac is signed into iCloud.
// Flow: read FileManager's ubiquity identity token → a nil token means no iCloud account is
//       available, which drives the "iCloud sync disabled" friendly badge in Settings.

import Foundation

enum CloudSyncAvailability {
    // True when an iCloud account is signed in on this Mac.
    static var isSignedIn: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    // True only when sync can actually happen: the CloudKit capability is present AND iCloud is
    // signed in. Before the capability is added in Xcode, this is false (drives the Settings badge).
    static var isSyncEnabled: Bool {
        AppModelContainer.hasCloudKitEntitlement() && isSignedIn
    }
}
