// HomeTypingRhythmPlayTile.swift
// Quick Actions — single background pulse watermark that grows on hover; tap opens Settings → Security Actions → Pulse.
// Flow: caption on top → centered waveform watermark behind → hover zoom → parent handles navigation.

import SwiftUI

struct HomeTypingRhythmPlayTile: View {
    @Environment(\.glassPalette) private var palette

    let showsReenrollmentReminder: Bool
    let action: () -> Void

    @State private var isWatermarkHovered = false

    private var subtitle: String {
        showsReenrollmentReminder
            ? "Your profile is due for a refresh"
            : "Re-record how you type your master password"
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(HomeQuickActionTileStyle.typingRhythmGlassFill)

                HomePulseRhythmWatermark(isHovered: isWatermarkHovered)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Update Typing Rhythm")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.onGlassPrimary)

                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(palette.onGlassSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: HomeQuickActionTileLayout.height,
                maxHeight: HomeQuickActionTileLayout.height,
                alignment: .topLeading
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(HomeQuickActionTileStyle.typingRhythmGlassStroke, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isWatermarkHovered = $0 }
        .accessibilityLabel("Update Typing Rhythm")
        .accessibilityHint("Opens retrain typing profile in Settings")
    }
}

enum HomeQuickActionTileLayout {
    static let height: CGFloat = 108
}

// Large pulse glyph centered in the tile — only background layer; grows on hover without resizing the card.
private struct HomePulseRhythmWatermark: View {
    var isHovered: Bool

    private static let restingSize: CGFloat = 104
    private static let hoverScale: CGFloat = SettingsSingleActionWatermarkInteraction.hoverScale

    var body: some View {
        Image(systemName: "waveform.path.ecg")
            .font(.system(size: Self.restingSize, weight: .light))
            .foregroundStyle(
                SettingsSecurityActionsStyle.pulseWatermarkColor.opacity(isHovered ? 0.48 : 0.36)
            )
            .scaleEffect(isHovered ? Self.hoverScale : 1)
            .animation(.spring(response: 0.32, dampingFraction: 0.68), value: isHovered)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .allowsHitTesting(false)
    }
}
