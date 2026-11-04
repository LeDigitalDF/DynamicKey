// GlassCapsuleSurface.swift
// Shared liquid glass capsule fill, border, and shadow used by the password field and action buttons.

import SwiftUI

enum GlassCapsuleTint {
    case none
    case verify
    case blue
    case enroll
    case orange
    case green
    case neutral
    case destructive
}

struct GlassCapsuleSurface: View {
    @Environment(\.glassPalette) private var palette

    var tint: GlassCapsuleTint = .none
    var borderStyle: GlassCapsuleBorderStyle = .standard

    var body: some View {
        ZStack {
            baseGlassFill
            tintOverlay
        }
        .overlay {
            if borderStyle == .standard {
                innerTopHighlight
            }
        }
        .overlay {
            if borderStyle == .standard {
                GlassLiquidCapsuleBorder()
            }
        }
        .clipShape(Capsule())
        .overlay {
            if borderStyle == .referenceDiagonal {
                GlassReferenceCapsuleBorder()
            }
        }
        .shadow(color: palette.shadowStrong, radius: 8, x: 0, y: 4)
        .shadow(color: palette.shadowSoft, radius: 2, x: 0, y: 1)
    }

    private var baseGlassFill: some View {
        ZStack {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [palette.surfaceTop, palette.surfaceMid, palette.surfaceBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Capsule()
                .fill(.ultraThinMaterial)
                .opacity(palette.materialOpacity)

            if borderStyle == .standard {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [palette.specularTop, palette.specularMid, palette.specularBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
    }

    @ViewBuilder
    private var tintOverlay: some View {
        switch tint {
        case .none:
            EmptyView()
        case .verify:
            Capsule()
                .fill(GlassTheme.verifyGradient)
                .opacity(0.52)
        case .blue:
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.58),
                            Color(red: 0.12, green: 0.28, blue: 0.72).opacity(0.48),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        case .enroll:
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.purple.opacity(0.58),
                            Color(red: 0.42, green: 0.16, blue: 0.72).opacity(0.50),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        case .orange:
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.orange.opacity(0.62),
                            Color(red: 0.72, green: 0.36, blue: 0.08).opacity(0.52),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        case .green:
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.green.opacity(0.58),
                            Color(red: 0.10, green: 0.52, blue: 0.28).opacity(0.50),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        case .neutral:
            Capsule()
                .fill(palette.onGlassPrimary.opacity(0.08))
        case .destructive:
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.red.opacity(0.58),
                            Color(red: 0.55, green: 0.10, blue: 0.14).opacity(0.50),
                        ],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    )
                )
        }
    }

    private var innerTopHighlight: some View {
        Capsule()
            .strokeBorder(
                LinearGradient(
                    colors: [palette.borderHighlightStrong.opacity(0.22), Color.clear],
                    startPoint: .top,
                    endPoint: .center
                ),
                lineWidth: 0.75
            )
            .padding(1.5)
            .blendMode(.overlay)
    }
}
