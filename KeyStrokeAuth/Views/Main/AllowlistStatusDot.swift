// AllowlistStatusDot.swift
// Green/red status indicator for allowlist rows — optional glow pulse when toggled.

import SwiftUI

struct AllowlistStatusDot: View {
    let isAllowed: Bool
    var animatesOnToggle: Bool = false

    @State private var glowBoost: CGFloat = 1.0
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0

    var body: some View {
        ZStack {
            if animatesOnToggle {
                Circle()
                    .fill(glowColor.opacity(0.45))
                    .frame(width: 10, height: 10)
                    .scaleEffect(pulseScale)
                    .opacity(pulseOpacity)
            }

            Circle()
                .fill(isAllowed ? Color.green : Color.red)
                .frame(width: 10, height: 10)
                .shadow(color: glowColor.opacity(0.55 * glowBoost), radius: 5 * glowBoost, x: 0, y: 0)
                .shadow(color: glowColor.opacity(0.30 * glowBoost), radius: 10 * glowBoost, x: 0, y: 0)
                .animation(.spring(response: 0.34, dampingFraction: 0.62), value: isAllowed)
        }
        .frame(width: 22, height: 22)
        .accessibilityLabel(isAllowed ? "Allowed" : "Not allowed")
        .onChange(of: isAllowed) { _, _ in
            guard animatesOnToggle else { return }
            playToggleGlow()
        }
    }

    private var glowColor: Color {
        isAllowed ? .green : .red
    }

    private func playToggleGlow() {
        glowBoost = 1.0
        pulseScale = 1.0
        pulseOpacity = 0.75

        withAnimation(.easeOut(duration: 0.18)) {
            glowBoost = 2.4
        }

        withAnimation(.easeOut(duration: 0.55)) {
            pulseScale = 2.8
            pulseOpacity = 0
        }

        withAnimation(.easeInOut(duration: 0.5).delay(0.12)) {
            glowBoost = 1.0
        }
    }
}
