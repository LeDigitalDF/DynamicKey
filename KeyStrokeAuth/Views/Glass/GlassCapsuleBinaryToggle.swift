// GlassCapsuleBinaryToggle.swift
// Morphing on/off capsule — frosted track, plain glass thumb while sliding, accent when settled.
// Flow: drag or tap → thumb morphs between off/on icons → green or neutral tint at rest.

import SwiftUI

private enum CapsuleBinaryToggleLayout {
    static let trackHeight: CGFloat = 32
    static let segmentWidth: CGFloat = 44
    static let thumbInset: CGFloat = 3
    static let morphVerticalOvershoot: CGFloat = 12

    static var morphLayout: GlassMorphSegmentLayout {
        GlassMorphSegmentLayout(
            trackHeight: trackHeight,
            segmentWidth: segmentWidth,
            segmentCount: 2,
            thumbInset: thumbInset,
            morphVerticalOvershoot: morphVerticalOvershoot
        )
    }
}

struct GlassCapsuleBinaryToggle: View {
    @Environment(\.glassPalette) private var palette

    @Binding var isOn: Bool
    let offSystemImage: String
    let onSystemImage: String
    var offTint: GlassCapsuleTint = .neutral
    var onTint: GlassCapsuleTint = .green
    let accessibilityLabel: String

    @State private var dragThumbOffset: CGFloat?
    @State private var isDragging = false

    private var layout: GlassMorphSegmentLayout {
        CapsuleBinaryToggleLayout.morphLayout
    }

    private var resolvedThumbOffset: CGFloat {
        if let dragThumbOffset {
            return dragThumbOffset
        }
        return isOn ? CapsuleBinaryToggleLayout.segmentWidth : 0
    }

    private var isThumbSettled: Bool {
        layout.thumbMorphProgress(for: resolvedThumbOffset) < 0.04 && !isDragging
    }

    private var settledAccentColor: Color {
        morphAccentColor(for: isOn ? onTint : offTint)
    }

    var body: some View {
        WindowDragLock {
            ZStack(alignment: .leading) {
                GlassMorphTrackCapsule()
                    .transaction { transaction in
                        transaction.animation = nil
                    }

                GlassMorphThumbLayer(
                    layout: layout,
                    resolvedThumbOffset: resolvedThumbOffset,
                    isDragging: isDragging
                ) {
                    GlassMorphColoredCapsuleThumb(accentColor: settledAccentColor)
                }

                HStack(spacing: 0) {
                    segmentIcon(offSystemImage, isActive: !isOn)
                    segmentIcon(onSystemImage, isActive: isOn)
                }
                .allowsHitTesting(false)
                .zIndex(1)
            }
            .frame(width: layout.trackWidth, height: layout.trackHeight)
            .contentShape(Capsule(style: .continuous))
            .highPriorityGesture(selectionGesture)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isOn ? "On" : "Off")
    }

    private func segmentIcon(_ systemImage: String, isActive: Bool) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(
                isActive && isThumbSettled
                    ? GlassTheme.buttonLabelColor
                    : palette.onGlassSecondary.opacity(0.55)
            )
            .frame(width: CapsuleBinaryToggleLayout.segmentWidth, height: layout.trackHeight)
            .animation(.easeInOut(duration: 0.18), value: isOn)
            .animation(.easeInOut(duration: 0.18), value: isThumbSettled)
    }

    private var selectionGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                isDragging = true
                let rawOffset = value.location.x
                    - (layout.thumbDisplayWidth(for: resolvedThumbOffset) * 0.5)
                    - CapsuleBinaryToggleLayout.thumbInset
                dragThumbOffset = min(max(0, rawOffset), CapsuleBinaryToggleLayout.segmentWidth)

                let nextIsOn = value.location.x >= CapsuleBinaryToggleLayout.segmentWidth
                if isOn != nextIsOn {
                    isOn = nextIsOn
                }
            }
            .onEnded { value in
                isDragging = false
                withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.76)) {
                    dragThumbOffset = nil
                    isOn = value.location.x >= CapsuleBinaryToggleLayout.segmentWidth
                }
            }
    }

    private func morphAccentColor(for tint: GlassCapsuleTint) -> Color {
        switch tint {
        case .none:
            return palette.onGlassPrimary
        case .verify:
            return Color(red: 0.2, green: 0.72, blue: 0.88)
        case .blue:
            return Color(red: 0.22, green: 0.48, blue: 0.95)
        case .enroll:
            return Color(red: 0.52, green: 0.28, blue: 0.88)
        case .orange:
            return Color(red: 0.95, green: 0.52, blue: 0.12)
        case .green:
            return Color(red: 0.18, green: 0.78, blue: 0.42)
        case .neutral:
            return Color.secondary
        case .destructive:
            return Color(red: 0.92, green: 0.28, blue: 0.24)
        }
    }
}
