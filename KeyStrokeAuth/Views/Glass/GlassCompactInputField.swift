// GlassCompactInputField.swift
// Compact single-line glass text field — thin border, small focus ring, placeholder overlay.
// Flow: caption optional in parent → field with manualCredential-style chrome → focus/disabled states.

import SwiftUI

struct GlassCompactInputField: View {
    @Environment(\.glassPalette) private var palette

    @Binding var text: String
    let placeholder: String
    @FocusState.Binding var isFocused: Bool
    var isSecure: Bool = false
    var cornerRadius: CGFloat = 6
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        Group {
            if isSecure {
                SecureField("", text: $text)
            } else {
                TextField("", text: $text)
            }
        }
        .glassCompactInputStyle(isFocused: isFocused, cornerRadius: cornerRadius)
        .focused($isFocused)
        .onSubmit { onSubmit?() }
        .overlay(alignment: .leading) {
            if text.isEmpty && !isFocused {
                Text(placeholder)
                    .font(.callout)
                    .foregroundStyle(palette.fieldPlaceholder)
                    .padding(.horizontal, 8)
                    .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    func glassCompactInputStyle(isFocused: Bool, cornerRadius: CGFloat = 6) -> some View {
        textFieldStyle(.plain)
            .font(.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isFocused ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.16),
                        lineWidth: isFocused ? 1 : 0.5
                    )
            }
            .focusEffectDisabled()
    }
}
