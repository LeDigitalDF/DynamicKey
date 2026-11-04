// LoginTrustBadgeRow.swift
// Read-only trust indicators shown on the master-password login screen.
// Flow: observe TrustContextStore → render a keyboard badge and a Wi-Fi badge →
//       green + checkmark when the current context is trusted, otherwise a muted warning tint →
//       hovering a badge reveals a short explanation. The badges are informational only (not tappable).

import SwiftUI

// Compact horizontal row of trust badges (keyboard + Wi-Fi) for the login screen.
struct LoginTrustBadgeRow: View {
    // Observe the shared store so the badges refresh when trust rules change.
    @ObservedObject private var trustContext = TrustContextStore.shared

    var body: some View {
        HStack(spacing: 16) {
            // Keyboard trust indicator.
            LoginTrustBadge(
                systemImage: "keyboard",
                isTrusted: trustContext.isCurrentKeyboardTrusted,
                helpText: keyboardHelpText,
                accessibilityLabel: "Keyboard trust status"
            )

            // Wi-Fi network trust indicator.
            LoginTrustBadge(
                systemImage: "wifi",
                isTrusted: trustContext.isCurrentNetworkTrusted,
                helpText: networkHelpText,
                accessibilityLabel: "Network trust status"
            )
        }
    }

    // Explanation shown when hovering the keyboard badge.
    private var keyboardHelpText: String {
        if !trustContext.requiresKeyboardTrust {
            return "No keyboard restrictions — this keyboard is allowed."
        }
        return trustContext.isCurrentKeyboardTrusted
            ? "This keyboard is on your trusted list."
            : "This keyboard is not on your trusted list."
    }

    // Explanation shown when hovering the Wi-Fi badge.
    private var networkHelpText: String {
        if !trustContext.requiresNetworkTrust {
            return "No network restrictions — this Wi-Fi network is allowed."
        }
        return trustContext.isCurrentNetworkTrusted
            ? "This Wi-Fi network is on your trusted list."
            : "This Wi-Fi network is not on your trusted list."
    }
}

// A single circular liquid-glass trust badge with a status checkmark and hover tooltip.
private struct LoginTrustBadge: View {
    let systemImage: String
    let isTrusted: Bool
    let helpText: String
    let accessibilityLabel: String

    private let badgeSize: CGFloat = 44

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: badgeSize, height: badgeSize)
            // Green glass when trusted, amber when the current context fails a trust rule.
            .background {
                GlassCapsuleSurface(tint: isTrusted ? .green : .orange)
                    .clipShape(Circle())
            }
            // Small status marker in the corner: checkmark when trusted, exclamation otherwise.
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: isTrusted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isTrusted ? Color.green : Color.orange)
                    .background(Circle().fill(Color.white))
                    .offset(x: 3, y: 3)
            }
            // Informational only: no button wrapper, so it is not clickable — hover reveals the text.
            .help(helpText)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(helpText)
    }
}
