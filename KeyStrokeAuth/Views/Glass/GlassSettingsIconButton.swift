// GlassSettingsIconButton.swift
// Sidebar settings gear with a subtle rotation animation on hover.
// Flow: hover detected → gear rotates → tap opens Settings.

import SwiftUI

struct GlassSettingsIconButton: View {
    let accessibilityLabel: String
    let action: () -> Void

    @Environment(\.glassPalette) private var palette
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.title3)
                .foregroundStyle(isHovered ? palette.onGlassPrimary : palette.onGlassSecondary)
                .rotationEffect(.degrees(isHovered ? 90 : 0))
                .scaleEffect(isHovered ? 1.08 : 1.0)
                .animation(.spring(response: 0.35, dampingFraction: 0.68), value: isHovered)
        }
        .buttonStyle(.plain)
        .onContinuousHover { phase in
            switch phase {
            case .active:
                isHovered = true
            case .ended:
                isHovered = false
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }
}
