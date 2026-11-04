// ExplanationView.swift
// Shown after password rhythm enrollment completes, before saving the profile.

import SwiftUI

struct ExplanationView: View {
    let keystrokeCount: Int
    let positionCount: Int
    let sampleCount: Int
    let onContinue: () -> Void
    let onBack: () -> Void

    var body: some View {
        PhaseScreenLayout {
            BackButton(title: "Back", action: onBack)

            PhaseHeader(
                title: "Typing Profile Ready",
                subtitle: "Your rhythm profile is built and ready to save securely.",
                systemImage: "checkmark.circle.fill",
                accent: .green
            )

            GlassPanel {
                VStack(alignment: .leading, spacing: GlassTheme.itemSpacing) {
                    profileRow(
                        icon: "waveform.path.ecg",
                        title: "Per-key rhythm captured",
                        detail: "Built from \(sampleCount) password samples, \(keystrokeCount) keystrokes, and \(positionCount) character positions."
                    )
                    profileRow(
                        icon: "person.badge.key.fill",
                        title: "Why this is more accurate",
                        detail: "Your profile reflects how you type your actual password."
                    )
                    profileRow(
                        icon: "lock.shield.fill",
                        title: "Ready to save",
                        detail: "When you continue, your password hash and rhythm profile are stored in Keychain."
                    )
                    profileRow(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Improves the more you use it",
                        detail: "Every sign-in helps DynamicKey learn your typing rhythm more precisely — and everything it learns stays on this Mac and never leaves your device."
                    )
                }
                .padding(GlassTheme.padding)
            }

            PrimaryActionButton(
                title: "Save & Test",
                color: .green,
                expandsFullWidth: false,
                action: onContinue
            )
            EnterKeyMonitor(onEnter: onContinue)

            Text("Press Enter or click the button to save and test your profile.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func profileRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
