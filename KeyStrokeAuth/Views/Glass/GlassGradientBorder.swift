// GlassGradientBorder.swift
// Gradient stroke overlays for Liquid Glass fields and controls.

import SwiftUI

struct GlassGradientBorder: View {
    var cornerRadius: CGFloat = GlassTheme.cornerRadius
    var lineWidth: CGFloat = 1.5

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.primary.opacity(0.5),
                        Color.primary.opacity(0.14),
                        Color.primary.opacity(0.42),
                    ],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                ),
                lineWidth: lineWidth
            )
    }
}

struct GlassClockwiseGradientBorder: View {
    var cornerRadius: CGFloat = GlassTheme.passwordFieldCornerRadius
    var lineWidth: CGFloat = 1.5

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                AngularGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color.primary.opacity(0.72), location: 0.00),
                        .init(color: Color.primary.opacity(0.16), location: 0.25),
                        .init(color: Color.primary.opacity(0.72), location: 0.50),
                        .init(color: Color.primary.opacity(0.16), location: 0.75),
                        .init(color: Color.primary.opacity(0.72), location: 1.00),
                    ]),
                    center: .center,
                    startAngle: .degrees(225),
                    endAngle: .degrees(585)
                ),
                lineWidth: lineWidth
            )
    }
}
