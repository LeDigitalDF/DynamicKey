// MainDetailSectionHeader.swift
// Centered detail header with app logo (Home) or colored section icon — shared across main panes.
// Flow: centered icon → centered title + subtitle; used by every sidebar detail view.

import SwiftUI

struct MainDetailSectionHeader: View {
    let section: MainSidebarSection
    let subtitle: String
    var useAppLogo: Bool = false
    var showsSectionIcon: Bool = true
    /// Kept for call-site compatibility; header is centered so back-button inset is unused.
    var indentsForBackButton: Bool = false

    @Environment(\.glassPalette) private var palette

    private let headerIconSize: CGFloat = 36

    private var sectionCornerRadius: CGFloat {
        headerIconSize * (GlassTheme.cornerRadius / 56)
    }

    var body: some View {
        VStack(spacing: 12) {
            if showsSectionIcon {
                if useAppLogo {
                    DynamicKeyBrandLogo(size: headerIconSize)
                } else {
                    sectionIconBadge
                }
            }

            VStack(spacing: 4) {
                Text(section.title)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(palette.onGlassPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(palette.onGlassSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // Colored section tile centered above the title.
    private var sectionIconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous)
                .fill(section.accentColor)

            Image(systemName: section.systemImage)
                .font(.system(size: headerIconSize * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: headerIconSize, height: headerIconSize)
        .clipShape(RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
        .accessibilityHidden(true)
    }
}
