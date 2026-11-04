// GlassPanel.swift
// Liquid Glass surface wrapper for cards and grouped content.

import SwiftUI

struct GlassPanel<Content: View>: View {
    var cornerRadius: CGFloat = GlassTheme.cornerRadius
    @ViewBuilder var content: () -> Content

    var body: some View {
        NSGlassEffectContainerRepresentable(cornerRadius: cornerRadius, content: content)
            .frame(maxWidth: .infinity, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
