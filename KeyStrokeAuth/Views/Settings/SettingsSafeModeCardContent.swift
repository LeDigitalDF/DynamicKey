// SettingsSafeModeCardContent.swift
// Safe Mode single-action play card — fingerprint watermark, tap to activate, countdown while on.
// Flow: inactive → caption + tap strip → activate 24h → status copy + live clock at bottom.

import AppKit
import SwiftUI

enum SettingsSafeModeStyle {
    static let cardTint = NSColor(calibratedRed: 0.38, green: 0.20, blue: 0.06, alpha: 0.24)
    static let activeCardTint = NSColor(calibratedRed: 0.62, green: 0.28, blue: 0.06, alpha: 0.40)
    static let accentColor = Color(red: 1.0, green: 0.58, blue: 0.18)
}

struct SettingsSafeModeCardContent: View {
    @Environment(\.glassPalette) private var palette
    @ObservedObject private var safeMode = SafeModeStore.shared
    @Binding var isWatermarkHovered: Bool

    var body: some View {
        Group {
            if safeMode.isActive {
                activeContent
            } else {
                inactiveContent
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: SettingsCardLayout.frontContentHeight,
            maxHeight: SettingsCardLayout.frontContentHeight,
            alignment: .center
        )
        .animation(.easeInOut(duration: 0.28), value: safeMode.isActive)
    }

    /// Inactive — caption at top; tap anywhere on the card front (including the fingerprint) to activate.
    private var inactiveContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tap to activate Safe Mode for 24 hours when rhythm is unreliable — for example an injured hand or arm.")
                .font(.caption)
                .foregroundStyle(palette.onGlassSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onHover { isWatermarkHovered = $0 }
        .onTapGesture {
            safeMode.activate()
        }
        .accessibilityElement()
        .accessibilityLabel("Activate Safe Mode")
        .accessibilityAddTraits(.isButton)
    }

    /// Active — large centered countdown; explicit Turn Off (no tap-to-extend).
    private var activeContent: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            VStack(spacing: 4) {
                Text(safeMode.formattedRemainingTime)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(palette.onGlassPrimary)
                    .contentTransition(.numericText())

                Text("remaining")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SettingsSafeModeStyle.accentColor)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Safe Mode time remaining \(safeMode.formattedRemainingTime)")

            Spacer(minLength: 0)

            Button(action: { safeMode.deactivate() }) {
                Text("Turn Off")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GlassTheme.buttonLabelColor)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 16)
                    .glassEffect()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Turn Off")
            .accessibilityHint("Ends Safe Mode immediately")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
