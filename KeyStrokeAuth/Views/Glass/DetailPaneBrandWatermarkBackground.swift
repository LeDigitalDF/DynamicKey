// DetailPaneBrandWatermarkBackground.swift
// Large centered brand watermark for the Home dashboard only (`HomeWatermark` asset).
// Flow: load `HomeWatermark` from asset catalog → centered at ~68% of pane → non-interactive.

import AppKit
import SwiftUI

struct DetailPaneBrandWatermarkBackground: View {
    @Environment(\.glassPalette) private var palette

    var body: some View {
        GeometryReader { geometry in
            let spreadSize = max(geometry.size.width, geometry.size.height) * 0.68

            Group {
                if NSImage(named: "HomeWatermark") != nil {
                    Image("HomeWatermark")
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .scaledToFit()
                } else {
                    Image(systemName: "eye")
                        .font(.system(size: spreadSize * 0.35, weight: .ultraLight))
                        .foregroundStyle(palette.onGlassPrimary.opacity(0.12))
                }
            }
            .frame(width: spreadSize, height: spreadSize)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}
