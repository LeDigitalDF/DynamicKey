// SettingsDetailSlideOver.swift
// Floating glass sheet from Settings — slides in from the right like Home quick links.
// Flow: trailing card → header with back chevron → scrollable flow content.

import SwiftUI

private enum SettingsSlideOverLayout {
    static let topInset: CGFloat = 8
    static let bottomInset: CGFloat = 16
    static let trailingInset: CGFloat = 16
    static let widthFraction: CGFloat = 0.52
}

struct SettingsDetailSlideOver<Content: View>: View {
    @Environment(\.glassPalette) private var palette

    let title: String
    let systemImage: String
    let accentColor: Color
    let onDismiss: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .top, spacing: 0) {
                Spacer(minLength: 0)

                floatingCard(
                    width: max(320, (proxy.size.width - SettingsSlideOverLayout.trailingInset * 2) * SettingsSlideOverLayout.widthFraction),
                    height: proxy.size.height - SettingsSlideOverLayout.topInset - SettingsSlideOverLayout.bottomInset
                )
                .padding(.trailing, SettingsSlideOverLayout.trailingInset)
                .padding(.top, SettingsSlideOverLayout.topInset)
                .padding(.bottom, SettingsSlideOverLayout.bottomInset)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topTrailing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .ignoresSafeArea(.container, edges: .top)
        .allowsHitTesting(true)
    }

    private func floatingCard(width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(accentColor)
                        .frame(width: 28, height: 28)

                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 0)

                GlassCircleIconButton(
                    systemImage: "chevron.right",
                    accessibilityLabel: "Back",
                    action: onDismiss
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)

            ScrollView {
                content()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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
}
