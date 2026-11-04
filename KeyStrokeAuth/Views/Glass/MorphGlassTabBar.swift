// MorphGlassTabBar.swift
// Flexible Liquid Glass tab bar — MorphGlassTabBarShell + fixed sliding selection pill (UnionTabView / sage.me).
// Reference: https://sage.me/glass-tab-bar · https://github.com/unionst/union-tab-view
// Flow: real Liquid Glass shell (border + refraction) → fixed pill slides between segments → haptic on settle.

import AppKit
import SwiftUI

// MARK: - Fixed-size glass shell (track + labels only — never scales with the thumb)

struct MorphGlassTabBarShell<Content: View>: View {
    var cornerRadius: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
            .background {
                LiquidGlassSurface(cornerRadius: cornerRadius)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                GlassMorphTabBarOutline(cornerRadius: cornerRadius)
            }
    }
}

// MARK: - Liquid glass thumb (shape morphs while sliding)

struct MorphGlassLiquidThumb: View {
    @Environment(\.glassPalette) private var palette

    let width: CGFloat
    let height: CGFloat
    let accentColor: Color
    let isMorphing: Bool

    private var cornerRadius: CGFloat {
        min(width, height) / 2
    }

    var body: some View {
        ZStack {
            LiquidGlassSurface(cornerRadius: cornerRadius)

            if isMorphing {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                palette.borderHighlightStrong.opacity(0.38),
                                palette.borderHighlightSoft.opacity(0.14),
                                Color.clear,
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(palette.onGlassPrimary.opacity(0.08))
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accentColor.opacity(0.52),
                                accentColor.opacity(0.34),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.plusLighter)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(
            color: palette.shadowSoft.opacity(isMorphing ? 0.45 : 0.28),
            radius: isMorphing ? 5 : 2,
            y: isMorphing ? 2 : 1
        )
    }
}

// MARK: - Morphing thumb layer (capsule at rest → round blob mid-slide → capsule at next tab)

struct MorphGlassSegmentThumbLayer<SettledThumb: View>: View {
    let layout: GlassMorphSegmentLayout
    let resolvedThumbOffset: CGFloat
    let isDragging: Bool
    @ViewBuilder var settledThumb: () -> SettledThumb

    private var morphProgress: CGFloat {
        layout.thumbMorphProgress(for: resolvedThumbOffset)
    }

    private var shouldClipThumbToTrack: Bool {
        morphProgress < 0.04 && !isDragging
    }

    var body: some View {
        let thumb = Group {
            if isDragging || morphProgress > 0.04 {
                MorphGlassLiquidThumb(
                    width: layout.thumbDisplayWidth(for: resolvedThumbOffset),
                    height: layout.thumbDisplayHeight(for: resolvedThumbOffset),
                    accentColor: .clear,
                    isMorphing: true
                )
            } else {
                settledThumb()
            }
        }
        .frame(
            width: layout.thumbDisplayWidth(for: resolvedThumbOffset),
            height: layout.thumbDisplayHeight(for: resolvedThumbOffset)
        )
        .offset(
            x: layout.thumbLeadingOffset(for: resolvedThumbOffset),
            y: layout.thumbVerticalOffset(for: resolvedThumbOffset)
        )
        .animation(isDragging ? nil : .bouncy(duration: 0.42, extraBounce: 0.03), value: resolvedThumbOffset)
        .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.82), value: morphProgress)
        .compositingGroup()

        Group {
            if shouldClipThumbToTrack {
                Color.clear
                    .frame(width: layout.trackWidth, height: layout.trackHeight)
                    .overlay(alignment: .topLeading) { thumb }
                    .clipShape(Capsule(style: .continuous))
            } else {
                Color.clear
                    .frame(width: layout.trackWidth, height: layout.trackHeight)
                    .overlay(alignment: .topLeading) { thumb }
            }
        }
    }
}

// MARK: - Flexible morphing tab bar (UnionTabView-style for macOS)

enum FlexibleLiquidGlassMorphingTabBarLayout {
    static let trackHeight: CGFloat = 40
    static let segmentWidth: CGFloat = 94
    static let thumbInset: CGFloat = 4
    static let tapMovementThreshold: CGFloat = 6
    static let shellPadding: CGFloat = 4

    static var shellCornerRadius: CGFloat { trackHeight / 2 + 2 }

    static var overflowFrameHeight: CGFloat { trackHeight + shellPadding }

    /// Vertical space to reserve when the bar floats over scrolling content.
    static var floatingOverlayHeight: CGFloat { overflowFrameHeight + 14 }
}

/// Selection pill at rest — real Liquid Glass with category tint (matches bottom period bar thumb).
struct FlexibleMorphGlassSettledThumb: View {
    let width: CGFloat
    let height: CGFloat
    let accentColor: Color

    var body: some View {
        MorphGlassLiquidThumb(
            width: width,
            height: height,
            accentColor: accentColor,
            isMorphing: false
        )
    }
}

/// Floating liquid glass tab bar — UnionTabView / sage.me pattern on macOS:
/// MorphGlassTabBarShell (real Liquid Glass + specular border) + fixed-size sliding selection pill.
struct FlexibleLiquidGlassMorphingTabBar<Segment: Identifiable & Hashable>: View {
    @Binding var selection: Segment

    let segments: [Segment]
    let segmentTitle: (Segment) -> String
    let segmentAccent: (Segment) -> Color
    let accessibilityLabel: String

    @State private var dragThumbOffset: CGFloat?
    @State private var isDragging = false

    private var layout: GlassMorphSegmentLayout {
        GlassMorphSegmentLayout(
            trackHeight: FlexibleLiquidGlassMorphingTabBarLayout.trackHeight,
            segmentWidth: FlexibleLiquidGlassMorphingTabBarLayout.segmentWidth,
            segmentCount: segments.count,
            thumbInset: FlexibleLiquidGlassMorphingTabBarLayout.thumbInset,
            morphVerticalOvershoot: 0
        )
    }

    private var resolvedThumbOffset: CGFloat {
        if let dragThumbOffset {
            return dragThumbOffset
        }
        return thumbOffset(for: selection)
    }

    private var highlightedSegment: Segment {
        if !isDragging {
            return selection
        }

        let thumbCenterX = resolvedThumbOffset + layout.thumbWidth * 0.5
        let index = min(
            segments.count - 1,
            max(0, Int(thumbCenterX / FlexibleLiquidGlassMorphingTabBarLayout.segmentWidth))
        )
        return segments[index]
    }

    var body: some View {
        WindowDragLock {
            morphingTabBarContent
                .contentShape(Capsule(style: .continuous))
                .highPriorityGesture(selectionGesture)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(segmentTitle(selection))
    }

    // Same shell stack as the bottom period bar — LiquidGlassSurface capsule + specular border.
    private var morphingTabBarContent: some View {
        ZStack {
            categoryTrackShell

            GlassSlidingThumbLayer(
                layout: layout,
                resolvedThumbOffset: resolvedThumbOffset,
                isDragging: isDragging
            ) {
                FlexibleMorphGlassSettledThumb(
                    width: layout.thumbWidth,
                    height: layout.thumbHeight,
                    accentColor: segmentAccent(selection)
                )
            }
            .frame(width: layout.trackWidth, height: layout.trackHeight)

            segmentLabelsOverlay
                .zIndex(2)
        }
        .frame(
            width: layout.trackWidth + FlexibleLiquidGlassMorphingTabBarLayout.shellPadding,
            height: FlexibleLiquidGlassMorphingTabBarLayout.overflowFrameHeight
        )
    }

    private var categoryTrackShell: some View {
        MorphGlassTabBarShell(
            cornerRadius: FlexibleLiquidGlassMorphingTabBarLayout.shellCornerRadius
        ) {
            GlassMorphTrackCapsule()
                .opacity(0.55)
                .transaction { transaction in
                    transaction.animation = nil
                }
                .frame(width: layout.trackWidth, height: layout.trackHeight)
        }
    }

    private var segmentLabelsOverlay: some View {
        HStack(spacing: 0) {
            ForEach(segments) { segment in
                let isHighlighted = segment.id == highlightedSegment.id

                Text(segmentTitle(segment))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        isHighlighted
                            ? GlassTheme.buttonLabelColor
                            : segmentAccent(segment).opacity(0.72)
                    )
                    .shadow(
                        color: isHighlighted && isDragging ? .black.opacity(0.35) : .clear,
                        radius: 1.5,
                        y: 0.5
                    )
                    .frame(
                        width: FlexibleLiquidGlassMorphingTabBarLayout.segmentWidth,
                        height: layout.trackHeight
                    )
                    .animation(.easeInOut(duration: 0.18), value: highlightedSegment.id)
                    .animation(.easeInOut(duration: 0.18), value: isDragging)
            }
        }
        .allowsHitTesting(false)
    }

    private var selectionGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let movedDistance = hypot(value.translation.width, value.translation.height)
                guard movedDistance > FlexibleLiquidGlassMorphingTabBarLayout.tapMovementThreshold else { return }

                isDragging = true
                let rawOffset = value.location.x
                    - (layout.thumbWidth * 0.5)
                    - FlexibleLiquidGlassMorphingTabBarLayout.thumbInset
                dragThumbOffset = min(max(0, rawOffset), layout.maxThumbOffset)

                let next = segment(at: value.location.x)
                if selection.id != next.id {
                    selection = next
                }
            }
            .onEnded { value in
                isDragging = false
                let tapped = segment(at: value.location.x)

                withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                    dragThumbOffset = nil
                    selection = tapped
                }

                performMorphTabBarHaptic()
            }
    }

    private func thumbOffset(for segment: Segment) -> CGFloat {
        CGFloat(segmentIndex(segment)) * FlexibleLiquidGlassMorphingTabBarLayout.segmentWidth
    }

    private func segment(at x: CGFloat) -> Segment {
        let index = min(
            segments.count - 1,
            max(0, Int(x / FlexibleLiquidGlassMorphingTabBarLayout.segmentWidth))
        )
        return segments[index]
    }

    private func segmentIndex(_ segment: Segment) -> Int {
        segments.firstIndex(where: { $0.id == segment.id }) ?? 0
    }
}

private func performMorphTabBarHaptic() {
    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
}
