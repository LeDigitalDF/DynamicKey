// TrainingView.swift
// Step 1 enrollment: copy-type four random sentences to learn rhythm capture.

import SwiftUI

struct SentenceTrainingView: View {
    let currentSentenceIndex: Int
    let totalSentences: Int
    let currentSentence: String
    let typedText: String
    let hasError: Bool
    var isRetrainSession: Bool = false
    let onKeystroke: (KeystrokeData) -> Void
    let onBack: () -> Void

    var body: some View {
        PhaseScreenLayout {
            BackButton(title: "Back", action: onBack)

            PhaseHeader(
                title: isRetrainSession ? "Retrain Your Typing Rhythm" : "Step 1: Train Your Typing Rhythm",
                subtitle: "Type each sentence exactly as shown. DynamicKey learns your per-key timing."
            )

            GlassPanel {
                VStack(alignment: .leading, spacing: GlassTheme.itemSpacing) {
                    Text("What is happening?")
                        .font(.headline)
                    Text("DynamicKey learns how you type — how long you hold each key and the gap between keystrokes. This builds a rhythm profile that is hard for someone else to copy.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("What should you do?")
                        .font(.headline)
                    Text("Type each random sentence below at your normal pace. Green letters are correct; red marks the next character to fix.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(GlassTheme.padding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("Sentence \(currentSentenceIndex + 1) of \(totalSentences)")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .center)

            GlassPanel {
                Text(coloredSentence)
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(GlassTheme.padding)
            }

            if hasError {
                GlassInfoBanner(
                    kind: .danger,
                    message: "That character was incorrect. Continue from the red position."
                )
            }

            GlassSentenceTypingField(
                typedText: typedText,
                placeholder: "Type the sentence here…",
                onKeystroke: onKeystroke
            )
        }
    }

    private var coloredSentence: AttributedString {
        var result = AttributedString()
        for (index, character) in currentSentence.enumerated() {
            var segment = AttributedString(String(character))
            segment.foregroundColor = color(for: index)
            result.append(segment)
        }
        return result
    }

    private func color(for index: Int) -> Color {
        if index < typedText.count { return .green }
        return hasError && index == typedText.count ? .red : .primary
    }
}
