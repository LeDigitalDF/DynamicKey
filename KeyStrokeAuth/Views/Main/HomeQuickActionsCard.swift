// HomeQuickActionsCard.swift
// Home dashboard — typing rhythm and browser pairing shortcuts.
// Flow: Update Typing Rhythm → Pair Browser when needed, or extension status.

import SwiftUI

struct HomeQuickActionsCard: View {
    @Environment(\.glassPalette) private var palette

    let showsReenrollmentReminder: Bool
    let isExtensionAPIRunning: Bool
    let pairedExtensionClients: [PairedExtensionClient]
    let onUpdateTypingRhythm: () -> Void
    let onOpenBrowserExtension: () -> Void

    private var pairedExtensionCount: Int {
        pairedExtensionClients.count
    }

    private var needsExtensionPairing: Bool {
        !isExtensionAPIRunning || pairedExtensionCount == 0
    }

    var body: some View {
        HomeWidgetCard(title: "Quick Actions", usesLiquidGlass: true) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Refresh how DynamicKey recognizes your typing, or connect your browser.")
                    .font(.caption)
                    .foregroundStyle(palette.onGlassSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 12) {
                    updateTypingRhythmTile
                        .frame(maxWidth: .infinity)

                    if needsExtensionPairing {
                        pairBrowserTile
                            .frame(maxWidth: .infinity)
                    } else {
                        connectedBrowsersTile
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var updateTypingRhythmTile: some View {
        HomeTypingRhythmPlayTile(
            showsReenrollmentReminder: showsReenrollmentReminder,
            action: onUpdateTypingRhythm
        )
    }

    private var pairBrowserTile: some View {
        HomeQuickActionTile(
            systemImage: "puzzlepiece.extension.fill",
            title: "Pair Browser",
            subtitle: "Connect Chrome or Safari for web login",
            tint: .enroll,
            action: onOpenBrowserExtension
        )
    }

    private var connectedBrowsersTile: some View {
        HomeConnectedBrowsersPlayTile(
            pairedClients: pairedExtensionClients,
            isExtensionAPIRunning: isExtensionAPIRunning,
            action: onOpenBrowserExtension
        )
    }
}

// Compact action tile for rhythm update and browser pairing.
private struct HomeQuickActionTile: View {
    @Environment(\.glassPalette) private var palette

    let systemImage: String
    let title: String
    let subtitle: String
    let tint: GlassCapsuleTint
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(GlassTheme.buttonLabelColor)
                    .frame(width: 36, height: 36)
                    .background {
                        GlassCapsuleSurface(tint: tint)
                            .clipShape(Circle())
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.onGlassPrimary)

                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(palette.onGlassSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(
                maxWidth: .infinity,
                minHeight: HomeQuickActionTileLayout.height,
                maxHeight: HomeQuickActionTileLayout.height,
                alignment: .topLeading
            )
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
