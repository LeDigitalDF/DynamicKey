// SetPasswordView.swift
// Master password enrollment with validation before rhythm training (M6 enrollment step 2).
// Flow: lettertype header → flat password fields → Continue CTA with diagonal border.

import SwiftUI

// Layout tuning specific to the Master Password screen (kept local so other auth screens are unaffected).
private enum MasterPasswordLayout {
    /// Extra space above the title to push the content down from the top of the window.
    static let headerTopPadding: CGFloat = 60
}

struct SetPasswordView: View {
    @Binding var masterPassword: String
    @Binding var repeatPassword: String
    @Binding var validationMessage: String?
    var flowTitle: String = "Step 2: Create Master Password"
    var flowSubtitle: String = "Minimum \(PasswordPolicy.minimumLength) characters. Both fields show what you type."
    var continueTitle: String = "Continue to Rhythm Training"
    var backTitle: String = "Back"
    let onContinue: () -> Void
    let onBack: () -> Void

    private var canContinue: Bool {
        PasswordPolicy.validate(password: masterPassword, repeatPassword: repeatPassword) == nil
    }

    private var usesEnrollmentChrome: Bool {
        flowTitle.contains("Step 2")
    }

    var body: some View {
        VStack(spacing: 0) {
            GlassBackButton(title: backTitle, action: onBack)

            if usesEnrollmentChrome {
                enrollmentBody
            } else {
                settingsStyleBody
            }
        }
        .frame(maxWidth: GlassTheme.maxContentWidth)
        .background {
            EnterKeyMonitor(onEnter: continueIfValid)
        }
    }

    private var enrollmentBody: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                LettertypeTitleView(
                    phrase: "Master Password",
                    letterHeight: CloudAuthScreenLayout.titleLetterHeight,
                    letterSpacing: CloudAuthScreenLayout.titleLetterSpacing,
                    wordSpacing: CloudAuthScreenLayout.titleWordSpacing,
                    animate: false
                )

                Text(flowSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, MasterPasswordLayout.headerTopPadding)
            .padding(.bottom, CloudAuthScreenLayout.headerBottomPadding)

            passwordFields
                .frame(width: CloudAuthScreenLayout.fieldWidth)
                .frame(maxWidth: .infinity)

            PrimaryActionButton(
                title: continueTitle,
                color: .blue,
                isEnabled: canContinue,
                expandsFullWidth: true,
                borderStyle: .referenceDiagonal,
                action: onContinue
            )
            .frame(width: CloudAuthScreenLayout.buttonWidth)
            .frame(maxWidth: .infinity)
            .padding(.top, CloudAuthScreenLayout.formToButtonSpacing)

            Text("Press Enter to continue when both passwords match.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 12)
        }
    }

    private var settingsStyleBody: some View {
        PhaseScreenLayout {
            BackButton(title: backTitle, action: onBack)

            PhaseHeader(title: flowTitle, subtitle: flowSubtitle)

            GlassPanel {
                passwordFields
                    .padding(GlassTheme.padding)
            }

            PrimaryActionButton(
                title: continueTitle,
                color: .blue,
                isEnabled: canContinue,
                action: onContinue
            )

            Text("Press Enter to continue when both passwords match.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var passwordFields: some View {
        VStack(alignment: .leading, spacing: CloudAuthScreenLayout.fieldSpacing) {
            VStack(alignment: .leading, spacing: 6) {
                GlassPasswordTextField(
                    title: "Master password",
                    placeholder: "Enter master password",
                    text: $masterPassword,
                    fieldWidth: usesEnrollmentChrome ? CloudAuthScreenLayout.fieldWidth : nil,
                    borderStyle: usesEnrollmentChrome ? .none : .standard,
                    isSecure: usesEnrollmentChrome,
                    onSubmit: continueIfValid,
                    autoFocusOnAppear: true
                )

                if usesEnrollmentChrome, !masterPassword.isEmpty {
                    PasswordStrengthBar(strength: PasswordPolicy.strength(for: masterPassword))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                GlassPasswordTextField(
                    title: "Confirm password",
                    placeholder: "Repeat master password",
                    text: $repeatPassword,
                    fieldWidth: usesEnrollmentChrome ? CloudAuthScreenLayout.fieldWidth : nil,
                    borderStyle: usesEnrollmentChrome ? .none : .standard,
                    isSecure: usesEnrollmentChrome,
                    onSubmit: continueIfValid
                )

                if usesEnrollmentChrome, !repeatPassword.isEmpty {
                    PasswordStrengthBar(
                        strength: PasswordPolicy.confirmFieldStrength(
                            password: masterPassword,
                            repeatPassword: repeatPassword
                        )
                    )
                }
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
    }

    private func continueIfValid() {
        if canContinue { onContinue() }
    }
}
