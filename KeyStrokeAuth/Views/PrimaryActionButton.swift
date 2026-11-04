// PrimaryActionButton.swift
// Primary action control backed by Liquid Glass styling.

import SwiftUI

struct PrimaryActionButton: View {
    let title: String
    var color: Color = .blue
    var isEnabled: Bool = true
    var expandsFullWidth: Bool = true
    var borderStyle: GlassCapsuleBorderStyle = .standard
    let action: () -> Void

    var body: some View {
        GlassButton(
            title: title,
            role: .primary,
            tint: color,
            isEnabled: isEnabled,
            expandsFullWidth: expandsFullWidth,
            submitOnReturn: true,
            borderStyle: borderStyle,
            action: action
        )
    }
}
