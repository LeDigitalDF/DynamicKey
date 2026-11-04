// SiteCredentialCardBackground.swift
// Per-site card backdrop — deterministic gradient from the origin (no image upload required).
// Flow: hash hostname → two accent colors → soft gradient under a glass scrim.

import SwiftUI

enum SiteCredentialCardBackground {
    static func gradientColors(for origin: String) -> [Color] {
        let seed = abs(origin.lowercased().hashValue)
        let hueA = Double(seed % 360) / 360.0
        let hueB = Double((seed / 360) % 360) / 360.0

        return [
            Color(hue: hueA, saturation: 0.55, brightness: 0.72),
            Color(hue: hueB, saturation: 0.48, brightness: 0.58),
        ]
    }
}

struct SiteCredentialCardBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    let origin: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: SiteCredentialCardBackground.gradientColors(for: origin),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(colorScheme == .dark ? 0.42 : 0.34)

            LinearGradient(
                colors: [
                    Color.black.opacity(colorScheme == .dark ? 0.28 : 0.08),
                    Color.black.opacity(colorScheme == .dark ? 0.48 : 0.16),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}
