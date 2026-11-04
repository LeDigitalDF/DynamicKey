// SettingsRhythmLearningCardContent.swift
// Learn my typing rhythm card — continuous-learning toggle and optional threshold advice.
// Flow: toggle on top → when data supports it, one-line advice over a large suggested % watermark.

import SwiftUI

struct SettingsRhythmLearningCardContent: View {
    @ObservedObject private var adaptiveRhythm = AdaptiveRhythmStore.shared
    @Binding var continuousLearningEnabled: Bool
    let passThreshold: Int

    private var suggestedThreshold: Int? {
        adaptiveRhythm.suggestedThreshold(currentThreshold: passThreshold)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: suggestedThreshold == nil ? 0 : 10) {
            HStack(alignment: .center, spacing: 12) {
                Text("Continuously improve profile")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                GlassCapsuleBinaryToggle(
                    isOn: $continuousLearningEnabled,
                    offSystemImage: "pause.fill",
                    onSystemImage: "brain.head.profile",
                    onTint: .green,
                    accessibilityLabel: "Continuously improve typing profile"
                )
            }

            if let suggestion = suggestedThreshold {
                adviceRow(suggestion: suggestion)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func adviceRow(suggestion: Int) -> some View {
        (Text("Advice: ")
            .foregroundStyle(SettingsRhythmAdviceStyle.adviceLabelColor)
            .fontWeight(.semibold)
         + Text("Your recent sign-ins are very consistent. Consider raising the match threshold to \(suggestion)% for stronger security.")
            .foregroundStyle(.secondary))
        .font(.caption)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
