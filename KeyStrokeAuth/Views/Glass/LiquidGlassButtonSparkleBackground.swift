// LiquidGlassButtonSparkleBackground.swift
// Soft drifting color blooms clipped inside a liquid-glass button — no sharp pixels.
// Flow: TimelineView → blurred Canvas orbs → palette-tinted sparks behind the label.

import SwiftUI

enum LiquidGlassSparklePalette {
    case playful
    case neutral
    case destructive
    case blue
    case green
    case cyan
    case enroll
    case indigo

    var colors: [Color] {
        switch self {
        case .playful:
            return [
                Color(red: 1.0, green: 0.42, blue: 0.68),
                Color(red: 0.38, green: 0.82, blue: 1.0),
                Color(red: 1.0, green: 0.78, blue: 0.22),
                Color(red: 0.58, green: 0.48, blue: 1.0),
                Color(red: 0.28, green: 0.92, blue: 0.62),
            ]
        case .neutral:
            return [
                Color(white: 0.82),
                Color(red: 0.62, green: 0.66, blue: 0.72),
                Color(white: 0.58),
                Color(red: 0.48, green: 0.52, blue: 0.58),
                Color(white: 0.72),
            ]
        case .destructive:
            return [
                Color(red: 1.0, green: 0.34, blue: 0.30),
                Color(red: 0.90, green: 0.16, blue: 0.20),
                Color(red: 1.0, green: 0.52, blue: 0.36),
                Color(red: 0.76, green: 0.10, blue: 0.16),
                Color(red: 1.0, green: 0.40, blue: 0.34),
            ]
        case .blue:
            return [
                Color(red: 0.22, green: 0.48, blue: 0.95),
                Color(red: 0.38, green: 0.66, blue: 1.0),
                Color(red: 0.14, green: 0.36, blue: 0.82),
                Color(red: 0.52, green: 0.76, blue: 1.0),
                Color(red: 0.18, green: 0.54, blue: 0.92),
            ]
        case .green:
            return [
                Color(red: 0.18, green: 0.78, blue: 0.42),
                Color(red: 0.32, green: 0.88, blue: 0.58),
                Color(red: 0.10, green: 0.62, blue: 0.34),
                Color(red: 0.44, green: 0.92, blue: 0.66),
                Color(red: 0.22, green: 0.70, blue: 0.48),
            ]
        case .cyan:
            return [
                Color(red: 0.12, green: 0.78, blue: 0.82),
                Color(red: 0.28, green: 0.88, blue: 0.92),
                Color(red: 0.08, green: 0.62, blue: 0.68),
                Color(red: 0.40, green: 0.92, blue: 0.96),
                Color(red: 0.16, green: 0.72, blue: 0.78),
            ]
        case .enroll:
            return [
                Color.purple.opacity(0.88),
                Color(red: 0.58, green: 0.28, blue: 0.92),
                Color(red: 0.42, green: 0.16, blue: 0.72),
                Color(red: 0.72, green: 0.38, blue: 0.98),
                Color(red: 0.50, green: 0.22, blue: 0.82),
            ]
        case .indigo:
            return [
                Color.indigo.opacity(0.88),
                Color(red: 0.42, green: 0.34, blue: 0.94),
                Color(red: 0.28, green: 0.22, blue: 0.78),
                Color(red: 0.55, green: 0.46, blue: 0.98),
                Color(red: 0.36, green: 0.30, blue: 0.86),
            ]
        }
    }

    /// Light Mode uses deeper, more saturated blooms so sparkle buttons read clearly on pale glass.
    func colors(for colorScheme: ColorScheme) -> [Color] {
        guard colorScheme == .light else { return colors }
        switch self {
        case .enroll:
            return [
                Color(red: 0.50, green: 0.18, blue: 0.86),
                Color(red: 0.42, green: 0.14, blue: 0.76),
                Color(red: 0.34, green: 0.10, blue: 0.66),
                Color(red: 0.58, green: 0.24, blue: 0.90),
                Color(red: 0.46, green: 0.16, blue: 0.80),
            ]
        case .blue:
            return [
                Color(red: 0.14, green: 0.36, blue: 0.86),
                Color(red: 0.22, green: 0.48, blue: 0.94),
                Color(red: 0.10, green: 0.28, blue: 0.76),
                Color(red: 0.28, green: 0.54, blue: 0.96),
                Color(red: 0.16, green: 0.40, blue: 0.84),
            ]
        default:
            return colors
        }
    }
}

struct LiquidGlassButtonSparkleBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var sparklePalette: LiquidGlassSparklePalette = .playful

    private var sparkColors: [Color] {
        sparklePalette.colors(for: colorScheme)
    }

    private var usesLightModeDepth: Bool {
        colorScheme == .light
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            Canvas { context, size in
                guard size.width > 4, size.height > 4 else { return }
                let time = timeline.date.timeIntervalSinceReferenceDate
                drawFluentSparks(in: &context, size: size, time: time)
            }
        }
        .allowsHitTesting(false)
    }

    /// Large blurred color orbs — smooth motion, heavy blur so edges melt together.
    private func drawFluentSparks(in context: inout GraphicsContext, size: CGSize, time: Double) {
        let orbCount = 5
        var orbCenters: [(center: CGPoint, radius: CGFloat, breathe: Double, colorIndex: Int)] = []

        for index in 0..<orbCount {
            let seed = Double(index)
            let centerX = size.width * (0.5 + sin(time * (0.38 + seed * 0.06) + seed * 0.7) * 0.30)
            let centerY = size.height * (0.5 + cos(time * (0.32 + seed * 0.05) + seed * 1.05) * 0.26)
            let breathe = sparkBreathe(at: time, seed: seed)
            let radius = max(9, min(size.width, size.height) * (0.50 + 0.12 * sin(time * 0.48 + seed)))
            orbCenters.append((
                center: CGPoint(x: centerX, y: centerY),
                radius: radius,
                breathe: breathe,
                colorIndex: index
            ))
        }

        var glowLayer = context
        glowLayer.addFilter(.blur(radius: 8))

        for orb in orbCenters {
            let rect = CGRect(
                x: orb.center.x - orb.radius,
                y: orb.center.y - orb.radius,
                width: orb.radius * 2,
                height: orb.radius * 2
            )

            glowLayer.fill(
                Path(ellipseIn: rect),
                with: .color(sparkColors[orb.colorIndex % sparkColors.count].opacity(orb.breathe))
            )
        }

        var highlightLayer = context
        highlightLayer.addFilter(.blur(radius: 4))

        for index in 0..<3 {
            let seed = Double(index) + 8
            let centerX = size.width * (0.5 + sin(time * (0.52 + seed * 0.04) + seed) * 0.22)
            let centerY = size.height * (0.5 + cos(time * (0.44 + seed * 0.03) + seed * 0.9) * 0.20)
            let pulse = highlightPulse(at: time, seed: seed)
            let radius = max(6, min(size.width, size.height) * 0.26)
            let rect = CGRect(x: centerX - radius, y: centerY - radius, width: radius * 2, height: radius * 2)

            highlightLayer.fill(
                Path(ellipseIn: rect),
                with: .color(sparkColors[(index + 2) % sparkColors.count].opacity(pulse))
            )
        }
    }

    private func sparkBreathe(at time: Double, seed: Double) -> Double {
        let wave = 0.48 + 0.28 * sin(time * (0.75 + seed * 0.1) + seed)
        return usesLightModeDepth ? min(0.88, wave + 0.12) : wave
    }

    private func highlightPulse(at time: Double, seed: Double) -> Double {
        let wave = 0.34 + 0.26 * abs(sin(time * (1.1 + seed * 0.08) + seed))
        return usesLightModeDepth ? min(0.84, wave + 0.10) : wave
    }
}

// Plain liquid-glass label button with optional palette-tinted sparkle overlay.
struct LiquidGlassSparkleButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.glassPalette) private var palette

    let title: String
    var horizontalPadding: CGFloat = 16
    var verticalPadding: CGFloat = 5
    var font: Font = .subheadline.weight(.semibold)
    var minHeight: CGFloat? = nil
    var expandsFullWidth: Bool = false
    var usesCapsuleShape: Bool = false
    var sparklePalette: LiquidGlassSparklePalette = .playful
    var titleColor: Color?
    /// Soft drop shadow under the glass capsule — used on primary auth actions.
    var showsDropShadow: Bool = false
    /// Keeps button width stable when `title` changes (e.g. Show ↔ Hide).
    var widthAnchorTitle: String? = nil
    var isEnabled: Bool = true
    var submitOnReturn: Bool = false
    var accessibilityLabel: String?
    let action: () -> Void

    var body: some View {
        Group {
            if submitOnReturn {
                sparkleButton.keyboardShortcut(.return, modifiers: [])
            } else {
                sparkleButton
            }
        }
    }

    private var sparkleButton: some View {
        Button(action: action) {
            labelStack
                .padding(.vertical, verticalPadding)
                .padding(.horizontal, horizontalPadding)
                .frame(minHeight: minHeight)
                .frame(maxWidth: expandsFullWidth ? .infinity : nil)
                .background { glassSparkleBackground }
                .clipShape(buttonShape)
                .contentShape(buttonShape)
                .modifier(SparkleButtonDropShadowModifier(
                    isEnabled: showsDropShadow,
                    palette: palette
                ))
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel ?? title)
    }

    private var labelStack: some View {
        ZStack {
            if let widthAnchorTitle {
                Text(widthAnchorTitle)
                    .font(font)
                    .opacity(0)
                    .accessibilityHidden(true)
            }

            Text(title)
                .font(font)
                .foregroundStyle(resolvedTitleColor)
        }
    }

    // Light Mode uses black labels; Dark Mode keeps white for contrast on vivid sparkle fills.
    private var resolvedTitleColor: Color {
        if let titleColor { return titleColor }
        return colorScheme == .light ? GlassTheme.buttonLabelColor : .white
    }

    // Light Mode uses normal compositing so the slightly deeper blooms stay visible on pale glass.
    private var sparkleBlendMode: BlendMode {
        colorScheme == .light ? .normal : .plusLighter
    }

    @ViewBuilder
    private var glassSparkleBackground: some View {
        if usesCapsuleShape {
            Capsule(style: .continuous)
                .fill(Color.clear)
                .glassEffect()
                .overlay {
                    LiquidGlassButtonSparkleBackground(sparklePalette: sparklePalette)
                        .blendMode(sparkleBlendMode)
                }
                .allowsHitTesting(false)
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.clear)
                .glassEffect()
                .overlay {
                    LiquidGlassButtonSparkleBackground(sparklePalette: sparklePalette)
                        .blendMode(sparkleBlendMode)
                }
                .allowsHitTesting(false)
        }
    }

    private var buttonShape: AnyShape {
        if usesCapsuleShape {
            return AnyShape(Capsule(style: .continuous))
        }
        return AnyShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// Layered drop shadow so primary auth capsules lift off the landing/login backdrop.
private struct SparkleButtonDropShadowModifier: ViewModifier {
    let isEnabled: Bool
    let palette: GlassPalette

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .shadow(color: palette.shadowStrong, radius: 8, x: 0, y: 4)
                .shadow(color: palette.shadowSoft, radius: 2, x: 0, y: 1)
        } else {
            content
        }
    }
}
