// SiteCredentialCard.swift
// Widget-style card for one saved website credential (Home dashboard visual language).
// Flow: liquid glass surface → site info → Show/Remove sparkle glass buttons.

import SwiftUI

struct SiteCredentialCard: View {
    @Environment(\.glassPalette) private var palette

    let credential: SiteCredential
    let isRevealed: Bool
    let onToggleReveal: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 4) {
                Text(displayTitle(for: credential.origin))
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity)

                Text(credential.origin)
                    .font(.caption2)
                    .foregroundStyle(palette.onGlassSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity)
            }

            emailRow

            VStack(spacing: 4) {
                Text(credential.isGenerated ? "24-character auto-generated password" : "Manual site password")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.onGlassSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)

                Group {
                    if isRevealed {
                        Text(credential.password)
                            .textSelection(.enabled)
                    } else {
                        Text(String(repeating: "•", count: maskedDotCount))
                    }
                }
                .font(.caption.monospaced())
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 14, alignment: .center)
            }

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Spacer(minLength: 0)

                LiquidGlassSparkleButton(
                    title: isRevealed ? "Hide" : "Show",
                    sparklePalette: .neutral,
                    titleColor: Color(red: 0, green: 0, blue: 0),
                    widthAnchorTitle: "Show",
                    action: onToggleReveal
                )

                LiquidGlassSparkleButton(
                    title: "Remove",
                    sparklePalette: .destructive,
                    action: onRemove
                )

                Spacer(minLength: 0)
            }
        }
        .padding(GlassTheme.padding)
        .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 220, alignment: .topLeading)
        .background {
            LiquidGlassSurface(cornerRadius: GlassTheme.cornerRadius)
        }
    }

    private var emailRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "envelope.fill")
                .font(.subheadline)
                .foregroundStyle(palette.credentialEmailAccent)

            Text(credential.username.isEmpty ? "(no username saved)" : credential.username)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(palette.credentialEmailAccent)
                .lineLimit(1)
                .truncationMode(.middle)

            credentialBadge
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var credentialBadge: some View {
        Text(credential.isGenerated ? "Generated" : "Manual")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((credential.isGenerated ? Color.accentColor : Color.orange).opacity(0.18))
            .clipShape(Capsule())
    }

    private var maskedDotCount: Int {
        if credential.isGenerated {
            return SitePasswordGenerator.defaultLength
        }
        return max(credential.password.count, SitePasswordGenerator.defaultLength)
    }

    private func displayTitle(for origin: String) -> String {
        if let host = URL(string: origin)?.host, !host.isEmpty {
            return host
        }
        return origin
    }
}
