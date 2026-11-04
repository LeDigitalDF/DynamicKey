// WelcomeView.swift
// Introduces local vault setup after cloud sign-in (M6 enrollment step 1).
// Flow: lettertype header → three-step glass panel → Start Enrollment CTA.

import SwiftUI

// Layout tuning specific to the Set Up Vault screen (kept local so other auth screens are unaffected).
private enum SetUpVaultLayout {
    /// Larger title letters for this screen only.
    static let titleLetterHeight: CGFloat = 50
    /// Extra space above the title to push the content down from the top of the window.
    static let headerTopPadding: CGFloat = 60
}

struct WelcomeView: View {
    let onContinue: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            GlassBackButton(title: "Back", action: onBack)

            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    LettertypeTitleView(
                        phrase: "Set Up Vault",
                        letterHeight: SetUpVaultLayout.titleLetterHeight,
                        letterSpacing: CloudAuthScreenLayout.titleLetterSpacing,
                        wordSpacing: CloudAuthScreenLayout.titleWordSpacing,
                        animate: false
                    )

                    Text("Secure sign-in with your master password and your unique typing rhythm. Everything stays on this Mac.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, SetUpVaultLayout.headerTopPadding)
                .padding(.bottom, CloudAuthScreenLayout.headerBottomPadding)

                GlassPanel {
                    VStack(alignment: .leading, spacing: GlassTheme.itemSpacing) {
                        introRow(
                            icon: "waveform.path.ecg",
                            title: "Step 1: Rhythm warm-up",
                            detail: "Type four random sentences so DynamicKey learns how you type."
                        )
                        introRow(
                            icon: "keyboard.fill",
                            title: "Step 2: Master password",
                            detail: "Create your master password with visible confirmation fields."
                        )
                        introRow(
                            icon: "lock.shield.fill",
                            title: "Step 3: Password rhythm",
                            detail: "Type your password three times to capture per-key timing for sign-in."
                        )
                    }
                    .padding(GlassTheme.padding)
                }
                .frame(width: CloudAuthScreenLayout.fieldWidth)
                .frame(maxWidth: .infinity)

                PrimaryActionButton(
                    title: "Start Enrollment",
                    color: .blue,
                    expandsFullWidth: true,
                    borderStyle: .referenceDiagonal,
                    action: onContinue
                )
                .frame(width: CloudAuthScreenLayout.buttonWidth)
                .frame(maxWidth: .infinity)
                .padding(.top, CloudAuthScreenLayout.formToButtonSpacing)

                Text("Press Enter or click the button to begin sentence training.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
            }
        }
        .frame(maxWidth: GlassTheme.maxContentWidth)
        .background {
            EnterKeyMonitor(onEnter: onContinue)
        }
    }

    private func introRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
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
