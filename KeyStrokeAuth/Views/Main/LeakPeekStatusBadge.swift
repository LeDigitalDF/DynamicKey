// LeakPeekStatusBadge.swift
// Compact Safe / Compromised / Not scanned pill for LeakPeek site rows.

import SwiftUI

struct LeakPeekStatusBadge: View {
    let status: LeakPeekSiteStatus

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                Capsule(style: .continuous)
                    .fill(backgroundColor)
            }
            .accessibilityLabel(accessibilityLabel)
    }

    private var label: String {
        switch status {
        case .unknown: return "Not scanned"
        case .safe: return "Safe"
        case .compromised: return "Compromised"
        }
    }

    private var foregroundColor: Color {
        switch status {
        case .unknown: return .secondary
        case .safe: return Color(red: 0.1, green: 0.72, blue: 0.35)
        case .compromised: return Color(red: 0.95, green: 0.25, blue: 0.22)
        }
    }

    private var backgroundColor: Color {
        foregroundColor.opacity(0.16)
    }

    private var accessibilityLabel: String {
        switch status {
        case .unknown: return "Password not scanned yet"
        case .safe: return "Password is safe"
        case .compromised: return "Password is compromised"
        }
    }
}
