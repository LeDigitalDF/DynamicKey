// AppLaunchRouter.swift
// Decides the first screen after launch from the local (Keychain) master-password vault only.
// Flow: keychain vault exists → master login; otherwise → landing (first-run onboarding).
//
// Identity is now the user's iCloud account (via SwiftData + CloudKit), so there is no cloud
// session/email/password to route around — the single question is "does a local vault exist?".

import Foundation

/// Launch destinations derived purely from the on-device master-password vault.
enum AppLaunchDestination: Equatable {
    /// A master password profile exists in the Keychain — go straight to unlock.
    case masterLogin
    /// No local vault yet — show the landing / first-run onboarding entry.
    case landing
}

enum AppLaunchRouter {
    /// Resolves where the app should route immediately after launch.
    static func resolve(hasLocalMasterProfile: Bool) -> AppLaunchDestination {
        hasLocalMasterProfile ? .masterLogin : .landing
    }
}
