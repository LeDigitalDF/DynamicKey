// SettingsCardInfoFlipButton.swift
// Shared “i” control for settings card headers — opens the info back face.
// Flow: tap → parent toggles flip to description; same chrome on every settings card type.

import SwiftUI

struct SettingsCardInfoFlipButton: View {
    var isShowingInfo: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("i")
                .font(.system(size: 14, weight: .bold, design: .serif))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 25, height: 25)
                .background {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isShowingInfo ? "Show card front" : "Show card description")
    }
}
