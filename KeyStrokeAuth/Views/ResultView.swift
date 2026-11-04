// ResultView.swift
// Displays login outcome with rhythm score and denial reason when applicable.

import SwiftUI

struct ResultView: View {
    let granted: Bool
    let matchPercentage: Int
    let denialReason: DenialReason?
    let isTestMode: Bool
    let onTryAgain: () -> Void
    let onContinue: (() -> Void)?
    let onResetLockout: (() -> Void)?

    var body: some View {
        PhaseScreenLayout {
            PhaseHeader(
                title: granted ? "Access Granted!" : "Access Denied",
                subtitle: resultSubtitle,
                systemImage: granted ? "checkmark.seal.fill" : "xmark.seal.fill",
                accent: granted ? .green : .red
            )

            if matchPercentage > 0 || granted {
                GlassPanel {
                    Text("Rhythm Match: \(matchPercentage)%")
                        .font(.title2.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(GlassTheme.padding)
                }
                .accessibilityLabel("Rhythm match \(matchPercentage) percent")
            }

            if granted, isTestMode, let continueAction = onContinue {
                PrimaryActionButton(
                    title: "Continue",
                    color: .green,
                    action: continueAction
                )

                GlassTextButton(title: "Retry Test", action: onTryAgain)

                EnterKeyMonitor(onEnter: continueAction)

                Text("Press Enter to continue to Log In.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !granted || isTestMode {
                PrimaryActionButton(
                    title: isTestMode ? "Retry Test" : "Try Again",
                    color: .blue,
                    action: onTryAgain
                )

                if !granted, isLockedOut(denialReason), let onResetLockout {
                    GlassTextButton(title: "Reset Lockout (Testing)", action: onResetLockout)
                }

                EnterKeyMonitor(onEnter: onTryAgain)

                Text("Press Enter to \(isTestMode ? "retry the test" : "try again").")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var resultSubtitle: String? {
        if granted && isTestMode {
            return "Setup is complete. Your password and typing rhythm both matched."
        }
        if let denialReason, !granted {
            return message(for: denialReason)
        }
        return nil
    }

    private func isLockedOut(_ reason: DenialReason?) -> Bool {
        if case .lockedOut = reason { return true }
        return false
    }

    private func message(for reason: DenialReason) -> String {
        switch reason {
        case .wrongPassword:
            return "The password is incorrect."
        case .rhythmMismatch:
            return "Your typing rhythm did not match your enrolled profile. Try again at your normal typing speed."
        case .emptyInput:
            return "Enter your password before verifying."
        case .lockedOut(let remainingSeconds):
            if remainingSeconds >= 60 {
                let minutes = remainingSeconds / 60
                let seconds = remainingSeconds % 60
                return "Too many failed attempts. Try again in \(minutes)m \(seconds)s."
            }
            return "Too many failed attempts. Try again in \(remainingSeconds)s."
        case .untrustedKeyboard:
            return "This keyboard is not on your trusted list. Connect a trusted keyboard or update Settings."
        case .untrustedNetwork:
            return "This Wi-Fi network is not trusted. Join a trusted network or update Settings."
        }
    }
}
