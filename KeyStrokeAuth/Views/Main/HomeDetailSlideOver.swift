// HomeDetailSlideOver.swift
// Floating half-width glass sheet from Home quick links — slides in from the right, Home stays visible on the left.
// Flow: trailing-aligned card with inset margins → opaque glass surface → header → section content.

import SwiftUI

private enum HomeSlideOverLayout {
    static let topInset: CGFloat = 8
    static let bottomInset: CGFloat = 16
    static let trailingInset: CGFloat = 16
    static let widthFraction: CGFloat = 0.52
}

struct HomeDetailSlideOver<Content: View>: View {
    @Environment(\.glassPalette) private var palette

    let section: MainSidebarSection
    let onDismiss: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .top, spacing: 0) {
                Spacer(minLength: 0)

                floatingCard(
                    width: max(320, (proxy.size.width - HomeSlideOverLayout.trailingInset * 2) * HomeSlideOverLayout.widthFraction),
                    height: proxy.size.height - HomeSlideOverLayout.topInset - HomeSlideOverLayout.bottomInset
                )
                .padding(.trailing, HomeSlideOverLayout.trailingInset)
                .padding(.top, HomeSlideOverLayout.topInset)
                .padding(.bottom, HomeSlideOverLayout.bottomInset)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topTrailing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .ignoresSafeArea(.container, edges: .top)
        .allowsHitTesting(true)
    }

    // Floating liquid glass card — sits higher in the detail column with a more opaque glass fill.
    private func floatingCard(width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                sidebarIconBadge(section: section)
                Spacer()
                GlassCircleIconButton(
                    systemImage: "chevron.right",
                    accessibilityLabel: "Back",
                    action: onDismiss
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .background {
            ZStack {
                NSGlassEffectContainerRepresentable(cornerRadius: GlassTheme.cornerRadius) {
                    Color.clear
                }

                RoundedRectangle(cornerRadius: GlassTheme.cornerRadius, style: .continuous)
                    .fill(palette.slideOverScrim)

                RoundedRectangle(cornerRadius: GlassTheme.cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
                    .opacity(palette.slideOverMaterialOpacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: GlassTheme.cornerRadius, style: .continuous))
        .overlay {
            GlassGradientBorder(cornerRadius: GlassTheme.cornerRadius)
        }
        .shadow(color: palette.shadowStrong.opacity(0.55), radius: 24, x: -6, y: 8)
        .shadow(color: palette.shadowSoft, radius: 8, x: 0, y: 2)
    }

    // Colored icon tile matching the sidebar entry for this slide-over.
    private func sidebarIconBadge(section: MainSidebarSection) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(section.accentColor)
                .frame(width: 28, height: 28)

            Image(systemName: section.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
        .accessibilityHidden(true)
    }
}
