// SiteCredentialNotifications.swift
// Notification posted when site credentials change via Settings or the extension API (W3.5).
//
// Flow: CredentialStore saves → posts notification → ContentView refreshes Settings list.

import Foundation

extension Notification.Name {
    /// Posted after site credentials are saved, updated, or deleted in Keychain.
    static let siteCredentialsDidChange = Notification.Name("KeyStrokeAuth.siteCredentialsDidChange")

    /// Posted after the website allowlist changes in UserDefaults.
    static let sitePolicyDidChange = Notification.Name("KeyStrokeAuth.sitePolicyDidChange")

    /// Posted after DynamicShield trusted sender domains change in UserDefaults.
    static let dynamicShieldPolicyDidChange = Notification.Name("KeyStrokeAuth.dynamicShieldPolicyDidChange")

    /// Posted when the browser extension asks the Mac app to open retrain typing profile.
    static let dynamicKeyExtensionOpenRetrain = Notification.Name("DynamicKey.extensionOpenRetrain")

    /// Posted when the menu bar panel asks to open the main DynamicKey window on Home.
    static let dynamicKeyMenuBarOpenMainApp = Notification.Name("DynamicKey.menuBarOpenMainApp")

    /// Posted when the menu bar panel asks to open the Preferences window.
    static let dynamicKeyMenuBarOpenPreferences = Notification.Name("DynamicKey.menuBarOpenPreferences")
}
