// DynamicKeyDashboardBackground.swift
// Shared app backdrop for the main shell and the entire auth flow (landing, login, enrollment).
// Flow: Dark Mode → opaque black base with slowly floating glowing orbs (green, orange, red);
//       Light Mode → opaque pale base with softly drifting pastel orbs (teal, orange, violet).
//
// Why opaque: the App Store rejects apps whose window is transparent at launch. The solid base
// here guarantees the main shell always paints a background (the window chrome is also made
// opaque in MainWindowChromeConfigurator).

import SwiftUI

struct DynamicKeyDashboardBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if colorScheme == .dark {
            DashboardDarkGlowBackground()
        } else {
            DashboardLightGlowBackground()
        }
    }
}

// Opaque black backdrop with a few large, softly blurred color orbs that drift slowly.
private struct DashboardDarkGlowBackground: View {
    // Glow colors requested for the dashboard: green (safe), orange (caution), red (alert).
    private let green = Color(red: 0.20, green: 0.90, blue: 0.50)
    private let orange = Color(red: 1.00, green: 0.62, blue: 0.20)
    private let red = Color(red: 0.98, green: 0.28, blue: 0.32)

    var body: some View {
        // 30fps timeline drives the slow drift without pegging the CPU.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                // Solid, fully opaque base — this is the "black background" the dashboard needs.
                Color.black
                glowOrbs(at: time)
            }
        }
        .ignoresSafeArea()
    }

    // Four drifting orbs positioned across the canvas; each moves on a slow sine/cosine path.
    // Amplitudes (~0.16 of the canvas) and speeds are large enough to read as motion, yet gentle.
    private func glowOrbs(at time: Double) -> some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                orb(
                    color: green,
                    size: side * 0.55,
                    center: CGPoint(
                        x: proxy.size.width * (0.26 + 0.16 * sin(time * 0.17)),
                        y: proxy.size.height * (0.32 + 0.14 * cos(time * 0.13))
                    )
                )
                orb(
                    color: orange,
                    size: side * 0.48,
                    center: CGPoint(
                        x: proxy.size.width * (0.74 + 0.16 * cos(time * 0.15)),
                        y: proxy.size.height * (0.64 + 0.15 * sin(time * 0.12))
                    )
                )
                orb(
                    color: red,
                    size: side * 0.42,
                    center: CGPoint(
                        x: proxy.size.width * (0.60 + 0.18 * sin(time * 0.11)),
                        y: proxy.size.height * (0.24 + 0.14 * cos(time * 0.16))
                    )
                )
                orb(
                    color: green,
                    size: side * 0.40,
                    center: CGPoint(
                        x: proxy.size.width * (0.48 + 0.17 * cos(time * 0.10)),
                        y: proxy.size.height * (0.80 + 0.13 * sin(time * 0.14))
                    )
                )
            }
        }
    }

    // A single soft glowing ball: radial gradient fading to clear, heavily blurred.
    private func orb(color: Color, size: CGFloat, center: CGPoint) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.38), color.opacity(0.0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.5
                )
            )
            .frame(width: size, height: size)
            .position(center)
            .blur(radius: 48)
    }
}

// Opaque pale backdrop with soft pastel orbs — mirrors the dark dashboard motion in Light Mode.
private struct DashboardLightGlowBackground: View {
    private let base = Color(red: 0.94, green: 0.95, blue: 0.98)
    private let teal = Color(red: 0.12, green: 0.78, blue: 0.82)
    private let orange = Color(red: 1.00, green: 0.72, blue: 0.42)
    private let violet = Color(red: 0.55, green: 0.45, blue: 0.92)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                base
                glowOrbs(at: time)
            }
        }
        .ignoresSafeArea()
    }

    private func glowOrbs(at time: Double) -> some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                orb(
                    color: teal,
                    size: side * 0.55,
                    center: CGPoint(
                        x: proxy.size.width * (0.26 + 0.16 * sin(time * 0.17)),
                        y: proxy.size.height * (0.32 + 0.14 * cos(time * 0.13))
                    )
                )
                orb(
                    color: orange,
                    size: side * 0.48,
                    center: CGPoint(
                        x: proxy.size.width * (0.74 + 0.16 * cos(time * 0.15)),
                        y: proxy.size.height * (0.64 + 0.15 * sin(time * 0.12))
                    )
                )
                orb(
                    color: violet,
                    size: side * 0.42,
                    center: CGPoint(
                        x: proxy.size.width * (0.60 + 0.18 * sin(time * 0.11)),
                        y: proxy.size.height * (0.24 + 0.14 * cos(time * 0.16))
                    )
                )
                orb(
                    color: teal,
                    size: side * 0.40,
                    center: CGPoint(
                        x: proxy.size.width * (0.48 + 0.17 * cos(time * 0.10)),
                        y: proxy.size.height * (0.80 + 0.13 * sin(time * 0.14))
                    )
                )
            }
        }
    }

    private func orb(color: Color, size: CGFloat, center: CGPoint) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.24), color.opacity(0.0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.5
                )
            )
            .frame(width: size, height: size)
            .position(center)
            .blur(radius: 48)
    }
}
