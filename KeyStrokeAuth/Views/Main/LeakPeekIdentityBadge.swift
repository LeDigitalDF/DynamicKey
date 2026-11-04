// LeakPeekIdentityBadge.swift
// Compact email breach status pill for credential rows with email usernames.

import SwiftUI

struct LeakPeekIdentityBadge: View {
    let status: LeakPeekIdentityDisplayStatus
    var breachCount: Int = 0

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                Capsule(style: .continuous)
                    .fill(backgroundColor)
                    .overlay {
                        if status == .safe {
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    foregroundColor.opacity(colorScheme == .dark ? 0.50 : 0.40),
                                    lineWidth: 1
                                )
                        }
                    }
            }
            .accessibilityLabel(accessibilityLabel)
    }

    private var label: String {
        switch status {
        case .unknown:
            return "Email not checked"
        case .safe:
            return "Email safe"
        case .compromised:
            if breachCount > 0 {
                return "Email · \(breachCount) breach\(breachCount == 1 ? "" : "es")"
            }
            return "Email compromised"
        }
    }

    private var foregroundColor: Color {
        switch status {
        case .unknown: return .secondary
        case .safe:
            if colorScheme == .dark {
                return Color(red: 0.55, green: 0.86, blue: 1.0)
            }
            return Color(red: 0.02, green: 0.34, blue: 0.68)
        case .compromised: return Color(red: 0.95, green: 0.45, blue: 0.18)
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .safe:
            return foregroundColor.opacity(colorScheme == .dark ? 0.30 : 0.22)
        default:
            return foregroundColor.opacity(0.16)
        }
    }

    private var accessibilityLabel: String {
        switch status {
        case .unknown: return "Email not checked for breaches"
        case .safe: return "Email address is safe"
        case .compromised: return "Email address found in breaches"
        }
    }
}
