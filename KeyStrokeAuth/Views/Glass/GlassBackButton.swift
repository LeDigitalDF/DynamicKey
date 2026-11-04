// GlassBackButton.swift
// Circular liquid glass back control for main detail navigation.

import SwiftUI

struct GlassBackButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        HStack {
            GlassCircleIconButton(
                systemImage: "chevron.left",
                accessibilityLabel: title,
                action: action
            )
            Spacer()
        }
    }
}
