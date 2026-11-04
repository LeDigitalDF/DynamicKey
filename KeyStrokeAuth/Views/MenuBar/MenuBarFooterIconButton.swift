// MenuBarFooterIconButton.swift
// Glass bar-style footer control for Preferences and Quit — matches paired-browser / action bars.
//
// Flow: hover → liquid glass lift → tap action.

import SwiftUI

struct MenuBarFooterIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let tint: Color
    let action: () -> Void

    @State private var isHovered = false

    private let cornerRadius: CGFloat = 12

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isHovered ? tint : tint.opacity(0.88))
                .frame(width: 44, height: 32)
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.clear)
                        .glassEffect()
                        .overlay {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(tint.opacity(isHovered ? 0.22 : 0.10))
                        }
                }
                .scaleEffect(isHovered ? 1.045 : 1)
                .shadow(
                    color: .black.opacity(isHovered ? 0.22 : 0),
                    radius: isHovered ? 8 : 0,
                    y: isHovered ? 3 : 0
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.68), value: isHovered)
        .accessibilityLabel(accessibilityLabel)
    }
}
