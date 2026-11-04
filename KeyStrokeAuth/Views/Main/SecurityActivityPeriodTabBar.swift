// SecurityActivityPeriodTabBar.swift
// Floating bottom tab bar for Security Activity — Today, Yesterday, Last 7 days.
// Same morph glass effect as the top category bar; double-click selected tab flips to trash → tap to clear.

import SwiftUI

private enum SecurityActivityTabBarLayout {
    static let trackHeight: CGFloat = 36
    static let segmentWidth: CGFloat = 104
    static let thumbInset: CGFloat = 3
    static let tapMovementThreshold: CGFloat = 6
    static let shellPadding: CGFloat = 2
    static let doubleTapInterval: TimeInterval = 0.42

    static var shellCornerRadius: CGFloat { trackHeight / 2 + 2 }
    static var thumbHeight: CGFloat { trackHeight - (thumbInset * 2) }
    static var thumbWidth: CGFloat { segmentWidth - (thumbInset * 2) }
    static var trackWidth: CGFloat {
        segmentWidth * CGFloat(SecurityActivityPeriod.allCases.count)
    }
}

struct SecurityActivityPeriodTabBar: View {
    @Binding var selection: SecurityActivityPeriod
    let onClearPeriod: (SecurityActivityPeriod) -> Void

    @State private var settledIndicatorOffset: CGFloat = SecurityActivityTabBarLayout.thumbInset
    @State private var dragIndicatorCenterX: CGFloat?
    @State private var dragPreviewPeriod: SecurityActivityPeriod?
    @State private var isDragging = false
    @State private var clearReadyPeriod: SecurityActivityPeriod?
    @State private var lastTapPeriod: SecurityActivityPeriod?
    @State private var lastTapTime: Date?

    private var previewPeriod: SecurityActivityPeriod {
        dragPreviewPeriod ?? selection
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

    private var highlightedPeriod: SecurityActivityPeriod {
        previewPeriod
    }

    var body: some View {
        periodBarContent
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Security activity period")
            .accessibilityValue(accessibilityValue)
            .onAppear {
                settledIndicatorOffset = indicatorLeadingOffset(for: selection)
            }
            .onChange(of: selection) { _, newSelection in
                if clearReadyPeriod != newSelection {
                    clearReadyPeriod = nil
                }
                let target = indicatorLeadingOffset(for: newSelection)
                guard !isDragging, abs(settledIndicatorOffset - target) > 0.5 else { return }
                settledIndicatorOffset = target
            }
    }

    // Three layers matching the top tab bar: indicator → labels → fixed interaction overlay.
    private var periodBarContent: some View {
        ZStack(alignment: .topLeading) {
            periodIndicatorLayer
                .zIndex(0)

            segmentLabelsOverlay
                .zIndex(1)

            periodInteractionOverlay
                .zIndex(2)
        }
        .frame(
            width: SecurityActivityTabBarLayout.trackWidth,
            height: SecurityActivityTabBarLayout.trackHeight
        )
        .padding(SecurityActivityTabBarLayout.shellPadding)
        .background {
            LiquidGlassSurface(
                cornerRadius: SecurityActivityTabBarLayout.shellCornerRadius
            )
        }
        .background {
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.055))
        }
        .clipShape(Capsule(style: .continuous))
        .overlay {
            GlassMorphTabBarOutline(
                cornerRadius: SecurityActivityTabBarLayout.shellCornerRadius
            )
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: clearReadyPeriod)
    }

    // Fixed-size Liquid Glass pill with the same concentric inset as the top tab bar.
    private var periodIndicatorLayer: some View {
        ClearSegmentedGlassIndicator(
            accentColor: previewPeriod.timelineTextColor,
            isDragging: isDragging,
            cornerRadius: SecurityActivityTabBarLayout.thumbHeight / 2
        )
        .frame(
            width: SecurityActivityTabBarLayout.thumbWidth,
            height: SecurityActivityTabBarLayout.thumbHeight
        )
        .offset(
            x: displayIndicatorOffset,
            y: SecurityActivityTabBarLayout.thumbInset
        )
        .id("clear-glass-period-indicator")
    }

    // Stable full-width gesture surface prevents moving hit-test coordinates.
    private var periodInteractionOverlay: some View {
        WindowDragLock {
            Color.clear
                .frame(
                    width: SecurityActivityTabBarLayout.trackWidth,
                    height: SecurityActivityTabBarLayout.trackHeight
                )
                .contentShape(Rectangle())
                .highPriorityGesture(periodSelectionGesture)
        }
    }

    private var accessibilityValue: String {
        if let clearReadyPeriod {
            return "\(clearReadyPeriod.title) — \(clearReadyPeriod.clearAccessibilityLabel)"
        }
        return selection.title
    }

    private var segmentLabelsOverlay: some View {
        HStack(spacing: 0) {
            ForEach(SecurityActivityPeriod.allCases) { period in
                segmentLabel(period)
            }
        }
        .allowsHitTesting(false)
    }

    // Selected tab flips from title to trash after a double-click on that segment.
    private func segmentLabel(_ period: SecurityActivityPeriod) -> some View {
        let showTrash = clearReadyPeriod == period && selection == period
        let isHighlighted = period == highlightedPeriod

        return ZStack {
            Text(period.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    isHighlighted
                        ? GlassTheme.buttonLabelColor
                        : period.timelineTextColor.opacity(0.72)
                )
                .shadow(
                    color: isHighlighted && !isThumbSettled ? .black.opacity(0.45) : .clear,
                    radius: 1.5,
                    y: 0.5
                )
                .opacity(showTrash ? 0 : 1)
                .rotation3DEffect(.degrees(showTrash ? 180 : 0), axis: (x: 1, y: 0, z: 0))

            Image(systemName: "trash.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isHighlighted && isThumbSettled ? GlassTheme.buttonLabelColor : period.timelineTextColor)
                .opacity(showTrash ? 1 : 0)
                .rotation3DEffect(.degrees(showTrash ? 0 : -180), axis: (x: 1, y: 0, z: 0))
        }
        .frame(
            width: SecurityActivityTabBarLayout.segmentWidth,
            height: SecurityActivityTabBarLayout.trackHeight
        )
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: showTrash)
        .animation(.easeInOut(duration: 0.18), value: highlightedPeriod)
        .animation(.easeInOut(duration: 0.18), value: isThumbSettled)
        .accessibilityHidden(true)
    }

    private var periodSelectionGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let movedDistance = hypot(value.translation.width, value.translation.height)
                guard movedDistance > SecurityActivityTabBarLayout.tapMovementThreshold else { return }

                isDragging = true
                clearReadyPeriod = nil

                // Preserve the last settled origin and move from it using pointer translation.
                let settledCenterX = settledIndicatorOffset
                    + SecurityActivityTabBarLayout.thumbWidth / 2
                let centerX = min(
                    max(
                        SecurityActivityTabBarLayout.thumbInset
                            + SecurityActivityTabBarLayout.thumbWidth / 2,
                        settledCenterX + value.translation.width
                    ),
                    SecurityActivityTabBarLayout.trackWidth
                        - SecurityActivityTabBarLayout.thumbInset
                        - SecurityActivityTabBarLayout.thumbWidth / 2
                )
                dragIndicatorCenterX = centerX
                dragPreviewPeriod = period(at: centerX)
            }
            .onEnded { value in
                let movedDistance = hypot(value.translation.width, value.translation.height)

                if movedDistance <= SecurityActivityTabBarLayout.tapMovementThreshold {
                    handleSegmentTap(period(at: value.location.x))
                } else {
                    let settledPeriod = period(
                        at: dragIndicatorCenterX ?? value.location.x
                    )
                    commitSelection(to: settledPeriod, animated: true)
                }
            }
    }

    private func handleSegmentTap(_ tappedPeriod: SecurityActivityPeriod) {
        let now = Date()

        if clearReadyPeriod == tappedPeriod {
            onClearPeriod(tappedPeriod)
            clearReadyPeriod = nil
            lastTapPeriod = nil
            lastTapTime = nil
            resetDragState()
            return
        }

        if let lastTapPeriod,
           let lastTapTime,
           lastTapPeriod == tappedPeriod,
           tappedPeriod == selection,
           now.timeIntervalSince(lastTapTime) <= SecurityActivityTabBarLayout.doubleTapInterval {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                clearReadyPeriod = tappedPeriod
            }
            self.lastTapPeriod = nil
            self.lastTapTime = nil
            resetDragState()
            return
        }

        commitSelection(to: tappedPeriod, animated: true)
        clearReadyPeriod = nil

        lastTapPeriod = tappedPeriod
        lastTapTime = now
    }

    // Moves the glass pill and selection together so the slide always starts at the last position.
    private func commitSelection(to period: SecurityActivityPeriod, animated: Bool) {
        let targetOffset = indicatorLeadingOffset(for: period)
        let updates = {
            settledIndicatorOffset = targetOffset
            selection = period
            isDragging = false
            dragIndicatorCenterX = nil
            dragPreviewPeriod = nil
        }

        if animated {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.74), updates)
        } else {
            updates()
        }
    }

    // Clears transient pointer state after a tap, drag, or clear action.
    private func resetDragState() {
        isDragging = false
        dragIndicatorCenterX = nil
        dragPreviewPeriod = nil
    }

    private func indicatorLeadingOffset(for period: SecurityActivityPeriod) -> CGFloat {
        CGFloat(periodIndex(period)) * SecurityActivityTabBarLayout.segmentWidth
            + SecurityActivityTabBarLayout.thumbInset
    }

    private func clampedLeadingOffset(forCenterX centerX: CGFloat) -> CGFloat {
        min(
            max(
                SecurityActivityTabBarLayout.thumbInset,
                centerX - SecurityActivityTabBarLayout.thumbWidth / 2
            ),
            SecurityActivityTabBarLayout.trackWidth
                - SecurityActivityTabBarLayout.thumbInset
                - SecurityActivityTabBarLayout.thumbWidth
        )
    }

    private func period(at x: CGFloat) -> SecurityActivityPeriod {
        let index = min(
            SecurityActivityPeriod.allCases.count - 1,
            max(0, Int(x / SecurityActivityTabBarLayout.segmentWidth))
        )
        return SecurityActivityPeriod.allCases[index]
    }

    private func periodIndex(_ period: SecurityActivityPeriod) -> Int {
        SecurityActivityPeriod.allCases.firstIndex(of: period) ?? 0
    }
}
