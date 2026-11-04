// MainSidebarSection.swift
// Sidebar destinations for the post-login DynamicKey main interface.

import SwiftUI

enum MainSidebarSection: Hashable, CaseIterable {
    case home
    case credentials
    case allowlist
    case securityActivity
    case leakPeek
    case extensionPairing
    case settings

    var title: String {
        switch self {
        case .home: return "Home"
        case .credentials: return "Website Credentials"
        case .allowlist: return "Connected Sites"
        case .securityActivity: return "Security Activity"
        case .leakPeek: return "LeakPeek"
        case .extensionPairing: return "Browser Extension"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .credentials: return "key.fill"
        case .allowlist: return "globe"
        case .securityActivity: return "shield.checkered"
        case .leakPeek: return "eye.trianglebadge.exclamationmark"
        case .extensionPairing: return "puzzlepiece.extension.fill"
        case .settings: return "gearshape"
        }
    }

    /// Distinct accent for each sidebar destination (Apple Passwords–style colored icons).
    var accentColor: Color {
        switch self {
        case .home: return .blue
        case .credentials: return .orange
        case .allowlist: return .green
        case .securityActivity: return .pink
        case .leakPeek: return .indigo
        case .extensionPairing: return .purple
        case .settings: return .secondary
        }
    }

    /// Glass button tint matching the section icon color.
    var capsuleTint: GlassCapsuleTint {
        switch self {
        case .home: return .blue
        case .credentials: return .orange
        case .allowlist: return .green
        case .securityActivity: return .verify
        case .leakPeek: return .enroll
        case .extensionPairing: return .enroll
        case .settings: return .neutral
        }
    }

    /// Sections shown in the primary sidebar list (settings opens from the footer gear).
    static var sidebarItems: [MainSidebarSection] {
        [.home, .credentials, .allowlist, .securityActivity, .leakPeek]
    }
}
