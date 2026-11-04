// PasswordStrengthBar.swift
// Thin gradient strength indicator shown under account password fields.

import SwiftUI

struct PasswordStrengthBar: View {
    @Environment(\.glassPalette) private var palette

    let strength: AccountPasswordStrength

    var body: some View {
        if strength == .empty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(palette.onGlassSecondary.opacity(0.18))

                        Capsule(style: .continuous)
                            .fill(strengthGradient)
                            .frame(width: max(0, proxy.size.width * strength.fillFraction))
                    }
                }
                .frame(height: 4)

                Text(strength.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var strengthGradient: LinearGradient {
        switch strength {
        case .empty:
            return LinearGradient(colors: [.clear], startPoint: .leading, endPoint: .trailing)
        case .weak:
            return LinearGradient(
                colors: [Color.red.opacity(0.85), Color.orange.opacity(0.9)],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .fair:
            return LinearGradient(
                colors: [Color.orange.opacity(0.9), Color.yellow.opacity(0.95)],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .good:
            return LinearGradient(
                colors: [Color.yellow.opacity(0.95), Color.green.opacity(0.85)],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .strong:
            return LinearGradient(
                colors: [Color.green.opacity(0.85), Color(red: 0.12, green: 0.78, blue: 0.82)],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .matched:
            return LinearGradient(
                colors: [Color.green.opacity(0.85), Color.green.opacity(0.65)],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .mismatch:
            return LinearGradient(
                colors: [Color.red.opacity(0.75), Color.orange.opacity(0.85)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}
