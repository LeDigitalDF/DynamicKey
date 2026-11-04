// GlassCircleIconButton.swift
// Circular liquid glass icon control — sidebar toggle, back navigation, toolbar actions.
// Flow: icon label → frosted circular glass surface → tap action.

import SwiftUI

struct GlassCircleIconButton: View {
    @Environment(\.glassPalette) private var palette

    let systemImage: String
    let accessibilityLabel: String
    var size: CGFloat = 34
    var iconColor: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor ?? palette.onGlassPrimary)
                .frame(width: size, height: size)
                .background {
                    GlassRoundedGlassSurface(cornerRadius: size / 2, tint: .neutral)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
