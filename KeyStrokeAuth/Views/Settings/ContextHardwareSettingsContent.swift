// ContextHardwareSettingsContent.swift
// Settings card bodies for trusted keyboards and trusted Wi-Fi networks.
// Flow: show current context → list trusted entries → tap open area over + watermark to add.

import SwiftUI

// Shared status row for keyboard and network trust cards.
private struct TrustContextStatusRow: View {
    let nowLabel: String
    let state: TrustRuleUIState
    var footnote: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(state.indicatorColor)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Now: \(nowLabel)")
                        .font(.caption.weight(.semibold))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(state.statusLabel)
                        .font(.caption2)
                        .foregroundStyle(state.indicatorColor)
                }
            }

            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// Trusted keyboard list — status text above a centered + watermark; tap the open area to trust.
struct TrustedKeyboardsSettingsContent: View {
    @ObservedObject private var trustContext = TrustContextStore.shared
    @Binding var isPlusHovered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            currentKeyboardRow

            if trustContext.trustedKeyboards.isEmpty {
                Text("No keyboards trusted yet. Add your current keyboard to restrict unlock to known devices.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(trustContext.trustedKeyboards) { keyboard in
                    trustedKeyboardRow(keyboard)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: SettingsCardLayout.expandedFrontContentHeight,
            maxHeight: SettingsCardLayout.expandedFrontContentHeight,
            alignment: .topLeading
        )
        .overlay(alignment: .bottom) {
            SettingsSingleActionPlayActionStrip(
                isWatermarkHovered: $isPlusHovered,
                accessibilityLabel: "Trust Current Keyboard",
                stripHeight: SettingsSingleActionPlayLayout.expandedActionStripHeight,
                action: { _ = trustContext.trustCurrentKeyboards() }
            )
        }
    }

    /// Shows the active keyboard and whether trust rules apply to it.
    private var currentKeyboardRow: some View {
        let connected = HardwareContextService.connectedKeyboards()
        let label = connected.first?.displayName ?? "Unknown keyboard"

        return TrustContextStatusRow(
            nowLabel: label,
            state: trustContext.keyboardTrustUIState
        )
    }

    /// Renders one trusted keyboard row with a remove action.
    private func trustedKeyboardRow(_ keyboard: TrustedKeyboard) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "keyboard")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(keyboard.displayName)
                .font(.caption)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button {
                trustContext.removeKeyboard(id: keyboard.id)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.85))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(keyboard.displayName)")
        }
    }
}

// Trusted Wi-Fi list — status text above a centered + watermark; tap the open area to trust.
struct TrustedNetworksSettingsContent: View {
    @ObservedObject private var trustContext = TrustContextStore.shared
    @ObservedObject private var locationAccess = WiFiLocationAccessService.shared
    @Binding var isPlusHovered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            currentNetworkRow

            if trustContext.trustedNetworks.isEmpty {
                Text("All networks are allowed until you add trusted Wi-Fi names.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(trustContext.trustedNetworks) { network in
                    trustedNetworkRow(network)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: SettingsCardLayout.expandedFrontContentHeight,
            maxHeight: SettingsCardLayout.expandedFrontContentHeight,
            alignment: .topLeading
        )
        .overlay(alignment: .bottom) {
            SettingsSingleActionPlayActionStrip(
                isWatermarkHovered: $isPlusHovered,
                accessibilityLabel: "Trust Current Network",
                stripHeight: SettingsSingleActionPlayLayout.expandedActionStripHeight,
                action: trustCurrentNetwork
            )
        }
        .onAppear {
            locationAccess.requestAccessIfNeeded()
        }
    }

    /// Shows the current Wi-Fi name and whether trust rules apply to it.
    private var currentNetworkRow: some View {
        let ssidUnavailable = HardwareContextService.currentWiFiNetworkName() == nil

        return TrustContextStatusRow(
            nowLabel: HardwareContextService.currentWiFiStatusLabel(),
            state: trustContext.networkTrustUIState,
            footnote: ssidUnavailable ? locationAccess.ssidUnavailableFootnote : nil
        )
    }

    /// Renders one trusted network row with a remove action.
    private func trustedNetworkRow(_ network: TrustedNetwork) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(network.ssid)
                .font(.caption)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button {
                trustContext.removeNetwork(id: network.id)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.85))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(network.ssid)")
        }
    }

    /// Requests Location if needed, then adds the current SSID when readable.
    private func trustCurrentNetwork() {
        locationAccess.requestAccessIfNeeded()
        _ = trustContext.trustCurrentNetwork()
    }
}
