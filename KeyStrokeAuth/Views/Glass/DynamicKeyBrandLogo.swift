// DynamicKeyBrandLogo.swift
// Centered app logo for landing and auth screens — loads `DynamicKeyBrand` from the asset catalog.
// Flow: load DynamicKeyBrand → fall back to NSApplication icon → system key glyph.

import AppKit
import SwiftUI

struct DynamicKeyBrandLogo: View {
    var size: CGFloat = 88

    var body: some View {
        Group {
            if NSImage(named: "DynamicKeyBrand") != nil {
                Image("DynamicKeyBrand")
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
            } else if let icon = NSApplication.shared.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
            } else {
                Image(systemName: "key.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: GlassTheme.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .accessibilityLabel("DynamicKey")
    }
}
