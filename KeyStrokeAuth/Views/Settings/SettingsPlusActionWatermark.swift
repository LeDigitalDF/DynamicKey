// SettingsPlusActionWatermark.swift
// Single-action play-card watermark — large action icon centered behind foreground text.
// Flow: parent supplies tint → card’s own icon (e.g. + or circle arrow) sits in the background → tap open area over it.

import SwiftUI

enum SettingsSingleActionPlayStyle {
    case add
    case destructive
    case safeMode
}

enum SettingsPlusActionStyle {
    static let addCardTint = NSColor(calibratedRed: 0.10, green: 0.52, blue: 0.30, alpha: 0.30)
    static let addWatermarkColor = Color(red: 0.32, green: 0.88, blue: 0.58)

    static let destructiveCardTint = NSColor(calibratedRed: 0.58, green: 0.14, blue: 0.14, alpha: 0.32)
    static let destructiveWatermarkColor = Color(red: 1.0, green: 0.42, blue: 0.38)

    static let safeModeCardTint = SettingsSafeModeStyle.cardTint
    static let safeModeWatermarkColor = SettingsSafeModeStyle.accentColor

    /// Default add/trust tint — Trusted Keyboards, Trusted Networks.
    static var cardTint: NSColor { addCardTint }

    static func cardTint(for style: SettingsSingleActionPlayStyle) -> NSColor {
        switch style {
        case .add:
            return addCardTint
        case .destructive:
            return destructiveCardTint
        case .safeMode:
            return safeModeCardTint
        }
    }

    static func activeCardTint(for style: SettingsSingleActionPlayStyle) -> NSColor? {
        switch style {
        case .safeMode:
            return SettingsSafeModeStyle.activeCardTint
        case .add, .destructive:
            return nil
        }
    }

    static func watermarkSystemImage(for style: SettingsSingleActionPlayStyle) -> String {
        switch style {
        case .add:
            return "plus"
        case .destructive:
            return "arrow.triangle.2.circlepath"
        case .safeMode:
            return "touchid"
        }
    }

    /// Circle-arrow reads larger than `plus` at equal point size — scale down to match visually.
    static func watermarkSize(for style: SettingsSingleActionPlayStyle) -> CGFloat {
        switch style {
        case .add:
            return 176
        case .destructive:
            return 148
        case .safeMode:
            return 176
        }
    }
}

enum SettingsSingleActionWatermarkInteraction {
    static let hoverScale: CGFloat = 1.5
    /// Quarter-turn reads as a spin on the symmetric plus without looking identical at 180°.
    static let hoverSpinDegrees: Double = 90
}

enum SettingsSingleActionPlayLayout {
    /// Bottom hit strip for standard-height single-action cards (e.g. Reset Data).
    static let standardActionStripHeight: CGFloat = 68
    /// Bottom hit strip for expanded single-action cards (e.g. Trusted Keyboards/Networks).
    static let expandedActionStripHeight: CGFloat = 112
}

/// Transparent bottom strip — hover drives watermark zoom/spin; tap runs the card action.
struct SettingsSingleActionPlayActionStrip: View {
    @Binding var isWatermarkHovered: Bool
    let accessibilityLabel: String
    var stripHeight: CGFloat = SettingsSingleActionPlayLayout.standardActionStripHeight
    let action: () -> Void

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: stripHeight)
            .contentShape(Rectangle())
            .onHover { isWatermarkHovered = $0 }
            .onTapGesture(perform: action)
            .accessibilityElement()
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
    }
}

struct SettingsPlusActionWatermark: View {
    var style: SettingsSingleActionPlayStyle = .add
    var isHovered: Bool = false
    var isEmphasized: Bool = false

    @State private var heartbeatPulseAmount: CGFloat = 0

    private var watermarkSize: CGFloat {
        SettingsPlusActionStyle.watermarkSize(for: style)
    }

    private var watermarkColor: Color {
        switch style {
        case .add:
            return SettingsPlusActionStyle.addWatermarkColor
        case .destructive:
            return SettingsPlusActionStyle.destructiveWatermarkColor
        case .safeMode:
            return SettingsPlusActionStyle.safeModeWatermarkColor
        }
    }

    private var usesHeartbeat: Bool {
        style == .safeMode && isEmphasized && !isHovered
    }

    /// Grow point size on hover — vector re-render stays sharp (same approach as dual-action icons).
    private var displayedWatermarkSize: CGFloat {
        let hoverScaled = watermarkSize * (isHovered ? SettingsSingleActionWatermarkInteraction.hoverScale : 1)
        let heartbeatScaled = usesHeartbeat ? hoverScaled * (1 + heartbeatPulseAmount) : hoverScaled
        return heartbeatScaled
    }

    private var displayedOpacity: Double {
        if isHovered { return 0.48 }
        if isEmphasized { return 0.46 }
        return 0.38
    }

    private var spinDegrees: Double {
        isHovered ? SettingsSingleActionWatermarkInteraction.hoverSpinDegrees : 0
    }

    var body: some View {
        Image(systemName: SettingsPlusActionStyle.watermarkSystemImage(for: style))
            .font(.system(size: displayedWatermarkSize, weight: .light))
            .foregroundStyle(watermarkColor.opacity(displayedOpacity))
            .rotationEffect(.degrees(spinDegrees))
            .animation(.spring(response: 0.32, dampingFraction: 0.68), value: isHovered)
            .animation(.easeInOut(duration: 0.28), value: isEmphasized)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .allowsHitTesting(false)
            .task(id: usesHeartbeat) {
                guard usesHeartbeat else {
                    heartbeatPulseAmount = 0
                    return
                }

                while !Task.isCancelled && usesHeartbeat {
                    withAnimation(.easeOut(duration: 0.14)) { heartbeatPulseAmount = 0.11 }
                    try? await Task.sleep(for: .milliseconds(140))
                    guard !Task.isCancelled && usesHeartbeat else { break }

                    withAnimation(.easeIn(duration: 0.10)) { heartbeatPulseAmount = 0 }
                    try? await Task.sleep(for: .milliseconds(90))
                    guard !Task.isCancelled && usesHeartbeat else { break }

                    withAnimation(.easeOut(duration: 0.12)) { heartbeatPulseAmount = 0.08 }
                    try? await Task.sleep(for: .milliseconds(120))
                    guard !Task.isCancelled && usesHeartbeat else { break }

                    withAnimation(.easeIn(duration: 0.30)) { heartbeatPulseAmount = 0 }
                    try? await Task.sleep(for: .milliseconds(720))
                }

                heartbeatPulseAmount = 0
            }
    }
}
