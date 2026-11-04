// ClearGlassSegmentedTabBar.swift
// Transparent glass segmented picker — full-segment Liquid Glass indicator with direct drag tracking.
// Pattern: https://www.sabesh.space/blog/engineering/clear-segmented-picker
// Flow: layer 0 sliding glass pill → layer 1 labels → layer 2 fixed interaction overlay.

import AppKit
import SwiftUI

// MARK: - Layout

enum ClearGlassSegmentedTabBarLayout {
    static let trackHeight: CGFloat = 40
    static let segmentWidth: CGFloat = 94
    static let tabSpacing: CGFloat = 0
    static let tabHorizontalPadding: CGFloat = 14
    static let iconSpacing: CGFloat = 6
    static let shellPadding: CGFloat = 2
    static let thumbInset: CGFloat = 4

    static var shellCornerRadius: CGFloat { trackHeight / 2 + 2 }
    static var thumbHeight: CGFloat { trackHeight - (thumbInset * 2) }
    static var overflowFrameHeight: CGFloat { trackHeight + (shellPadding * 2) }
    static var floatingOverlayHeight: CGFloat { overflowFrameHeight + 14 }
}

// MARK: - Clear Liquid Glass indicator

/// Real NSGlassEffectView-backed pill with a restrained category tint and specular rim.
struct ClearSegmentedGlassIndicator: View {
    @Environment(\.glassPalette) private var palette

    let accentColor: Color
    let isDragging: Bool
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            LiquidGlassSurface(cornerRadius: cornerRadius)

            Capsule(style: .continuous)
                .fill(accentColor.opacity(isDragging ? 0.08 : 0.18))
                .blendMode(.plusLighter)

            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            palette.borderHighlightStrong.opacity(0.26),
                            Color.clear,
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
        }
        .clipShape(Capsule(style: .continuous))
        .overlay {
            GlassLiquidCapsuleBorder(lineWidth: 0.8)
                .opacity(isDragging ? 0.72 : 0.9)
        }
        .scaleEffect(isDragging ? 1.025 : 1)
        .shadow(
            color: palette.shadowSoft.opacity(isDragging ? 0.5 : 0.3),
            radius: isDragging ? 6 : 3,
            y: isDragging ? 2 : 1
        )
        .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.82), value: isDragging)
    }
}

// MARK: - Clear glass segmented tab bar

/// Floating segmented control with a full-width sliding glass pill and stable interaction geometry.
struct ClearGlassSegmentedTabBar<Segment: Identifiable & Hashable>: View {
    @Binding var selection: Segment

    let segments: [Segment]
    let segmentTitle: (Segment) -> String
    let segmentIcon: (Segment) -> String
    let segmentAccent: (Segment) -> Color
    let accessibilityLabel: String

    @State private var settledIndicatorOffset: CGFloat = ClearGlassSegmentedTabBarLayout.thumbInset
    @State private var dragIndicatorCenterX: CGFloat?
    @State private var dragPreviewIndex: Int?
    @State private var isDragging = false

    private var selectedIndex: Int {
        segments.firstIndex(where: { $0.id == selection.id }) ?? 0
    }

    private var trackWidth: CGFloat {
        ClearGlassSegmentedTabBarLayout.segmentWidth * CGFloat(segments.count)
    }

    private var indicatorWidth: CGFloat {
        ClearGlassSegmentedTabBarLayout.segmentWidth
            - (ClearGlassSegmentedTabBarLayout.thumbInset * 2)
    }

    private var previewIndex: Int {
        dragPreviewIndex ?? selectedIndex
    }

    private var displayIndicatorOffset: CGFloat {
        if isDragging, let dragIndicatorCenterX {
            return clampedLeadingOffset(forCenterX: dragIndicatorCenterX)
        }
        return settledIndicatorOffset
    }

    var body: some View {
        pickerContent
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(segmentTitle(selection))
            .onAppear {
                settledIndicatorOffset = indicatorLeadingOffset(for: selectedIndex)
            }
            .onChange(of: selection.id) { _, _ in
                let target = indicatorLeadingOffset(for: selectedIndex)
                guard !isDragging, abs(settledIndicatorOffset - target) > 0.5 else { return }
                settledIndicatorOffset = target
            }
    }

    // Shell + three-layer stack: indicator → labels → fixed full-width interaction overlay.
    private var pickerContent: some View {
        ZStack(alignment: .topLeading) {
            slidingIndicatorLayer
                .zIndex(0)

            tabLabelsLayer
                .zIndex(1)

            dragOverlayLayer
                .zIndex(2)
        }
        .frame(height: ClearGlassSegmentedTabBarLayout.trackHeight)
        .padding(ClearGlassSegmentedTabBarLayout.shellPadding)
        .background {
            LiquidGlassSurface(
                cornerRadius: ClearGlassSegmentedTabBarLayout.shellCornerRadius
            )
        }
        .background {
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.055))
        }
        .clipShape(Capsule(style: .continuous))
        .overlay {
            GlassMorphTabBarOutline(
                cornerRadius: ClearGlassSegmentedTabBarLayout.shellCornerRadius
            )
        }
    }

    // Layer 0 — glass pill fills the tab region with a concentric 4-point edge inset.
    private var slidingIndicatorLayer: some View {
        ClearSegmentedGlassIndicator(
            accentColor: segmentAccent(segments[previewIndex]),
            isDragging: isDragging,
            cornerRadius: ClearGlassSegmentedTabBarLayout.thumbHeight / 2
        )
        .frame(
            width: indicatorWidth,
            height: ClearGlassSegmentedTabBarLayout.thumbHeight
        )
        .offset(
            x: displayIndicatorOffset,
            y: ClearGlassSegmentedTabBarLayout.thumbInset
        )
        .id("clear-glass-segmented-indicator")
    }

    // Layer 1 — icon + text labels; the fixed overlay handles interaction.
    private var tabLabelsLayer: some View {
        HStack(spacing: ClearGlassSegmentedTabBarLayout.tabSpacing) {
            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                tabLabelCell(segment: segment, index: index)
            }
        }
    }

    private func tabLabelCell(segment: Segment, index: Int) -> some View {
        let isSelected = index == previewIndex

        return HStack(spacing: ClearGlassSegmentedTabBarLayout.iconSpacing) {
            Image(systemName: segmentIcon(segment))
                .font(.caption.weight(.semibold))
                .symbolRenderingMode(.hierarchical)

            Text(segmentTitle(segment))
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(
            isSelected
                ? GlassTheme.buttonLabelColor
                : segmentAccent(segment).opacity(0.72)
        )
        .shadow(
            color: isSelected && isDragging ? .black.opacity(0.35) : .clear,
            radius: 1.5,
            y: 0.5
        )
        .padding(.horizontal, ClearGlassSegmentedTabBarLayout.tabHorizontalPadding)
        .frame(
            width: ClearGlassSegmentedTabBarLayout.segmentWidth,
            height: ClearGlassSegmentedTabBarLayout.trackHeight
        )
        .allowsHitTesting(false)
    }

    // Layer 2 — fixed hit target spanning the complete bar; WindowDragLock only wraps this layer.
    private var dragOverlayLayer: some View {
        WindowDragLock {
            Color.clear
                .frame(width: trackWidth, height: ClearGlassSegmentedTabBarLayout.trackHeight)
                .contentShape(Rectangle())
                .highPriorityGesture(tabBarSelectionGesture)
        }
    }

    private var tabBarSelectionGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { gesture in
                let movedDistance = hypot(
                    gesture.translation.width,
                    gesture.translation.height
                )
                guard movedDistance > 2 else { return }

                isDragging = true
                let settledCenterX = settledIndicatorOffset + indicatorWidth / 2
                let centerX = min(
                    max(
                        ClearGlassSegmentedTabBarLayout.thumbInset + indicatorWidth / 2,
                        settledCenterX + gesture.translation.width
                    ),
                    trackWidth
                        - ClearGlassSegmentedTabBarLayout.thumbInset
                        - indicatorWidth / 2
                )
                dragIndicatorCenterX = centerX
                dragPreviewIndex = segmentIndex(at: centerX)
            }
            .onEnded { gesture in
                let movedDistance = hypot(
                    gesture.translation.width,
                    gesture.translation.height
                )
                let targetIndex = segmentIndex(
                    at: isDragging
                        ? (dragIndicatorCenterX ?? gesture.location.x)
                        : gesture.location.x
                )
                let targetOffset = indicatorLeadingOffset(for: targetIndex)

                withAnimation(.spring(response: 0.32, dampingFraction: 0.74)) {
                    settledIndicatorOffset = targetOffset
                    selection = segments[targetIndex]
                    isDragging = false
                    dragIndicatorCenterX = nil
                    dragPreviewIndex = nil
                }

                performClearGlassTabBarHaptic()
            }
    }

    // Leading offset preserves the concentric inset inside each 94-point tab region.
    private func indicatorLeadingOffset(for index: Int) -> CGFloat {
        CGFloat(index) * ClearGlassSegmentedTabBarLayout.segmentWidth
            + ClearGlassSegmentedTabBarLayout.thumbInset
    }

    private func clampedLeadingOffset(forCenterX centerX: CGFloat) -> CGFloat {
        min(
            max(
                ClearGlassSegmentedTabBarLayout.thumbInset,
                centerX - indicatorWidth / 2
            ),
            max(
                ClearGlassSegmentedTabBarLayout.thumbInset,
                trackWidth - ClearGlassSegmentedTabBarLayout.thumbInset - indicatorWidth
            )
        )
    }

    // Converts the fixed interaction layer's x-coordinate into one of the tab regions.
    private func segmentIndex(at x: CGFloat) -> Int {
        min(
            segments.count - 1,
            max(0, Int(x / ClearGlassSegmentedTabBarLayout.segmentWidth))
        )
    }
}

private func performClearGlassTabBarHaptic() {
    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
}
