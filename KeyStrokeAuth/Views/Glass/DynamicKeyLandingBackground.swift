// DynamicKeyLandingBackground.swift
// Landing backdrop: drifting rhythm pulses and soft keystroke ticks — original, lightweight motion.
// Flow: base gradient + Canvas waves + blurred accent orbs animated on a timeline.

import SwiftUI

struct DynamicKeyLandingBackground: View {
    @Environment(\.glassPalette) private var palette

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                baseGradient
                rhythmCanvas(at: time)
                accentOrbs(at: time)
            }
        }
        .ignoresSafeArea()
    }

    // Theme-aware base with a gentle accent wash.
    private var baseGradient: some View {
        LinearGradient(
            colors: [palette.landingSurfaceTop, palette.landingSurfaceMid, palette.landingSurfaceBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // Horizontal rhythm lines that travel outward — evokes typing intervals.
    private func rhythmCanvas(at time: Double) -> some View {
        Canvas { context, size in
            let lineCount = 7
            for index in 0..<lineCount {
                let progress = (time * 0.22 + Double(index) * 0.14).truncatingRemainder(dividingBy: 1.0)
                let y = size.height * (0.18 + Double(index) * 0.11)
                let startX = size.width * (0.08 + progress * 0.84)
                let endX = startX + size.width * 0.12
                var path = Path()
                path.move(to: CGPoint(x: startX, y: y))
                path.addLine(to: CGPoint(x: endX, y: y))

                let opacity = 0.04 + 0.06 * (1.0 - abs(progress - 0.5) * 2.0)
                context.stroke(
                    path,
                    with: .color(palette.rhythmLine),
                    lineWidth: 1
                )

                // Small “keystrike” dot at the leading edge of each pulse.
                let dotRect = CGRect(x: startX - 2, y: y - 2, width: 4, height: 4)
                context.fill(
                    Path(ellipseIn: dotRect),
                    with: .color(Color.accentColor.opacity(opacity * 1.8))
                )
            }
        }
        .blur(radius: 0.4)
        .opacity(0.85)
    }

    // Slow drifting color blobs behind the glass UI.
    private func accentOrbs(at time: Double) -> some View {
        GeometryReader { proxy in
            ZStack {
                orb(
                    color: Color.blue.opacity(0.20),
                    size: min(proxy.size.width, proxy.size.height) * 0.42,
                    center: CGPoint(
                        x: proxy.size.width * (0.18 + 0.04 * sin(time * 0.35)),
                        y: proxy.size.height * (0.22 + 0.03 * cos(time * 0.28))
                    )
                )
                orb(
                    color: Color(red: 0.12, green: 0.78, blue: 0.82).opacity(0.16),
                    size: min(proxy.size.width, proxy.size.height) * 0.38,
                    center: CGPoint(
                        x: proxy.size.width * (0.78 + 0.03 * cos(time * 0.31)),
                        y: proxy.size.height * (0.68 + 0.04 * sin(time * 0.27))
                    )
                )
                orb(
                    color: Color.purple.opacity(0.14),
                    size: min(proxy.size.width, proxy.size.height) * 0.34,
                    center: CGPoint(
                        x: proxy.size.width * (0.52 + 0.05 * sin(time * 0.22)),
                        y: proxy.size.height * (0.42 + 0.04 * cos(time * 0.33))
                    )
                )
            }
        }
    }

    private func orb(color: Color, size: CGFloat, center: CGPoint) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color, color.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.5
                )
            )
            .frame(width: size, height: size)
            .position(center)
            .blur(radius: 28)
    }
}
