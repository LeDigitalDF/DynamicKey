// RetrainTypingProfileFlowView.swift
// Slide-over flow: warning → four-sentence warm-up → three password rhythm samples → overwrite profile.
// Flow: intro → SentenceTrainingView → hidden password samples → ProfileStore.updateRhythmProfile.

import SwiftUI

struct RetrainTypingProfileFlowView: View {
    var isCompactCard: Bool = false
    let onComplete: () -> Void
    let onCancel: () -> Void

    private enum Step {
        case intro
        case sentenceTraining
        case passwordEnrollment
    }

    @State private var step: Step = .intro

    @State private var trainingSentences: [String] = []
    @State private var currentSentenceIndex = 0
    @State private var sentenceTypedText = ""
    @State private var sentenceHasError = false

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

    var body: some View {
        VStack(alignment: .leading, spacing: outerSpacing) {
            switch step {
            case .intro:
                introStep
            case .sentenceTraining:
                sentenceTrainingStep
            case .passwordEnrollment:
                passwordEnrollmentStep
            }

            if let saveErrorMessage {
                GlassInfoBanner(kind: .danger, message: saveErrorMessage)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Warn that retraining replaces the stored rhythm profile.
    private var introStep: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            if isCompactCard {
                Text("This replaces your typing rhythm profile with fresh measurements.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("What happens next")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("You will type four random sentences, then type your master password three times. Your password and saved website credentials stay the same — only your rhythm fingerprint is replaced.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.secondary.opacity(0.10))
                }
            } else {
                Text("Retrain Typing Profile")
                    .font(.title3.weight(.bold))

                Text("This will overwrite your current typing rhythm profile with new measurements from a fresh training session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                GlassPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("What happens next")
                            .font(.subheadline.weight(.semibold))
                        Text("You will type four random sentences, then type your master password three times. Your password and saved website credentials stay the same — only your rhythm fingerprint is replaced.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(GlassTheme.padding)
                }
            }

            compactCardButtonRow {
                flowActionButton(title: "Cancel", role: .secondary, action: onCancel)
                flowActionButton(title: "Start Retraining", role: .primary, action: beginSentenceTraining)
            }
        }
    }

    // Four-sentence warm-up using the same UI as first-time enrollment.
    private var sentenceTrainingStep: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            Text("Sentence \(currentSentenceIndex + 1) of \(trainingSentences.count)")
                .font(isCompactCard ? .caption.weight(.semibold) : .subheadline.weight(.semibold))

            Text("Type each sentence exactly as shown at your normal pace.")
                .font(isCompactCard ? .caption2 : .caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Group {
                if isCompactCard {
                    Text(coloredSentence)
                        .font(.caption.weight(.medium))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.secondary.opacity(0.10))
                        }
                } else {
                    GlassPanel {
                        Text(coloredSentence)
                            .font(.body.weight(.medium))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(GlassTheme.padding)
                    }
                }
            }

            if sentenceHasError {
                GlassInfoBanner(
                    kind: .danger,
                    message: "That character was incorrect. Continue from the red position."
                )
            }

            GlassSentenceTypingField(
                typedText: sentenceTypedText,
                placeholder: "Type the sentence here…",
                onKeystroke: handleSentenceKeystroke
            )

            compactCardButtonRow {
                flowActionButton(title: "Cancel", role: .secondary, action: onCancel)
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

    // Three hidden password samples to rebuild the per-key rhythm averages.
    private var passwordEnrollmentStep: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            if isCompactCard {
                Text("Sample \(sampleIndex + 1) of \(EnrollmentConfig.requiredSamples) — press Enter after each password.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Password rhythm")
                    .font(.title3.weight(.bold))

                Text("Type your current master password \(EnrollmentConfig.requiredSamples) times (Enter after each).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                GlassPanel {
                    Text("Sample \(sampleIndex + 1) of \(EnrollmentConfig.requiredSamples)")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(GlassTheme.padding)
                }
            }

            PasswordDotsDisplay(
                length: currentSampleText.count,
                caption: isCompactCard ? "Type here, then press Enter." : "Click here if typing does not respond",
                usesFlexibleWidth: isCompactCard,
                fieldHeight: isCompactCard ? 30 : GlassTheme.passwordFieldHeight,
                stackSpacing: isCompactCard ? 6 : 10
            )

            if enrollmentHasError {
                GlassInfoBanner(
                    kind: .danger,
                    message: enrollmentErrorMessage ?? "Incorrect input. Try again."
                )
            } else if !isCompactCard {
                Text("Press Enter when you have finished typing your password.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            compactCardButtonRow {
                flowActionButton(title: "Clear Sample", role: .secondary, action: clearCurrentSample)
            }

            KeystrokeMonitorViewRepresentable(onKeystroke: handlePasswordSampleKeystroke)
                .frame(maxWidth: .infinity, minHeight: isCompactCard ? 1 : 44)
                .opacity(0.01)
        }
    }

    private var coloredSentence: AttributedString {
        guard currentSentenceIndex < trainingSentences.count else { return AttributedString() }
        let currentSentence = trainingSentences[currentSentenceIndex]
        var result = AttributedString()
        for (index, character) in currentSentence.enumerated() {
            var segment = AttributedString(String(character))
            if index < sentenceTypedText.count {
                segment.foregroundColor = .green
            } else if sentenceHasError && index == sentenceTypedText.count {
                segment.foregroundColor = .red
            }
            result.append(segment)
        }
        return result
    }

    private func beginSentenceTraining() {
        trainingSentences = TrainingSentenceProvider.randomSentences()
        currentSentenceIndex = 0
        sentenceTypedText = ""
        sentenceHasError = false
        step = .sentenceTraining
    }

    private func handleSentenceKeystroke(_ data: KeystrokeData) {
        guard currentSentenceIndex < trainingSentences.count else { return }

        if isDeleteKey(data.character) {
            guard !sentenceTypedText.isEmpty else { return }
            sentenceTypedText.removeLast()
            sentenceHasError = false
            return
        }

        let currentSentence = trainingSentences[currentSentenceIndex]
        let nextIndex = sentenceTypedText.count
        guard nextIndex < currentSentence.count else { return }

        let targetIndex = currentSentence.index(currentSentence.startIndex, offsetBy: nextIndex)
        if String(currentSentence[targetIndex]) == data.character {
            sentenceHasError = false
            sentenceTypedText.append(data.character)
            if sentenceTypedText == currentSentence {
                completeCurrentSentence()
            }
        } else {
            sentenceHasError = true
        }
    }

    private func completeCurrentSentence() {
        sentenceTypedText = ""
        sentenceHasError = false

        if currentSentenceIndex < trainingSentences.count - 1 {
            currentSentenceIndex += 1
        } else {
            sampleIndex = 0
            passwordSamples = []
            resetCurrentSample()
            step = .passwordEnrollment
        }
    }

    private func handlePasswordSampleKeystroke(_ data: KeystrokeData) {
        if data.character == "\r" {
            completePasswordSample()
            return
        }

        if isDeleteKey(data.character) {
            guard !currentSampleText.isEmpty, !currentSampleData.isEmpty else { return }
            currentSampleText.removeLast()
            currentSampleData.removeLast()
            enrollmentHasError = false
            enrollmentErrorMessage = nil
            return
        }

        enrollmentHasError = false
        enrollmentErrorMessage = nil
        currentSampleData.append(data)
        currentSampleText.append(data.character)
    }

    private func completePasswordSample() {
        guard !currentSampleText.isEmpty else {
            enrollmentHasError = true
            enrollmentErrorMessage = "Type your password, then press Enter."
            return
        }

        guard profileStore.verifyPassword(currentSampleText) else {
            enrollmentHasError = true
            enrollmentErrorMessage = "Incorrect password. Use Clear Sample and try again."
            return
        }

        enrollmentHasError = false
        enrollmentErrorMessage = nil
        passwordSamples.append(currentSampleData)
        SensitiveDataCleaner.clearEnrollmentSample(text: &currentSampleText, data: &currentSampleData)

        if sampleIndex < EnrollmentConfig.requiredSamples - 1 {
            sampleIndex += 1
            resetCurrentSample()
        } else {
            saveRetrainedProfile()
        }
    }

    private func saveRetrainedProfile() {
        guard let lastSample = passwordSamples.last else { return }
        let rebuiltPassword = lastSample.map(\.character).joined()

        guard let rhythmProfile = RhythmProfile.from(
            passwordSamples: passwordSamples,
            password: rebuiltPassword
        ) else {
            saveErrorMessage = ProfileStoreError.invalidRhythmProfile.localizedDescription
            return
        }

        do {
            try profileStore.updateRhythmProfile(rhythmProfile, verifyingPassword: rebuiltPassword)
            onComplete()
        } catch {
            saveErrorMessage = error.localizedDescription
            passwordSamples = []
            sampleIndex = 0
            resetCurrentSample()
        }
    }

    private func clearCurrentSample() {
        resetCurrentSample()
        enrollmentErrorMessage = nil
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
