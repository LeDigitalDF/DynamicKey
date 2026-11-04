// SettingsRoundIconButton.swift
// Round liquid-glass icon button with a hover tooltip for compact Settings cards.
// Flow: hover shows the native `.help` tooltip → a single tap fires the action.
// Note: the tooltip uses `.help` (not a `.popover`) on purpose. A hover-driven popover
// is a transient window that swallows the first click to dismiss itself, which forced a
// second click before the button activated. `.help` shows the text without stealing clicks.

import SwiftUI

struct SettingsRoundIconButton: View {
    let systemImage: String
    var tint: GlassCapsuleTint = .blue
    let helpText: String
    let accessibilityLabel: String
    let action: () -> Void

    private let buttonSize: CGFloat = 48

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: buttonSize, height: buttonSize)
                .background {
                    GlassCapsuleSurface(tint: tint)
                        .clipShape(Circle())
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .help(helpText)
    }
}
