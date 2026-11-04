// GlassInfoBanner.swift
// Tinted Liquid Glass banners for warnings, errors, and informational messages.

import SwiftUI

struct GlassInfoBanner: View {
    enum Kind {
        case info
        case warning
        case danger
        case success

        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .warning: return "clock.badge.exclamationmark"
            case .danger: return "lock.fill"
            case .success: return "checkmark.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .info: return .blue
            case .warning: return .orange
            case .danger: return .red
            case .success: return .green
            }
        }
    }

    let kind: Kind
    let message: String
    var accessory: AnyView?

    @Environment(\.glassPalette) private var palette

    init(kind: Kind, message: String, accessory: AnyView? = nil) {
        self.kind = kind
        self.message = message
        self.accessory = accessory
    }

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: kind.icon)
                        .foregroundStyle(kind.tint)
                        .font(.title3)
                        .fixedSize()

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(palette.onGlassSecondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                accessory
            }
            .padding(GlassTheme.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(kind.tint.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: GlassTheme.cornerRadius - 4, style: .continuous))
        }
        .overlay {
            GlassGradientBorder(cornerRadius: GlassTheme.cornerRadius)
                .opacity(0.85)
        }
        .accessibilityElement(children: .combine)
    }
}

struct GlassIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    @Environment(\.glassPalette) private var palette

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(palette.onGlassSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
