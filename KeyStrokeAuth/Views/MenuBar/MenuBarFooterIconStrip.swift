// MenuBarFooterIconStrip.swift
// Centered Preferences and Quit icon controls for the MenuBar footer area.
//
// Flow: parent supplies bottom region → gear + power icons sit centered inside it.

import SwiftUI

/// Footer icon controls centered by the parent bottom region.
struct MenuBarFooterIconStrip: View {
    let onPreferences: () -> Void
    let onQuit: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            MenuBarFooterIconButton(
                systemImage: "gearshape.fill",
                accessibilityLabel: "Preferences",
                tint: .blue,
                action: onPreferences
            )

            MenuBarFooterIconButton(
                systemImage: "power",
                accessibilityLabel: "Quit DynamicKey",
                tint: .red,
                action: onQuit
            )
        }
    }
}
