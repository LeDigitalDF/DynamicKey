// DetailPaneSectionIconWatermarkBackground.swift
// Large centered SF Symbol watermark for main detail panes (Settings gear pattern).
// Flow: section icon → ultraLight at ~68% of pane → white 18% opacity → non-interactive.

import SwiftUI

struct DetailPaneSectionIconWatermarkBackground: View {
    let section: MainSidebarSection

    @Environment(\.glassPalette) private var palette

    var body: some View {
        GeometryReader { geometry in
            let spreadSize = max(geometry.size.width, geometry.size.height) * 0.68

            Image(systemName: section.systemImage)
                .font(.system(size: spreadSize, weight: .ultraLight))
                .foregroundStyle(palette.onGlassPrimary.opacity(0.12))
                .frame(width: geometry.size.width, height: geometry.size.height)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}
