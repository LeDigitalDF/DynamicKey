// ChangePasswordVerifyView.swift
// Confirms the user's current master password and typing rhythm before a password change.
// Flow: hidden password entry with keystroke capture → verify password hash and rhythm profile.

import SwiftUI

struct ChangePasswordVerifyView: View {
    let typedLength: Int
    let errorMessage: String?
    let passThreshold: Int
    let onKeystroke: (KeystrokeData) -> Void
    let onVerify: () -> Void
    let onBack: () -> Void

    var body: some View {
        PhaseScreenLayout {
            BackButton(title: "Back to Settings", action: onBack)

            PhaseHeader(
                title: "Change Master Password",
                subtitle: "Type your current master password at your normal pace. Both the password and your typing rhythm must match."
            )

            PasswordDotsDisplay(
                length: typedLength,
                caption: "Type your password, then press Enter or Verify."
            )

            if let errorMessage {
                GlassInfoBanner(kind: .danger, message: errorMessage)
            }

            KeystrokeMonitorViewRepresentable(onKeystroke: onKeystroke)
                .frame(width: 1, height: 1)

            GlassButton(
                title: "Verify",
                role: .primary,
                expandsFullWidth: false,
                submitOnReturn: true,
                action: onVerify
            )

            Text("Rhythm match threshold: \(passThreshold)%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
