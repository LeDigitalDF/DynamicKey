// HomeConnectedBrowsersPlayTile.swift
// Quick Actions — connected browser watermarks behind caption; tap opens Settings → Browser Extension.
// Flow: green glass card → sized browser icons (1 large, 2–4 smaller, 5+ horizontal scroll) → navigate on tap.

import SwiftUI

struct HomeConnectedBrowsersPlayTile: View {
    @Environment(\.glassPalette) private var palette

    let pairedClients: [PairedExtensionClient]
    let isExtensionAPIRunning: Bool
    let action: () -> Void

    @State private var isWatermarkHovered = false

    private var browserIcons: [PairedBrowserDisplay.BrowserIconDescriptor] {
        PairedBrowserDisplay.connectedBrowserIcons(from: pairedClients)
    }

    private var browserNamesSummary: String {
        let names = browserIcons.map(\.displayName)
        guard !names.isEmpty else { return "No browsers paired" }
        return names.joined(separator: ", ")
    }

    private var subtitle: String {
        let apiStatus = isExtensionAPIRunning ? "API online" : "API offline"
        return "\(browserIcons.count) paired · \(apiStatus)"
    }

    private var usesHorizontalBrowserScroll: Bool {
        browserIcons.count >= 5
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(HomeQuickActionTileStyle.connectedBrowsersGlassFill)

            HomeConnectedBrowsersWatermark(
                icons: browserIcons,
                isHovered: isWatermarkHovered,
                usesHorizontalScroll: usesHorizontalBrowserScroll
            )

            VStack(alignment: .leading, spacing: 2) {
                Text("Connected Browsers")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.onGlassPrimary)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(palette.onGlassSecondary)
                    .lineLimit(2)
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
                .strokeBorder(HomeQuickActionTileStyle.connectedBrowsersGlassStroke, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: action)
        .onHover { isWatermarkHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Connected browsers, \(browserNamesSummary)")
        .accessibilityHint("Opens browser extension settings")
        .accessibilityAddTraits(.isButton)
    }
}

enum HomeQuickActionTileStyle {
    static let connectedBrowsersGlassFill = Color.green.opacity(0.06)
    static let connectedBrowsersGlassStroke = Color.green.opacity(0.16)
    static let typingRhythmGlassFill = Color.blue.opacity(0.06)
    static let typingRhythmGlassStroke = Color.blue.opacity(0.16)
}

// Background browser glyphs — one large icon or a row that scrolls when five or more are paired.
private struct HomeConnectedBrowsersWatermark: View {
    let icons: [PairedBrowserDisplay.BrowserIconDescriptor]
    var isHovered: Bool
    var usesHorizontalScroll: Bool

    private var iconSize: CGFloat {
        PairedBrowserDisplay.homeWatermarkIconSize(browserCount: icons.count)
    }

    private var hoverScale: CGFloat {
        let activeScale = icons.count > 1 ? 1.22 : SettingsSingleActionWatermarkInteraction.hoverScale
        return isHovered ? activeScale : 1
    }

    /// Extra gap between icons so hover growth does not overlap neighbors.
    private var iconSlotSpacing: CGFloat {
        switch icons.count {
        case 2:
            return 30
        case 3:
            return 20
        case 4:
            return 16
        default:
            return 12
        }
    }

    /// Fixed slot per icon — reserves space for hover scale inside the tile.
    private var iconSlotSize: CGFloat {
        iconSize * (icons.count > 1 ? 1.28 : 1.35)
    }

    var body: some View {
        Group {
            if icons.isEmpty {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Color.green.opacity(0.28))
            } else if usesHorizontalScroll {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(icons) { icon in
                            browserWatermarkIcon(icon)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                HStack(spacing: icons.count > 1 ? iconSlotSpacing : 0) {
                    ForEach(icons) { icon in
                        browserWatermarkIcon(icon)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .allowsHitTesting(usesHorizontalScroll)
    }

    private func browserWatermarkIcon(_ icon: PairedBrowserDisplay.BrowserIconDescriptor) -> some View {
        Image(systemName: icon.systemImage)
            .font(.system(size: iconSize, weight: .light))
            .foregroundStyle(icon.tint.opacity(isHovered ? 0.48 : 0.36))
            .frame(width: iconSlotSize, height: iconSlotSize)
            .scaleEffect(hoverScale)
            .animation(.spring(response: 0.32, dampingFraction: 0.68), value: isHovered)
    }
}
