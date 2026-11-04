// HomeWidgetCard.swift
// macOS widget-style glass card shell for Home dashboard zones.
// Flow: optional title → content on GlassRoundedGlassSurface with equal flex in grids.

import SwiftUI

struct HomeWidgetCard<Content: View>: View {
    var title: String? = nil
    // When true, the card uses the real Liquid Glass material (NSGlassEffectView) instead of the
    // simulated gray glass surface. Enabled on all Home dashboard cards.
    var usesLiquidGlass: Bool = false
    @ViewBuilder var content: () -> Content

    @Environment(\.glassPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.onGlassPrimary)
            }

            content()
        }
        .padding(GlassTheme.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            if usesLiquidGlass {
                // Real Liquid Glass — transparent + blurred, samples the animated dashboard behind it.
                LiquidGlassSurface(cornerRadius: GlassTheme.cornerRadius)
            } else {
                GlassRoundedGlassSurface(cornerRadius: GlassTheme.cornerRadius, tint: .none)
            }
        }
    }
}
