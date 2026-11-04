// ChangeMasterPasswordFlowView.swift
// Slide-over flow: verify current password with rhythm → set new password → train rhythm on new password.
// Flow: rhythm verify → visible new/confirm fields → three hidden rhythm samples → save via ProfileStore.

import SwiftUI

struct ChangeMasterPasswordFlowView: View {
    let passThreshold: Int
    var isCompactCard: Bool = false
    let onComplete: (String) -> Void
    let onCancel: () -> Void

    private enum Step {
        case verifyCurrent
        case setNewPassword
        case enrollRhythm
    }

    @State private var step: Step = .verifyCurrent

    @State private var verifyAttemptText = ""
    @State private var verifyAttemptData: [KeystrokeData] = []
    @State private var verifyErrorMessage: String?

    @State private var verifiedCurrentPassword = ""
    @State private var masterPassword = ""
    @State private var repeatPassword = ""
    @State private var passwordValidationMessage: String?

    @State private var sampleIndex = 0
    @State private var passwordSamples: [[KeystrokeData]] = []
    @State private var currentSampleText = ""
    @State private var currentSampleData: [KeystrokeData] = []
    @State private var enrollmentHasError = false
    @State private var enrollmentErrorMessage: String?
    @State private var saveErrorMessage: String?

    private let profileStore = ProfileStore.shared

    private var sectionSpacing: CGFloat { isCompactCard ? 6 : 14 }
    private var outerSpacing: CGFloat { isCompactCard ? 8 : 18 }

    @FocusState private var isNewPasswordFocused: Bool
    @FocusState private var isConfirmPasswordFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: outerSpacing) {
            switch step {
            case .verifyCurrent:
                verifyCurrentStep
            case .setNewPassword:
                setNewPasswordStep
            case .enrollRhythm:
                enrollRhythmStep
            }

            if let saveErrorMessage {
                GlassInfoBanner(kind: .danger, message: saveErrorMessage)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Step 1 — current master password must match hash and rhythm profile.
    private var verifyCurrentStep: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            if isCompactCard {
                Text("Verify your current password and typing rhythm.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                slideStepHeader(
                    title: "Verify Current Password",
                    subtitle: "Type your current master password at your normal pace. Both the password and your typing rhythm must match."
                )
            }

            PasswordDotsDisplay(
                length: verifyAttemptText.count,
                caption: isCompactCard
                    ? "Type here, then press Verify."
                    : "Type your password, then press Enter or Verify.",
                usesFlexibleWidth: isCompactCard,
                fieldHeight: isCompactCard ? 30 : GlassTheme.passwordFieldHeight,
                stackSpacing: isCompactCard ? 6 : 10
            )

            if let verifyErrorMessage {
                GlassInfoBanner(kind: .danger, message: verifyErrorMessage)
            }

            KeystrokeMonitorViewRepresentable(onKeystroke: handleVerifyKeystroke)
                .frame(width: 1, height: 1)

            compactCardButtonRow {
                flowActionButton(title: "Cancel", role: .secondary, action: cancelFlow)
                flowActionButton(title: "Verify", role: .primary, action: verifyCurrentPassword)
            }
        }
    }

    // Step 2 — visible new password fields (text match only; rhythm comes next).
    private var setNewPasswordStep: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            if isCompactCard {
                Text("Minimum \(PasswordPolicy.minimumLength) characters. Website passwords stay on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    compactPasswordField(
                        label: "New master password",
                        placeholder: "Enter new password",
                        text: $masterPassword,
                        isFocused: $isNewPasswordFocused
                    )

                    compactPasswordField(
                        label: "Confirm new password",
                        placeholder: "Repeat new password",
                        text: $repeatPassword,
                        isFocused: $isConfirmPasswordFocused
                    )

                    if let passwordValidationMessage {
                        Text(passwordValidationMessage)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                slideStepHeader(
                    title: "Choose New Master Password",
                    subtitle: "Minimum \(PasswordPolicy.minimumLength) characters. Website passwords saved on this Mac are not removed."
                )

                GlassPanel {
                    VStack(alignment: .leading, spacing: GlassTheme.itemSpacing) {
                        GlassPasswordTextField(
                            title: "New master password",
                            placeholder: "Enter new password",
                            text: $masterPassword
                        )

                        GlassPasswordTextField(
                            title: "Confirm new password",
                            placeholder: "Repeat new password",
                            text: $repeatPassword
                        )

                        if let passwordValidationMessage {
                            Text(passwordValidationMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(GlassTheme.padding)
                }
            }

            compactCardButtonRow {
                flowActionButton(title: "Back", role: .secondary, action: backToVerify)
                flowActionButton(
                    title: "Continue",
                    role: .primary,
                    action: continueToRhythmEnrollment
                )
            }
        }
    }

    // Step 3 — three rhythm samples on the new password before saving.
    private var enrollRhythmStep: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            if isCompactCard {
                Text("Sample \(sampleIndex + 1) of \(EnrollmentConfig.requiredSamples) — type your new password naturally.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                slideStepHeader(
                    title: "Train on New Password",
                    subtitle: "Type your new master password \(EnrollmentConfig.requiredSamples) times. DynamicKey records per-key timing for sign-in."
                )

                GlassPanel {
                    Text("Sample \(sampleIndex + 1) of \(EnrollmentConfig.requiredSamples)")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(GlassTheme.padding)
                }
            }

            PasswordDotsDisplay(
                length: currentSampleText.count,
                caption: isCompactCard ? "Type in this area" : "Type in this area",
                usesFlexibleWidth: isCompactCard,
                fieldHeight: isCompactCard ? 30 : GlassTheme.passwordFieldHeight,
                stackSpacing: isCompactCard ? 6 : 10
            )

            if enrollmentHasError {
                GlassInfoBanner(
                    kind: .danger,
                    message: enrollmentErrorMessage ?? "Incorrect character. Continue from the mistake."
                )
            } else if !isCompactCard {
                Text("Type naturally at your normal pace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            KeystrokeMonitorViewRepresentable(onKeystroke: handleEnrollmentKeystroke)
                .frame(maxWidth: .infinity, minHeight: isCompactCard ? 1 : 44)
                .opacity(0.01)

            compactCardButtonRow {
                flowActionButton(title: "Back", role: .secondary, action: backToSetPassword)
            }
        }
    }

    @ViewBuilder
    private func compactCardButtonRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: isCompactCard ? .center : .leading)
    }

    @ViewBuilder
    private func flowActionButton(
        title: String,
        role: GlassButtonRole = .secondary,
        action: @escaping () -> Void
    ) -> some View {
        if isCompactCard {
            LiquidGlassSparkleButton(
                title: title,
                font: .caption.weight(.semibold),
                sparklePalette: role == .primary ? .blue : .neutral,
                action: action
            )
        } else {
            SettingsCompactButton(title: title, role: role, action: action)
        }
    }

    private func compactPasswordField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        isFocused: FocusState<Bool>.Binding
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            GlassCompactInputField(
                text: text,
                placeholder: placeholder,
                isFocused: isFocused,
                isSecure: true,
                cornerRadius: 10
            )
        }
    }

    private func slideStepHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: isCompactCard ? 4 : 6) {
            Text(title)
                .font(isCompactCard ? .subheadline.weight(.bold) : .title3.weight(.bold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func handleVerifyKeystroke(_ data: KeystrokeData) {
        if data.character == "\r" {
            verifyCurrentPassword()
            return
        }

        if isDeleteKey(data.character) {
            guard !verifyAttemptText.isEmpty, !verifyAttemptData.isEmpty else { return }
            verifyAttemptText.removeLast()
            verifyAttemptData.removeLast()
            return
        }

        verifyAttemptData.append(data)
        verifyAttemptText.append(data.character)
    }

    private func verifyCurrentPassword() {
        verifyErrorMessage = nil

        let result = profileStore.verifyLogin(
            password: verifyAttemptText,
            loginData: verifyAttemptData,
            enforceSecurity: false
        )

        guard result.granted else {
            SensitiveDataCleaner.clearLoginAttempt(text: &verifyAttemptText, data: &verifyAttemptData)
            verifyErrorMessage = denialMessage(for: result)
            return
        }

        verifiedCurrentPassword = verifyAttemptText
        SensitiveDataCleaner.clearLoginAttempt(text: &verifyAttemptText, data: &verifyAttemptData)
        masterPassword = ""
        repeatPassword = ""
        passwordValidationMessage = nil
        step = .setNewPassword
    }

    private func denialMessage(for result: LoginVerificationResult) -> String {
        switch result.denialReason {
        case .wrongPassword:
            return ProfileStoreError.wrongPassword.localizedDescription
        case .rhythmMismatch:
            return "Typing rhythm did not match (\(result.matchPercentage)% — need at least \(passThreshold)%)."
        case .emptyInput:
            return "Type your current master password first."
        case .lockedOut(let remaining):
            return "Sign-in is temporarily locked. Try again in \(remaining)s."
        case .untrustedKeyboard:
            return "This keyboard is not trusted. Update trusted keyboards in Settings or connect an approved device."
        case .untrustedNetwork:
            return "This Wi-Fi network is not trusted. Join a trusted network or update Settings."
        case .none:
            return "Verification failed. Try again."
        }
    }

    private func continueToRhythmEnrollment() {
        saveErrorMessage = nil
        passwordValidationMessage = PasswordPolicy.validate(
            password: masterPassword,
            repeatPassword: repeatPassword
        )
        guard passwordValidationMessage == nil else { return }

        if masterPassword == verifiedCurrentPassword {
            passwordValidationMessage = ProfileStoreError.newPasswordSameAsCurrent.localizedDescription
            return
        }

        passwordSamples = []
        sampleIndex = 0
        resetCurrentSample()
        step = .enrollRhythm
    }

    private func handleEnrollmentKeystroke(_ data: KeystrokeData) {
        if isDeleteKey(data.character) {
            guard !currentSampleText.isEmpty, !currentSampleData.isEmpty else { return }
            currentSampleText.removeLast()
            currentSampleData.removeLast()
            enrollmentHasError = false
            enrollmentErrorMessage = nil
            return
        }

        let nextIndex = currentSampleText.index(currentSampleText.startIndex, offsetBy: currentSampleText.count)
        guard nextIndex < masterPassword.endIndex else { return }

        if String(masterPassword[nextIndex]) == data.character {
            enrollmentHasError = false
            enrollmentErrorMessage = nil
            currentSampleText.append(data.character)
            currentSampleData.append(data)

            if currentSampleText == masterPassword {
                passwordSamples.append(currentSampleData)
                SensitiveDataCleaner.clearEnrollmentSample(text: &currentSampleText, data: &currentSampleData)
                if sampleIndex < EnrollmentConfig.requiredSamples - 1 {
                    sampleIndex += 1
                    resetCurrentSample()
                } else {
                    saveNewMasterPassword()
                }
            }
        } else {
            enrollmentHasError = true
            enrollmentErrorMessage = "That character was incorrect. Continue from the mistake."
        }
    }

    private func saveNewMasterPassword() {
        guard let rhythmProfile = RhythmProfile.from(
            passwordSamples: passwordSamples,
            password: masterPassword
        ) else {
            saveErrorMessage = ProfileStoreError.invalidRhythmProfile.localizedDescription
            return
        }

        do {
            try profileStore.changeMasterPassword(
                currentPassword: verifiedCurrentPassword,
                newPassword: masterPassword,
                rhythmProfile: rhythmProfile
            )
            SensitiveDataCleaner.clear(&verifiedCurrentPassword)
            SensitiveDataCleaner.clear(&masterPassword)
            SensitiveDataCleaner.clear(&repeatPassword)
            passwordSamples = []
            onComplete("Master password updated. Use your new password in the browser extension and Mac log in.")
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func backToVerify() {
        masterPassword = ""
        repeatPassword = ""
        passwordValidationMessage = nil
        step = .verifyCurrent
    }

    private func backToSetPassword() {
        resetCurrentSample()
        passwordSamples = []
        sampleIndex = 0
        step = .setNewPassword
    }

    private func cancelFlow() {
        SensitiveDataCleaner.clear(&verifiedCurrentPassword)
        SensitiveDataCleaner.clear(&masterPassword)
        SensitiveDataCleaner.clear(&repeatPassword)
        SensitiveDataCleaner.clearLoginAttempt(text: &verifyAttemptText, data: &verifyAttemptData)
        onCancel()
    }

    private func resetCurrentSample() {
        currentSampleData = []
        currentSampleText = ""
        enrollmentHasError = false
        enrollmentErrorMessage = nil
    }

    private func isDeleteKey(_ character: String) -> Bool {
        character == "\u{7f}" || character == "\u{8}"
    }
}
