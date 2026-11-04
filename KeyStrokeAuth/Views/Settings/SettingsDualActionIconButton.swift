// SettingsDualActionIconButton.swift
// Dual-action play-card foreground icon — white symbol with accent shadow and hover zoom.
// Flow: pointer over → font size grows (vector re-render, not scaleEffect) → tap runs the card action.

import SwiftUI

enum SettingsDualActionIconButtonStyle {
    static let foregroundIconSize: CGFloat = 42
    static let tapTargetSize: CGFloat = 60
    static let hoverScale: CGFloat = 2.5
}

struct SettingsDualActionIconButton: View {
    let systemImage: String
    let accentColor: Color
    let accessibilityLabel: String
    let action: () -> Void

    var foregroundIconSize: CGFloat = SettingsDualActionIconButtonStyle.foregroundIconSize
    var tapTargetSize: CGFloat = SettingsDualActionIconButtonStyle.tapTargetSize
    var hoverScale: CGFloat = SettingsDualActionIconButtonStyle.hoverScale

    @State private var isHovered = false

    /// Grow the symbol’s point size on hover — keeps SF Symbols sharp (scaleEffect rasterizes and pixelates).
    private var displayedIconSize: CGFloat {
        foregroundIconSize * (isHovered ? hoverScale : 1)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: displayedIconSize, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(
                    color: accentColor.opacity(isHovered ? 0.55 : 0.35),
                    radius: isHovered ? 10 : 6,
                    y: 2
                )
                .frame(width: tapTargetSize, height: tapTargetSize, alignment: .center)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isHovered)
        .accessibilityLabel(accessibilityLabel)
    }
}
