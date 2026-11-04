// GlassMorphSegmentControl.swift
// Shared morph sliding-thumb layout and layers for multi-segment liquid glass toggles.
// Flow: fixed track → plain glass thumb while sliding → colored capsule when settled on a segment.

import SwiftUI

struct GlassMorphSegmentLayout {
    let trackHeight: CGFloat
    let segmentWidth: CGFloat
    let segmentCount: Int
    let thumbInset: CGFloat
    let morphVerticalOvershoot: CGFloat

    var trackWidth: CGFloat { segmentWidth * CGFloat(segmentCount) }
    var thumbWidth: CGFloat { segmentWidth - (thumbInset * 2) }
    var thumbHeight: CGFloat { trackHeight - (thumbInset * 2) }
    var morphThumbHeight: CGFloat { trackHeight + morphVerticalOvershoot }
    var halfSegment: CGFloat { segmentWidth / 2 }
    var maxThumbOffset: CGFloat { segmentWidth * CGFloat(segmentCount - 1) }

    func thumbMorphProgress(for offset: CGFloat) -> CGFloat {
        let snapOffsets = (0..<segmentCount).map { CGFloat($0) * segmentWidth }
        let distanceFromNearestSnap = snapOffsets.map { abs(offset - $0) }.min() ?? 0
        return min(1, distanceFromNearestSnap / halfSegment)
    }

    func thumbDisplayWidth(for offset: CGFloat) -> CGFloat {
        let progress = thumbMorphProgress(for: offset)
        return thumbHeight + (thumbWidth - thumbHeight) * (1 - progress)
    }

    func thumbDisplayHeight(for offset: CGFloat) -> CGFloat {
        let progress = thumbMorphProgress(for: offset)
        return thumbHeight + (morphThumbHeight - thumbHeight) * progress
    }

    func thumbVerticalOffset(for offset: CGFloat) -> CGFloat {
        (trackHeight - thumbDisplayHeight(for: offset)) / 2
    }

    func thumbLeadingOffset(for offset: CGFloat) -> CGFloat {
        offset + thumbInset
    }
}

struct GlassMorphTrackCapsule: View {
    @Environment(\.glassPalette) private var palette

    var body: some View {
        Capsule(style: .continuous)
            .fill(palette.themeTrackFill.opacity(0.88))
    }
}

struct PlainMorphGlassCapsuleThumb: View {
    @Environment(\.glassPalette) private var palette

    var body: some View {
        ZStack {
            Capsule()
                .fill(.thinMaterial)

            Capsule()
                .fill(.ultraThinMaterial)
                .opacity(0.9)

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            palette.borderHighlightStrong.opacity(0.42),
                            palette.borderHighlightSoft.opacity(0.16),
                            Color.clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Capsule()
                .fill(palette.onGlassPrimary.opacity(0.1))
        }
        .clipShape(Capsule(style: .continuous))
        .shadow(color: palette.shadowSoft.opacity(0.35), radius: 1, y: 0.5)
    }
}

struct GlassMorphColoredCapsuleThumb: View {
    let accentColor: Color

    var body: some View {
        GlassCapsuleSurface(tint: .none, borderStyle: .none)
            .overlay {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                accentColor.opacity(0.64),
                                accentColor.opacity(0.48),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
    }
}

struct GlassMorphThumbLayer<SettledThumb: View>: View {
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
                PlainMorphGlassCapsuleThumb()
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
        .animation(isDragging ? nil : .spring(response: 0.38, dampingFraction: 0.78), value: resolvedThumbOffset)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: morphProgress)
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

// MARK: - Fixed-size sliding thumb (UnionTabView / iOS 26 — no vertical balloon morph)

/// Glass pill that keeps the same capsule size while sliding; extra blur only while the user drags.
struct SlidingGlassDragThumb: View {
    @Environment(\.glassPalette) private var palette

    let isDragging: Bool

    var body: some View {
        ZStack {
            PlainMorphGlassCapsuleThumb()

            if isDragging {
                Capsule(style: .continuous)
                    .fill(.regularMaterial)
                    .opacity(0.42)

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                palette.borderHighlightStrong.opacity(0.5),
                                palette.borderHighlightSoft.opacity(0.2),
                                Color.clear,
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .blendMode(.plusLighter)

                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.75)
            }
        }
    }
}

/// Selection thumb with constant width/height — slides horizontally inside the track.
struct GlassSlidingThumbLayer<SettledThumb: View>: View {
    let layout: GlassMorphSegmentLayout
    let resolvedThumbOffset: CGFloat
    let isDragging: Bool
    @ViewBuilder var settledThumb: () -> SettledThumb

    private var thumbVerticalInset: CGFloat {
        (layout.trackHeight - layout.thumbHeight) / 2
    }

    var body: some View {
        let thumb = Group {
            if isDragging {
                MorphGlassLiquidThumb(
                    width: layout.thumbWidth,
                    height: layout.thumbHeight,
                    accentColor: .clear,
                    isMorphing: true
                )
            } else {
                settledThumb()
            }
        }
        .frame(width: layout.thumbWidth, height: layout.thumbHeight)
        .offset(
            x: layout.thumbLeadingOffset(for: resolvedThumbOffset),
            y: thumbVerticalInset
        )
        .animation(
            isDragging ? .interactiveSpring(response: 0.24, dampingFraction: 0.88) : .spring(response: 0.38, dampingFraction: 0.78),
            value: resolvedThumbOffset
        )

        Color.clear
            .frame(width: layout.trackWidth, height: layout.trackHeight)
            .overlay(alignment: .topLeading) { thumb }
            .clipShape(Capsule(style: .continuous))
    }
}
