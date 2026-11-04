// AuditEvent.swift
// Local security event records for user review (M3.6).

import Foundation
import SwiftUI

enum AuditEventType: String, Codable {
    case loginSuccess
    case loginFailedPassword
    case loginFailedRhythm
    case loginFailedEmpty
    case loginBlockedLockout
    case lockoutCleared
    case profileCreated
    case profileUpdated
    case masterPasswordChanged
    case profileDeleted
    case extensionPaired
    case extensionPairingsRevoked
    case extensionVerifySuccess
    case extensionVerifyDenied
    case extensionFillApproved
    case siteCredentialGenerated
    case siteCredentialsImported
    case extensionAllowlistAdded
    case extensionDynamicShieldTrusted
    case extensionDynamicShieldWarning
    case extensionDynamicShieldDismissed
    case extensionDynamicShieldRemoved
    case safeModeEngaged
    case safeModeEnded
    case emergencyLock
    case emergencyLockEnded
    case loginFailedUntrustedKeyboard
    case loginFailedUntrustedNetwork
}

struct AuditEvent: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let type: AuditEventType
    let detail: String?

    init(type: AuditEventType, detail: String? = nil, timestamp: Date = Date()) {
        self.id = UUID()
        self.timestamp = timestamp
        self.type = type
        self.detail = detail
    }

    var displayTitle: String {
        switch type {
        case .loginSuccess: return "Sign-in succeeded"
        case .loginFailedPassword: return "Sign-in failed — wrong password"
        case .loginFailedRhythm: return "Sign-in failed — rhythm mismatch"
        case .loginFailedEmpty: return "Sign-in failed — empty input"
        case .loginBlockedLockout: return "Sign-in blocked — lockout active"
        case .lockoutCleared: return "Lockout cleared manually"
        case .profileCreated: return "Profile created"
        case .profileUpdated: return "Typing profile updated"
        case .masterPasswordChanged: return "Master password changed"
        case .profileDeleted: return "Profile deleted"
        case .extensionPaired: return "Browser extension paired"
        case .extensionPairingsRevoked: return "Extension pairings revoked"
        case .extensionVerifySuccess: return "Extension verify succeeded"
        case .extensionVerifyDenied: return "Extension verify denied"
        case .extensionFillApproved: return "Extension fill approved"
        case .siteCredentialGenerated: return "Site password generated"
        case .siteCredentialsImported: return "Site credentials imported"
        case .extensionAllowlistAdded: return "Website added to allowlist"
        case .extensionDynamicShieldTrusted: return "DynamicShield sender trusted"
        case .extensionDynamicShieldWarning: return "DynamicShield warning shown"
        case .extensionDynamicShieldDismissed: return "DynamicShield warning dismissed"
        case .extensionDynamicShieldRemoved: return "DynamicShield sender removed"
        case .safeModeEngaged: return "Safe Mode engaged"
        case .safeModeEnded: return "Safe Mode ended"
        case .emergencyLock: return "Safe Mode engaged"
        case .emergencyLockEnded: return "Safe Mode ended"
        case .loginFailedUntrustedKeyboard: return "Sign-in blocked — untrusted keyboard"
        case .loginFailedUntrustedNetwork: return "Sign-in blocked — untrusted network"
        }
    }

    /// Accent color for timeline dots and connectors — unique per event category.
    var timelineAccentColor: Color {
        switch type {
        case .loginSuccess, .extensionVerifySuccess, .extensionFillApproved:
            return Color.green
        case .loginFailedPassword, .loginFailedRhythm, .loginFailedEmpty, .extensionVerifyDenied:
            return Color.red
        case .loginBlockedLockout:
            return Color.orange
        case .lockoutCleared:
            return Color.yellow
        case .profileCreated, .profileUpdated, .masterPasswordChanged:
            return Color.blue
        case .profileDeleted:
            return Color.pink
        case .extensionPaired:
            return Color.purple
        case .extensionPairingsRevoked:
            return Color.orange
        case .siteCredentialGenerated:
            return Color.cyan
        case .siteCredentialsImported:
            return Color.teal
        case .extensionAllowlistAdded:
            return Color.mint
        case .extensionDynamicShieldTrusted:
            return Color.green
        case .extensionDynamicShieldWarning:
            return Color.orange
        case .extensionDynamicShieldDismissed:
            return Color.yellow
        case .extensionDynamicShieldRemoved:
            return Color.pink
        case .safeModeEngaged, .safeModeEnded, .emergencyLock, .emergencyLockEnded:
            return Color.orange
        case .loginFailedUntrustedKeyboard, .loginFailedUntrustedNetwork:
            return Color.orange
        }
    }

    /// Short single-line summary shown beside each timeline dot.
    var timelineSummary: String {
        if let detail = detail, !detail.isEmpty {
            return "\(displayTitle) · \(detail)"
        }
        return displayTitle
    }
}
