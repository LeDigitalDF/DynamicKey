// SettingsFlipWidgetCard.swift
// Flippable settings widget card — front shows controls; back shows a short description.
// Flow: flip icon (top-right) or tap header → 3D flip animation → tap again to return.
// Optional frontTintColor + frontOverlay for play-card fronts (e.g. Touch ID Fallback).

import AppKit
import SwiftUI

struct SettingsFlipWidgetCard<Front: View>: View {
    let title: String
    let backDescription: String
    var minHeight: CGFloat = SettingsCardLayout.standardCardHeight
    var frontContentHeight: CGFloat = SettingsCardLayout.frontContentHeight
    var frontTintColor: NSColor? = nil
    var usesScrollableBackDescription: Bool = false
    @ViewBuilder var frontOverlay: () -> AnyView
    @ViewBuilder var front: () -> Front

    @Environment(\.glassPalette) private var palette
    @State private var isFlipped = false

    init(
        title: String,
        backDescription: String,
        minHeight: CGFloat = SettingsCardLayout.standardCardHeight,
        frontContentHeight: CGFloat = SettingsCardLayout.frontContentHeight,
        frontTintColor: NSColor? = nil,
        usesScrollableBackDescription: Bool = false,
        @ViewBuilder frontOverlay: @escaping () -> some View = { EmptyView() },
        @ViewBuilder front: @escaping () -> Front
    ) {
        self.title = title
        self.backDescription = backDescription
        self.minHeight = minHeight
        self.frontContentHeight = frontContentHeight
        self.frontTintColor = frontTintColor
        self.usesScrollableBackDescription = usesScrollableBackDescription
        self.frontOverlay = { AnyView(frontOverlay()) }
        self.front = front
    }

    var body: some View {
        ZStack {
            frontCardFace
                .opacity(isFlipped ? 0 : 1)
                .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                .allowsHitTesting(!isFlipped)

            backCardFace
                .opacity(isFlipped ? 1 : 0)
                .rotation3DEffect(.degrees(isFlipped ? 0 : -180), axis: (x: 0, y: 1, z: 0))
                .allowsHitTesting(isFlipped)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: minHeight, alignment: .topLeading)
        .clipped()
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: isFlipped)
    }

    private var frontCardFace: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow

            front()
                .frame(
                    maxWidth: .infinity,
                    minHeight: frontContentHeight,
                    maxHeight: frontContentHeight,
                    alignment: .center
                )
        }
        .padding(GlassTheme.padding)
        .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: minHeight, alignment: .topLeading)
        .background {
            ZStack {
                LiquidGlassSurface(
                    cornerRadius: GlassTheme.cornerRadius,
                    tintColor: frontTintColor
                )

                frontOverlay()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: GlassTheme.cornerRadius, style: .continuous))
        }
        .clipShape(RoundedRectangle(cornerRadius: GlassTheme.cornerRadius, style: .continuous))
    }

    private var backCardFace: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow

            Group {
                if usesScrollableBackDescription {
                    ScrollView(.vertical, showsIndicators: true) {
                        Text(backDescription)
                            .font(.caption)
                            .foregroundStyle(palette.onGlassSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, SettingsCardLayout.scrollContentBottomInset)
                    }
                    .contentMargins(.bottom, SettingsCardLayout.scrollContentBottomInset, for: .scrollContent)
                } else {
                    Text(backDescription)
                        .font(.caption)
                        .foregroundStyle(palette.onGlassSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .frame(
                maxWidth: .infinity,
                minHeight: frontContentHeight,
                maxHeight: frontContentHeight,
                alignment: .topLeading
            )
        }
        .padding(GlassTheme.padding)
        .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: minHeight, alignment: .topLeading)
        .background {
            LiquidGlassSurface(cornerRadius: GlassTheme.cornerRadius)
        }
        .clipShape(RoundedRectangle(cornerRadius: GlassTheme.cornerRadius, style: .continuous))
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.onGlassPrimary)

            Spacer(minLength: 0)

            flipHintButton
        }
        .contentShape(Rectangle())
        .onTapGesture {
            toggleFlip()
        }
    }

    private var flipHintButton: some View {
        SettingsCardInfoFlipButton(isShowingInfo: isFlipped, action: toggleFlip)
    }

    private func toggleFlip() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            isFlipped.toggle()
        }
    }
}
