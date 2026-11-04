// AppearanceThemeTabBar.swift
// Moon/sun appearance switch — clear glass segmented tab bar (same pattern as Security Activity bars).
// Flow: layer 0 sliding glass pill → layer 1 moon/sun icons → layer 2 fixed interaction overlay.

import AppKit
import SwiftUI

private enum AppearanceThemeTabBarLayout {
    static let trackHeight: CGFloat = 36
    static let segmentWidth: CGFloat = 56
    static let thumbInset: CGFloat = 3
    static let tapMovementThreshold: CGFloat = 6
    static let shellPadding: CGFloat = 2

    static var shellCornerRadius: CGFloat { trackHeight / 2 + 2 }
    static var thumbHeight: CGFloat { trackHeight - (thumbInset * 2) }
    static var thumbWidth: CGFloat { segmentWidth - (thumbInset * 2) }
    static var trackWidth: CGFloat {
        segmentWidth * CGFloat(AppTheme.toolbarCases.count)
    }
}

private extension AppTheme {
    var toolbarSystemImage: String {
        switch self {
        case .dark: return "moon.fill"
        case .light: return "sun.max.fill"
        case .system: return "circle.lefthalf.filled"
        }
    }

    var toolbarAccentColor: Color {
        switch self {
        case .dark: return .blue
        case .light: return .orange
        case .system: return .purple
        }
    }
}

struct AppearanceToolbarThemeControl: View {
    @EnvironmentObject private var appearance: AppAppearanceStore

    @State private var settledIndicatorOffset: CGFloat = AppearanceThemeTabBarLayout.thumbInset
    @State private var dragIndicatorCenterX: CGFloat?
    @State private var dragPreviewTheme: AppTheme?
    @State private var isDragging = false

    private var previewTheme: AppTheme {
        dragPreviewTheme ?? toolbarResolvedTheme
    }

    /// Toolbar only offers dark/light — system preference maps to the resolved scheme.
    private var toolbarResolvedTheme: AppTheme {
        switch appearance.theme {
        case .light:
            return .light
        case .dark:
            return .dark
        case .system:
            return appearance.theme.resolvedColorScheme == .dark ? .dark : .light
        }
    }

    private var displayIndicatorOffset: CGFloat {
        if isDragging, let dragIndicatorCenterX {
            return clampedLeadingOffset(forCenterX: dragIndicatorCenterX)
        }
        return settledIndicatorOffset
    }

    private var isThumbSettled: Bool {
        !isDragging
    }

    var body: some View {
        themeBarContent
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Appearance")
            .accessibilityValue(appearance.theme.label)
            .onAppear {
                settledIndicatorOffset = indicatorLeadingOffset(for: toolbarResolvedTheme)
            }
            .onChange(of: appearance.theme) { _, _ in
                let target = indicatorLeadingOffset(for: toolbarResolvedTheme)
                guard !isDragging, abs(settledIndicatorOffset - target) > 0.5 else { return }
                settledIndicatorOffset = target
            }
            .accessibilityAdjustableAction { direction in
                let newTheme: AppTheme = direction == .increment ? .light : .dark
                commitSelection(to: newTheme, animated: true)
            }
    }

    // Three layers matching Security Activity tab bars: indicator → icons → fixed interaction overlay.
    private var themeBarContent: some View {
        ZStack(alignment: .topLeading) {
            themeIndicatorLayer
                .zIndex(0)

            segmentIconsOverlay
                .zIndex(1)

            themeInteractionOverlay
                .zIndex(2)
        }
        .frame(
            width: AppearanceThemeTabBarLayout.trackWidth,
            height: AppearanceThemeTabBarLayout.trackHeight
        )
        .padding(AppearanceThemeTabBarLayout.shellPadding)
        .background {
            LiquidGlassSurface(
                cornerRadius: AppearanceThemeTabBarLayout.shellCornerRadius
            )
        }
        .background {
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.055))
        }
        .clipShape(Capsule(style: .continuous))
        .overlay {
            GlassMorphTabBarOutline(
                cornerRadius: AppearanceThemeTabBarLayout.shellCornerRadius
            )
        }
    }

    // Fixed-size Liquid Glass pill with the same concentric inset as Security Activity bars.
    private var themeIndicatorLayer: some View {
        ClearSegmentedGlassIndicator(
            accentColor: previewTheme.toolbarAccentColor,
            isDragging: isDragging,
            cornerRadius: AppearanceThemeTabBarLayout.thumbHeight / 2
        )
        .frame(
            width: AppearanceThemeTabBarLayout.thumbWidth,
            height: AppearanceThemeTabBarLayout.thumbHeight
        )
        .offset(
            x: displayIndicatorOffset,
            y: AppearanceThemeTabBarLayout.thumbInset
        )
        .id("clear-glass-theme-indicator")
    }

    private var segmentIconsOverlay: some View {
        HStack(spacing: 0) {
            ForEach(AppTheme.toolbarCases) { theme in
                let isHighlighted = theme == previewTheme

                Image(systemName: theme.toolbarSystemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                        isHighlighted
                            ? GlassTheme.buttonLabelColor
                            : theme.toolbarAccentColor.opacity(0.72)
                    )
                    .shadow(
                        color: isHighlighted && !isThumbSettled ? .black.opacity(0.45) : .clear,
                        radius: 1.5,
                        y: 0.5
                    )
                    .frame(
                        width: AppearanceThemeTabBarLayout.segmentWidth,
                        height: AppearanceThemeTabBarLayout.trackHeight
                    )
                    .animation(.easeInOut(duration: 0.18), value: previewTheme)
                    .animation(.easeInOut(duration: 0.18), value: isThumbSettled)
                    .accessibilityHidden(true)
            }
        }
        .allowsHitTesting(false)
    }

    // Stable full-width gesture surface; WindowDragLock only wraps this layer.
    private var themeInteractionOverlay: some View {
        WindowDragLock {
            Color.clear
                .frame(
                    width: AppearanceThemeTabBarLayout.trackWidth,
                    height: AppearanceThemeTabBarLayout.trackHeight
                )
                .contentShape(Rectangle())
                .highPriorityGesture(themeSelectionGesture)
        }
    }

    private var themeSelectionGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let movedDistance = hypot(value.translation.width, value.translation.height)
                guard movedDistance > AppearanceThemeTabBarLayout.tapMovementThreshold else { return }

                isDragging = true
                let settledCenterX = settledIndicatorOffset
                    + AppearanceThemeTabBarLayout.thumbWidth / 2
                let centerX = min(
                    max(
                        AppearanceThemeTabBarLayout.thumbInset
                            + AppearanceThemeTabBarLayout.thumbWidth / 2,
                        settledCenterX + value.translation.width
                    ),
                    AppearanceThemeTabBarLayout.trackWidth
                        - AppearanceThemeTabBarLayout.thumbInset
                        - AppearanceThemeTabBarLayout.thumbWidth / 2
                )
                dragIndicatorCenterX = centerX
                dragPreviewTheme = theme(at: centerX)
            }
            .onEnded { value in
                let movedDistance = hypot(value.translation.width, value.translation.height)
                let targetTheme = theme(
                    at: isDragging
                        ? (dragIndicatorCenterX ?? value.location.x)
                        : value.location.x
                )
                commitSelection(to: targetTheme, animated: true)

                if movedDistance > AppearanceThemeTabBarLayout.tapMovementThreshold {
                    performThemeTabBarHaptic()
                }
            }
    }

    // Moves the glass pill and theme together so the slide always starts at the last position.
    private func commitSelection(to theme: AppTheme, animated: Bool) {
        let targetOffset = indicatorLeadingOffset(for: theme)
        let updates = {
            settledIndicatorOffset = targetOffset
            appearance.setTheme(theme)
            isDragging = false
            dragIndicatorCenterX = nil
            dragPreviewTheme = nil
        }

        if animated {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.74), updates)
        } else {
            updates()
        }
    }

    private func indicatorLeadingOffset(for theme: AppTheme) -> CGFloat {
        CGFloat(themeIndex(theme)) * AppearanceThemeTabBarLayout.segmentWidth
            + AppearanceThemeTabBarLayout.thumbInset
    }

    private func clampedLeadingOffset(forCenterX centerX: CGFloat) -> CGFloat {
        min(
            max(
                AppearanceThemeTabBarLayout.thumbInset,
                centerX - AppearanceThemeTabBarLayout.thumbWidth / 2
            ),
            AppearanceThemeTabBarLayout.trackWidth
                - AppearanceThemeTabBarLayout.thumbInset
                - AppearanceThemeTabBarLayout.thumbWidth
        )
    }

    private func theme(at x: CGFloat) -> AppTheme {
        let index = min(
            AppTheme.toolbarCases.count - 1,
            max(0, Int(x / AppearanceThemeTabBarLayout.segmentWidth))
        )
        return AppTheme.toolbarCases[index]
    }

    private func themeIndex(_ theme: AppTheme) -> Int {
        AppTheme.toolbarCases.firstIndex(of: theme) ?? 0
    }
}

private func performThemeTabBarHaptic() {
    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
}

typealias AppearanceThemeTabBar = AppearanceToolbarThemeControl
