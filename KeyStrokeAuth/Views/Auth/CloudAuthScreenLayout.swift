// CloudAuthScreenLayout.swift
// Shared spacing and widths for M6 cloud auth and local vault enrollment screens.
// Flow: lettertype header → narrow flat fields → shorter CTA button with diagonal border.

import SwiftUI

enum CloudAuthScreenLayout {
    static let titleLetterHeight: CGFloat = 34
    static let titleLetterSpacing: CGFloat = 2
    static let titleWordSpacing: CGFloat = 14
    static let headerTopPadding: CGFloat = 20
    static let headerBottomPadding: CGFloat = 36
    static let fieldSpacing: CGFloat = 12
    static let formToButtonSpacing: CGFloat = 36
    static let fieldWidth: CGFloat = GlassTheme.maxContentWidth * 0.62
    static let buttonWidth: CGFloat = GlassTheme.maxContentWidth * 0.40
}
