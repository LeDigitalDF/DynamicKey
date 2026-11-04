// SettingsCompactButton.swift
// Smaller glass capsule buttons for dense settings sections.
// Flow: subheadline label → tinted GlassCapsuleSurface → tap action.

import SwiftUI

struct SettingsCompactButton: View {
    let title: String
    var role: GlassButtonRole = .secondary
    var tint: Color = .accentColor
    var capsuleTintOverride: GlassCapsuleTint? = nil
    var usesCompactHeight: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.vertical, usesCompactHeight ? 5 : 8)
                .padding(.horizontal, 16)
                .background {
                    GlassCapsuleSurface(tint: resolvedCapsuleTint)
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(foregroundColor)
        .accessibilityLabel(title)
    }

    private var resolvedCapsuleTint: GlassCapsuleTint {
        if let capsuleTintOverride {
            return capsuleTintOverride
        }
        switch role {
        case .primary:
            return tint == .blue ? .blue : .verify
        case .secondary:
            return .neutral
        case .destructive:
            return .destructive
        }
    }

    private var foregroundColor: Color {
        GlassTheme.buttonLabelColor
    }
}
