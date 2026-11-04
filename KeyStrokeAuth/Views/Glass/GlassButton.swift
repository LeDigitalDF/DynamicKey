// GlassButton.swift
// Liquid glass capsule buttons matching the password field styling.

import SwiftUI

enum GlassButtonRole {
    case primary
    case secondary
    case destructive
}

struct GlassButton: View {
    let title: String
    var role: GlassButtonRole = .primary
    var tint: Color = .accentColor
    var capsuleTintOverride: GlassCapsuleTint? = nil
    var isEnabled: Bool = true
    var expandsFullWidth: Bool = true
    var fixedWidth: CGFloat? = nil
    var submitOnReturn: Bool = false
    var borderStyle: GlassCapsuleBorderStyle = .standard
    let action: () -> Void

    private var nonExpandingWidth: CGFloat {
        fixedWidth ?? GlassTheme.actionButtonMaxWidth
    }

    var body: some View {
        Group {
            if submitOnReturn {
                button.keyboardShortcut(.return, modifiers: [])
            } else {
                button
            }
        }
        .frame(
            minWidth: expandsFullWidth ? nil : nonExpandingWidth,
            maxWidth: expandsFullWidth ? .infinity : nonExpandingWidth
        )
    }

    private var button: some View {
        Button(action: action) {
            Text(title)
                .font(.headline.weight(.semibold))
                .frame(maxWidth: expandsFullWidth ? .infinity : nil)
                .frame(minHeight: GlassTheme.actionButtonHeight)
                .padding(.horizontal, 24)
                .background {
                    GlassCapsuleSurface(tint: resolvedCapsuleTint, borderStyle: borderStyle)
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(foregroundColor)
        .opacity(isEnabled ? 1 : 0.45)
        .disabled(!isEnabled)
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

struct GlassTextButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                GlassCapsuleSurface(tint: .neutral)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(GlassTheme.buttonLabelColor)
        .accessibilityLabel(title)
    }
}
