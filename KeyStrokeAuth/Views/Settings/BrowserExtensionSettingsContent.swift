// BrowserExtensionSettingsContent.swift
// Compact browser extension cards for Settings — API status and connected browser names.
// Flow: status card → health + Chrome | Safari list; pairing card → code + round icon actions.

import AppKit
import SwiftUI

// API status and which browsers are connected (colored, pipe-separated).
struct BrowserExtensionStatusCardContent: View {
    @EnvironmentObject private var localAuthService: LocalAuthServiceManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(localAuthService.isRunning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)

                Text(localAuthService.isRunning ? "API running" : "API offline")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(localAuthService.isRunning ? .green : .red)
            }

            if localAuthService.isRunning {
                Text(localAuthService.serviceAddress)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text("\(localAuthService.pairedClientCount) paired")
                .font(.caption)
                .foregroundStyle(.secondary)

            connectedBrowsersLabel
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            localAuthService.refreshPairingCodeState()
            localAuthService.refreshPairedClients()
        }
    }

    // Connected browsers only — e.g. Chrome | Safari (unique names, each with its own color).
    private var connectedBrowsersLabel: some View {
        let labels = PairedBrowserDisplay.uniqueLabels(from: localAuthService.pairedClients)

        return Group {
            if labels.isEmpty {
                Text("None")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                        if index > 0 {
                            Text(" | ")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.45))
                        }

                        Text(label.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(label.color)
                    }
                }
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// Pairing code display and round liquid-glass pairing actions.
struct BrowserExtensionPairingCardContent: View {
    @EnvironmentObject private var localAuthService: LocalAuthServiceManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let code = localAuthService.activePairingCode,
               let expiresAt = localAuthService.pairingCodeExpiresAt {
                pairingCodeBlock(code: code, expiresAt: expiresAt)
            } else {
                Text("No active code")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 16) {
                Spacer(minLength: 0)

                SettingsRoundIconButton(
                    systemImage: "qrcode",
                    tint: .blue,
                    helpText: "Generate a short-lived pairing code for your browser extension.",
                    accessibilityLabel: "Generate pairing code",
                    action: { localAuthService.generatePairingCode() }
                )

                SettingsRoundIconButton(
                    systemImage: "xmark.circle.fill",
                    tint: .destructive,
                    helpText: "Revoke all paired browser extensions. You will need to pair again.",
                    accessibilityLabel: "Revoke pairings",
                    action: { localAuthService.revokeAllPairings() }
                )

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            localAuthService.refreshPairingCodeState()
            localAuthService.refreshPairedClients()
        }
    }

    private func pairingCodeBlock(code: String, expiresAt: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(code)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .tracking(2)

            HStack {
                PairingCodeExpiryCountdown(expiresAt: expiresAt) {
                    localAuthService.refreshPairingCodeState()
                }

                Spacer(minLength: 0)

                GlassTextButton(title: "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                }
            }
        }
    }
}

// Legacy single-panel embed — kept for compatibility if referenced elsewhere.
struct BrowserExtensionSettingsContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BrowserExtensionStatusCardContent()
            Divider()
            BrowserExtensionPairingCardContent()
        }
    }
}
