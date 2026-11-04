// MenuBarPanelFingerprintWatermark.swift
// Large centered fingerprint watermark behind the full MenuBar panel content.
//
// Flow: measure panel bounds → draw touchid at center → stays inside the liquid glass layer.

import SwiftUI

struct MenuBarPanelFingerprintWatermark: View {
    @Environment(\.glassPalette) private var palette

    var body: some View {
        GeometryReader { geometry in
            let spread = max(geometry.size.width, geometry.size.height) * 0.72

            Image(systemName: "touchid")
                .font(.system(size: spread, weight: .ultraLight))
                .foregroundStyle(palette.onGlassPrimary.opacity(0.10))
                .frame(width: geometry.size.width, height: geometry.size.height)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}
