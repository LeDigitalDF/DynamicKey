// GlassReferenceCapsuleBorder.swift
// Reference capsule stroke — glow concentrated at bottom-left and top-right corners only.
// Uses RadialGradient with an absolute pixel radius (not UnitPoint-relative) so the glow
// stays corner-sized instead of stretching into a left/right or top/bottom band on wide fields.

import SwiftUI

struct GlassReferenceCapsuleBorder: View {
    @Environment(\.glassPalette) private var palette

    var lineWidth: CGFloat = 1.35

    var body: some View {
        GeometryReader { proxy in
            let glowRadius = max(proxy.size.height * 1.15, 26)

            ZStack {
                capsuleStroke
                    .mask(cornerGlow(center: UnitPoint(x: 0, y: 1), radius: glowRadius))

                capsuleStroke
                    .mask(cornerGlow(center: UnitPoint(x: 1, y: 0), radius: glowRadius))
            }
        }
        .allowsHitTesting(false)
    }

    private var capsuleStroke: some View {
        Capsule(style: .continuous)
            .stroke(
                palette.borderHighlightStrong.opacity(0.9),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
    }

    /// Circular falloff anchored to one exact corner point, sized in real points so it doesn't
    /// stretch across the whole width of wide capsules.
    private func cornerGlow(center: UnitPoint, radius: CGFloat) -> some View {
        RadialGradient(
            stops: [
                .init(color: .white, location: 0.0),
                .init(color: .white.opacity(0.7), location: 0.28),
                .init(color: .white.opacity(0.18), location: 0.62),
                .init(color: .clear, location: 1.0),
            ],
            center: center,
            startRadius: 0,
            endRadius: radius
        )
    }
}

enum GlassCapsuleBorderStyle {
    case standard
    case referenceDiagonal
    /// No border overlay at all — flat capsule fill with no highlight stroke.
    case none
}
