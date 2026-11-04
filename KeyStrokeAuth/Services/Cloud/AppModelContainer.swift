// AppModelContainer.swift
// Shared SwiftData container for CloudKit-synced app data (currently AccountProfile).
// Flow: try to build a CloudKit-backed container → on failure (e.g. the iCloud capability/container
//       is not provisioned yet) fall back to a local-only store so the app still runs during
//       development → last resort in-memory so launch can never crash.
//
// When the "iCloud → CloudKit" capability and the container below are enabled in Xcode's
// Signing & Capabilities, mirroring activates automatically with no code change.

import Foundation
import Security
import SwiftData

enum AppModelContainer {
    // CloudKit container identifier — must match the iCloud container enabled for this app ID.
    static let cloudKitContainerID = "iCloud.LeDigital.KeyStrokeAuth"

    // App-wide shared container. Built once and reused by the store and SwiftUI environment.
    static let shared: ModelContainer = makeContainer()

    // Builds the best available container, degrading gracefully so the app always launches.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([AccountProfile.self])

        // 1) Preferred: CloudKit-backed private database (syncs across the user's Macs).
        //    Only selected when the process actually carries the CloudKit entitlement. Forcing a
        //    CloudKit config without it does NOT throw here — instead CoreData logs a recurring
        //    "Significant issue" on its background queue — so we gate on the entitlement.
        if hasCloudKitEntitlement() {
            let cloudConfiguration = ModelConfiguration(
                schema: schema,
                cloudKitDatabase: .private(cloudKitContainerID)
            )
            if let container = try? ModelContainer(for: schema, configurations: cloudConfiguration) {
                return container
            }
        }

        // 2) Fallback: local-only store (used before the iCloud capability/container is provisioned).
        let localConfiguration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: schema, configurations: localConfiguration) {
            return container
        }

        // 3) Last resort: in-memory store so launch never fails. A valid in-memory schema
        //    cannot realistically throw, so force-try is acceptable here.
        let memoryConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: memoryConfiguration)
    }

    /// True when this process carries the `com.apple.developer.icloud-services` = ["CloudKit"] entitlement.
    /// Used to decide whether CloudKit mirroring is safe to enable (avoids runtime CloudKit errors
    /// before the capability is added in Xcode's Signing & Capabilities).
    static func hasCloudKitEntitlement() -> Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.developer.icloud-services" as CFString,
                nil
              ) else {
            return false
        }
        guard let services = value as? [String] else { return false }
        return services.contains("CloudKit") || services.contains("CloudKit-Anonymous")
    }
}
