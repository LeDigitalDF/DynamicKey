// PhaseHeader.swift
// Consistent title and subtitle header for each enrollment phase.

import SwiftUI

struct PhaseHeader: View {
    @Environment(\.glassPalette) private var palette

    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var accent: Color = .accentColor

    var body: some View {
        VStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
            }

            Text(title)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(palette.onGlassPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            if let subtitle {
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(palette.onGlassSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct PhaseScreenLayout<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: GlassTheme.sectionSpacing) {
            content()
        }
        .frame(maxWidth: GlassTheme.maxContentWidth)
    }
}

struct AppScreenBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color.accentColor.opacity(colorScheme == .dark ? 0.08 : 0.05),
                Color(nsColor: .windowBackgroundColor),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}
