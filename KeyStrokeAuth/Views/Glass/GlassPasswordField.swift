// GlassPasswordField.swift
// Liquid glass capsule password entry field matching macOS glass search-bar styling.

import SwiftUI

struct GlassPasswordField: View {
    @Environment(\.glassPalette) private var palette

    let length: Int
    var caption: String? = nil
    // Border appearance for the capsule; `.none` removes the gradient border (used on the login screen).
    var borderStyle: GlassCapsuleBorderStyle = .standard
    /// When true, the capsule stretches to the card content width instead of the login field width.
    var usesFlexibleWidth: Bool = false
    var fieldHeight: CGFloat = GlassTheme.passwordFieldHeight
    var stackSpacing: CGFloat = 10

    @State private var isCursorVisible = true

    var body: some View {
        VStack(spacing: stackSpacing) {
            ZStack {
                fieldContent
            }
            .frame(maxWidth: .infinity, minHeight: fieldHeight, maxHeight: fieldHeight)
            .background {
                GlassCapsuleSurface(tint: .none, borderStyle: borderStyle)
            }
            .accessibilityLabel("Password length \(length) characters")

            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(palette.onGlassSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: usesFlexibleWidth ? .infinity : GlassTheme.passwordFieldWidth)
    }

    private var fieldContent: some View {
        HStack(spacing: 5) {
            ForEach(0..<length, id: \.self) { _ in
                Circle()
                    .frame(width: 8, height: 8)
                    .foregroundStyle(palette.onGlassPrimary.opacity(0.88))
            }

            Rectangle()
                .frame(width: 2, height: 16)
                .foregroundStyle(palette.fieldCaret)
                .opacity(isCursorVisible ? 1 : 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .onAppear(perform: startCursorBlink)
    }

    private func startCursorBlink() {
        withAnimation(.easeInOut(duration: 0.53).repeatForever(autoreverses: true)) {
            isCursorVisible = false
        }
    }
}

/// Visible or secure password entry field with optional reveal toggle.
struct GlassPasswordTextField: View {
    @Environment(\.glassPalette) private var palette

    let title: String
    let placeholder: String
    @Binding var text: String
    var fieldWidth: CGFloat? = nil
    var borderStyle: GlassCapsuleBorderStyle = .standard
    var isSecure: Bool = false
    var onSubmit: (() -> Void)? = nil
    /// When true, the field receives keyboard focus automatically when it appears.
    var autoFocusOnAppear: Bool = false

    @State private var isRevealed = false
    @FocusState private var isFocused: Bool

    private var resolvedFieldWidth: CGFloat {
        fieldWidth ?? GlassTheme.passwordFieldWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 0) {
                Group {
                    if isSecure && !isRevealed {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(palette.onGlassPrimary)
                .focused($isFocused)
                .padding(.leading, 20)
                .padding(.trailing, isSecure ? 8 : 20)

                if isSecure {
                    Button {
                        isRevealed.toggle()
                    } label: {
                        Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
                            .font(.body.weight(.medium))
                            .foregroundStyle(palette.onGlassSecondary)
                            .frame(width: 36, height: GlassTheme.passwordFieldHeight)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
                    .padding(.trailing, 8)
                }
            }
            .frame(
                width: fieldWidth == nil ? nil : resolvedFieldWidth,
                height: GlassTheme.passwordFieldHeight,
                alignment: .leading
            )
            .frame(maxWidth: fieldWidth == nil ? .infinity : resolvedFieldWidth)
            .background {
                GlassCapsuleSurface(tint: .none, borderStyle: borderStyle)
            }
            .onSubmit { onSubmit?() }
            .accessibilityLabel(title)
        }
        .frame(
            width: fieldWidth == nil ? nil : resolvedFieldWidth,
            alignment: .leading
        )
        .frame(maxWidth: fieldWidth == nil ? .infinity : resolvedFieldWidth, alignment: .leading)
        .onAppear {
            guard autoFocusOnAppear else { return }
            // Defer a runloop tick so the field is in the hierarchy before requesting focus.
            DispatchQueue.main.async { isFocused = true }
        }
    }
}

/// Backward-compatible alias used by login and enrollment screens.
struct PasswordDotsDisplay: View {
    let length: Int
    var caption: String? = nil
    // Border appearance for the capsule; `.none` removes the gradient border (used on the login screen).
    var borderStyle: GlassCapsuleBorderStyle = .standard
    var usesFlexibleWidth: Bool = false
    var fieldHeight: CGFloat = GlassTheme.passwordFieldHeight
    var stackSpacing: CGFloat = 10

    var body: some View {
        GlassPasswordField(
            length: length,
            caption: caption,
            borderStyle: borderStyle,
            usesFlexibleWidth: usesFlexibleWidth,
            fieldHeight: fieldHeight,
            stackSpacing: stackSpacing
        )
    }
}
