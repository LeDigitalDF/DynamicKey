// GlassLiquidCapsuleBorder.swift
// Capsule border with diagonal specular highlights (top-right and bottom-left glints).

import SwiftUI

struct GlassLiquidCapsuleBorder: View {
    @Environment(\.glassPalette) private var palette

    var lineWidth: CGFloat = 1.0

    var body: some View {
        Capsule()
            .strokeBorder(GlassSpecularBorderGradient(palette: palette), lineWidth: lineWidth)
    }
}

/// Pill-shaped tab bar outline — same specular border as MorphGlassTabBarShell / bottom period bar.
struct GlassMorphTabBarOutline: View {
    @Environment(\.glassPalette) private var palette

    var cornerRadius: CGFloat
    var lineWidth: CGFloat = 1.0

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(GlassSpecularBorderGradient(palette: palette), lineWidth: lineWidth)
    }
}

/// Shared angular specular stroke used by capsule fields and morph tab bar shells.
struct GlassSpecularBorderGradient: ShapeStyle {
    let palette: GlassPalette

    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        AngularGradient(
            stops: [
                .init(color: palette.borderHighlightStrong, location: 0.0),
                .init(color: palette.borderHighlightSoft, location: 0.22),
                .init(color: palette.borderHighlightSoft.opacity(0.45), location: 0.38),
                .init(color: palette.borderHighlightStrong.opacity(0.88), location: 0.50),
                .init(color: palette.borderHighlightSoft.opacity(0.55), location: 0.68),
                .init(color: palette.borderHighlightSoft, location: 0.82),
                .init(color: palette.borderHighlightStrong, location: 1.0),
            ],
            center: .center,
            startAngle: .degrees(-45),
            endAngle: .degrees(315)
        )
    }
}
