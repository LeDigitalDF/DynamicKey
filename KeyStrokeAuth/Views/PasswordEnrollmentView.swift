// PasswordEnrollmentView.swift
// Captures multiple password typing samples for per-key rhythm enrollment.

import SwiftUI

struct PasswordEnrollmentView: View {
    let sampleIndex: Int
    let totalSamples: Int
    let typedLength: Int
    var liveMatchPercentage: Int? = nil
    let hasError: Bool
    let isReenrollment: Bool
    var isChangingMasterPassword: Bool = false
    let errorMessage: String?
    let onKeystroke: (KeystrokeData) -> Void
    let onClearSample: () -> Void
    let onBack: () -> Void

    var body: some View {
        PhaseScreenLayout {
            BackButton(title: "Back", action: onBack)

            PhaseHeader(
                title: enrollmentTitle,
                subtitle: enrollmentSubtitle
            )

            GlassPanel {
                Text("Sample \(sampleIndex + 1) of \(totalSamples)")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(GlassTheme.padding)
            }

            PasswordDotsDisplay(
                length: typedLength,
                caption: isReenrollment ? "Click here if typing does not respond" : "Type in this area"
            )

            if let liveMatchPercentage, !isReenrollment, !isChangingMasterPassword {
                GlassPanel {
                    Text("Rhythm match: \(liveMatchPercentage)%")
                        .font(.headline.monospacedDigit())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }

            if hasError {
                GlassInfoBanner(kind: .danger, message: errorMessage ?? "Incorrect character. Continue from the mistake.")
            } else {
                Text(enrollmentHint)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if isReenrollment {
                GlassTextButton(title: "Clear Sample", action: onClearSample)
            }

            KeystrokeMonitorViewRepresentable(onKeystroke: onKeystroke)
                .frame(maxWidth: .infinity, minHeight: 44)
                .opacity(0.01)
        }
    }

    private var enrollmentTitle: String {
        if isChangingMasterPassword {
            return "Train on New Password"
        }
        if isReenrollment {
            return "Retrain Typing Profile"
        }
        return "Step 3: Train Your Master Password"
    }

    private var enrollmentSubtitle: String {
        if isChangingMasterPassword {
            return "Type your new master password exactly as entered. DynamicKey records per-key timing for the new password."
        }
        if isReenrollment {
            return "Type your current master password 3 times (Enter after each). Your password does not change — only your typing rhythm profile is refreshed."
        }
        return "Type your master password exactly as created. DynamicKey records per-key timing."
    }

    private var enrollmentHint: String {
        if isReenrollment {
            return "Press Enter when you have finished typing your password."
        }
        return "Type naturally at your normal pace."
    }
}
