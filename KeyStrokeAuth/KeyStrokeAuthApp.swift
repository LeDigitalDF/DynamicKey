// KeyStrokeAuthApp.swift
// App entry with main window, optional menu bar status, and extension auth service lifecycle (M5).
//
// Flow: launch app → start local auth server → show ContentView with environment objects.

import SwiftData
import SwiftUI

@main
struct KeyStrokeAuthApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleController.self) private var appLifecycle
    @StateObject private var appStatus = AppStatusModel()
    @StateObject private var appearance = AppAppearanceStore()
    @ObservedObject private var localAuthService = LocalAuthServiceManager.shared
    @ObservedObject private var preferences = AppPreferencesStore.shared
    // SwiftData-backed profile store (display name + iCloud sync availability).
    @ObservedObject private var accountProfile = AccountProfileStore.shared
    @AppStorage(AppPreferencesStore.showMenuBarIconDefaultsKey) private var showMenuBarIcon = true

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appStatus)
                .environmentObject(localAuthService)
                .environmentObject(appearance)
                .environmentObject(preferences)
                .environmentObject(accountProfile)
                .environmentObject(TrustContextStore.shared)
                .environment(\.glassPalette, appearance.palette)
                .preferredColorScheme(appearance.colorScheme)
        }
        // Shared SwiftData container (CloudKit-backed when the capability is enabled).
        .modelContainer(AppModelContainer.shared)
        .defaultSize(width: 720, height: 680)

        // Use @AppStorage for isInserted — binding to @ObservedObject publishes during scene updates.
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            DynamicKeyMenuBarPanel(
                appStatus: appStatus,
                localAuthService: localAuthService
            )
            .environment(\.glassPalette, appearance.palette)
        } label: {
            Image("MenuBarIcon")
                .resizable()
                .renderingMode(.template)
                .frame(width: 18, height: 18)
                .accessibilityLabel("DynamicKey")
        }
        .menuBarExtraStyle(.window)

        Window("DynamicKey Preferences", id: "dynamickey-preferences") {
            DynamicKeyPreferencesView()
                .environmentObject(appearance)
                .environmentObject(preferences)
                .environment(\.glassPalette, appearance.palette)
                .preferredColorScheme(appearance.colorScheme)
        }
        .defaultSize(width: 580, height: 460)
        .windowResizability(.contentSize)
    }
}
