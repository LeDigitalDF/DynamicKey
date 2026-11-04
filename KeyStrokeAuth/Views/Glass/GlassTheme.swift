// GlassTheme.swift
// Shared layout, Liquid Glass constants, and light/dark palette tokens for macOS 26 UI.

import SwiftUI

enum GlassTheme {
    static let cornerRadius: CGFloat = 20
    static let padding: CGFloat = 20
    static let sectionSpacing: CGFloat = 24
    static let itemSpacing: CGFloat = 16
    static let maxContentWidth: CGFloat = 560
    static let passwordFieldWidth: CGFloat = 300
    static let passwordFieldHeight: CGFloat = 40
    static let passwordFieldCornerRadius: CGFloat = 20
    static let actionButtonMinWidth: CGFloat = 250
    static let actionButtonMaxWidth: CGFloat = 250
    static let actionButtonHeight: CGFloat = 44
    /// Label color for glass and sparkle buttons — black reads clearly over animated button fills.
    static let buttonLabelColor = Color.black

    static let verifyGradient = LinearGradient(
        colors: [
            Color(red: 0.12, green: 0.78, blue: 0.82),
            Color(red: 0.36, green: 0.38, blue: 0.98),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// Theme-aware colors for glass surfaces, text, borders, and overlays.
struct GlassPalette {
    let surfaceTop: Color
    let surfaceMid: Color
    let surfaceBottom: Color
    let materialOpacity: Double
    let specularTop: Color
    let specularMid: Color
    let specularBottom: Color
    let onGlassPrimary: Color
    let onGlassSecondary: Color
    let shadowStrong: Color
    let shadowSoft: Color
    let slideOverScrim: Color
    let slideOverMaterialOpacity: Double
    let borderHighlightStrong: Color
    let borderHighlightSoft: Color
    let landingSurfaceTop: Color
    let landingSurfaceMid: Color
    let landingSurfaceBottom: Color
    let rhythmLine: Color
    let fieldPlaceholder: Color
    let fieldCaret: Color
    let themeTrackFill: Color
    let themeThumbFill: Color
    let credentialEmailAccent: Color

    static let dark = GlassPalette(
        surfaceTop: Color(red: 0.10, green: 0.12, blue: 0.16).opacity(0.92),
        surfaceMid: Color(red: 0.18, green: 0.20, blue: 0.26).opacity(0.72),
        surfaceBottom: Color(red: 0.10, green: 0.11, blue: 0.15).opacity(0.94),
        materialOpacity: 0.55,
        specularTop: Color.white.opacity(0.10),
        specularMid: Color.clear,
        specularBottom: Color.black.opacity(0.18),
        onGlassPrimary: Color.white.opacity(0.92),
        onGlassSecondary: Color.white.opacity(0.72),
        shadowStrong: Color.black.opacity(0.45),
        shadowSoft: Color.black.opacity(0.20),
        slideOverScrim: Color(red: 0.08, green: 0.09, blue: 0.12).opacity(0.82),
        slideOverMaterialOpacity: 0.92,
        borderHighlightStrong: Color.white.opacity(0.92),
        borderHighlightSoft: Color.white.opacity(0.14),
        landingSurfaceTop: Color(red: 0.04, green: 0.05, blue: 0.09),
        landingSurfaceMid: Color(red: 0.07, green: 0.09, blue: 0.14),
        landingSurfaceBottom: Color(red: 0.05, green: 0.06, blue: 0.10),
        rhythmLine: Color.white.opacity(0.06),
        fieldPlaceholder: Color.white.opacity(0.45),
        fieldCaret: Color.white.opacity(0.75),
        themeTrackFill: Color(red: 0.12, green: 0.14, blue: 0.18).opacity(0.88),
        themeThumbFill: Color(red: 0.22, green: 0.24, blue: 0.30).opacity(0.95),
        credentialEmailAccent: Color(red: 0.52, green: 0.76, blue: 1.0)
    )

    static let light = GlassPalette(
        surfaceTop: Color(red: 0.98, green: 0.99, blue: 1.00).opacity(0.92),
        surfaceMid: Color(red: 0.90, green: 0.92, blue: 0.96).opacity(0.72),
        surfaceBottom: Color(red: 0.94, green: 0.95, blue: 0.98).opacity(0.94),
        materialOpacity: 0.55,
        specularTop: Color.white.opacity(0.55),
        specularMid: Color.clear,
        specularBottom: Color.black.opacity(0.06),
        onGlassPrimary: Color(red: 0.10, green: 0.12, blue: 0.16),
        onGlassSecondary: Color(red: 0.10, green: 0.12, blue: 0.16).opacity(0.80),
        shadowStrong: Color.black.opacity(0.16),
        shadowSoft: Color.black.opacity(0.08),
        slideOverScrim: Color(red: 0.96, green: 0.97, blue: 0.99).opacity(0.82),
        slideOverMaterialOpacity: 0.92,
        borderHighlightStrong: Color.white.opacity(0.88),
        borderHighlightSoft: Color.black.opacity(0.16),
        landingSurfaceTop: Color(red: 0.94, green: 0.95, blue: 0.98),
        landingSurfaceMid: Color(red: 0.88, green: 0.91, blue: 0.96),
        landingSurfaceBottom: Color(red: 0.92, green: 0.94, blue: 0.98),
        rhythmLine: Color.black.opacity(0.08),
        fieldPlaceholder: Color.primary.opacity(0.38),
        fieldCaret: Color.primary.opacity(0.72),
        themeTrackFill: Color(red: 0.90, green: 0.92, blue: 0.96).opacity(0.94),
        themeThumbFill: Color.white.opacity(0.98),
        credentialEmailAccent: Color(red: 0.05, green: 0.38, blue: 0.74)
    )
}

private struct GlassPaletteKey: EnvironmentKey {
    static let defaultValue: GlassPalette = .dark
}

extension EnvironmentValues {
    var glassPalette: GlassPalette {
        get { self[GlassPaletteKey.self] }
        set { self[GlassPaletteKey.self] = newValue }
    }
}
