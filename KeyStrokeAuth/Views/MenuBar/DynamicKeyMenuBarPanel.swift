// DynamicKeyMenuBarPanel.swift
// Rich MenuBar window for DynamicKey status, quick actions, paired browsers, and app shortcuts.
//
// Flow: liquid glass shell → header status → pause/pair actions → paired browsers → footer icons.

import AppKit
import SwiftUI

/// High-level service state shown in the MenuBar header.
private enum MenuBarServiceState {
    case active
    case paused
    case setupRequired
    case apiStopped

    var title: String {
        switch self {
        case .active:
            return "DynamicKey Active"
        case .paused:
            return "DynamicKey Paused"
        case .setupRequired:
            return "Setup Required"
        case .apiStopped:
            return "Extension API Stopped"
        }
    }

    var indicatorColor: Color {
        switch self {
        case .active:
            return .green
        case .paused:
            return .orange
        case .setupRequired:
            return .yellow
        case .apiStopped:
            return .red
        }
    }
}

/// One paired browser row in the MenuBar device list.
private struct MenuBarBrowserRow: Identifiable {
    let id: String
    let browserName: String
    let deviceName: String
    let systemImage: String
    let tint: Color
    let isConnected: Bool
    let browserFamily: String
}

struct DynamicKeyMenuBarPanel: View {
    @ObservedObject var appStatus: AppStatusModel
    @ObservedObject var localAuthService: LocalAuthServiceManager
    @Environment(\.glassPalette) private var palette

    @State private var didCopyPairingCode = false

    private let profileStore = ProfileStore.shared

    /// Tight content height estimate so the window fits without clipping or excess bottom space.
    private var panelContentHeight: CGFloat {
        MenuBarPanelLayout.contentHeight(
            browserRowCount: browserRows.count,
            showsPairingCode: localAuthService.activePairingCode != nil
        )
    }

    /// Full MenuBar window height including outer padding and glass edge buffer.
    private var panelWindowHeight: CGFloat {
        panelContentHeight
            + (MenuBarPanelLayout.outerPadding * 2)
            + MenuBarPanelLayout.windowHeightBuffer
    }

    var body: some View {
        GlassPanel(cornerRadius: GlassTheme.cornerRadius) {
            panelContent
                .frame(minHeight: panelContentHeight, alignment: .top)
        }
        .frame(width: MenuBarPanelLayout.width)
        .fixedSize(horizontal: true, vertical: true)
        .padding(MenuBarPanelLayout.outerPadding)
        .background {
            MenuBarPanelWindowConfigurator(
                minWidth: MenuBarPanelLayout.width + (MenuBarPanelLayout.outerPadding * 2),
                minHeight: panelWindowHeight
            )
        }
        .onAppear {
            refreshPanelState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .extensionPairingsDidChange)) { _ in
            refreshPanelState()
        }
        .onChange(of: localAuthService.activePairingCode) { _, _ in
            didCopyPairingCode = false
        }
    }

    /// Main MenuBar layout inside the liquid glass container.
    private var panelContent: some View {
        ZStack(alignment: .top) {
            MenuBarPanelFingerprintWatermark()

            VStack(alignment: .leading, spacing: MenuBarPanelLayout.sectionSpacing) {
                headerSection
                Divider().opacity(0.35)
                quickActionsSection

                if let pairingCode = localAuthService.activePairingCode,
                   let expiresAt = localAuthService.pairingCodeExpiresAt {
                    pairingCodeBanner(code: pairingCode, expiresAt: expiresAt)
                }

                Divider().opacity(0.35)
                pairedBrowsersSection
                Divider().opacity(0.35)
                openMainAppButton

                ZStack {
                    MenuBarFooterIconStrip(
                        onPreferences: {
                            NotificationCenter.default.post(name: .dynamicKeyMenuBarOpenPreferences, object: nil)
                        },
                        onQuit: {
                            NSApplication.shared.terminate(nil)
                        }
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(MenuBarPanelLayout.innerPadding)
            .frame(minHeight: panelContentHeight, alignment: .top)
        }
        .frame(minHeight: panelContentHeight, alignment: .top)
    }

    // MARK: - Header

    /// Shows whether DynamicKey is active and how many browsers are paired.
    private var headerSection: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(serviceState.indicatorColor)
                .frame(width: 9, height: 9)
                .shadow(color: serviceState.indicatorColor.opacity(0.45), radius: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(serviceState.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(palette.onGlassPrimary)

                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(palette.onGlassSecondary)
            }

            Spacer(minLength: 8)

            if profileStore.hasProfile {
                Text("\(localAuthService.pairedClientCount) paired")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(palette.onGlassPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule()
                            .fill(palette.onGlassSecondary.opacity(0.14))
                    }
            }
        }
    }

    // MARK: - Quick actions

    /// Pause/resume and pairing shortcuts for common MenuBar tasks.
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Actions")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.onGlassSecondary)
                .textCase(.uppercase)

            HStack(spacing: 8) {
                menuBarActionButton(
                    title: localAuthService.isPausedByUser ? "Resume" : "Pause",
                    systemImage: localAuthService.isPausedByUser ? "play.fill" : "pause.fill",
                    prominent: true,
                    isEnabled: profileStore.hasProfile
                ) {
                    togglePauseResume()
                }

                menuBarActionButton(
                    title: "Pair Browser",
                    systemImage: "qrcode",
                    prominent: false,
                    isEnabled: profileStore.hasProfile && localAuthService.isRunning
                ) {
                    pairNewBrowser()
                }
            }
        }
    }

    /// Displays the active pairing code generated directly inside the MenuBar.
    private func pairingCodeBanner(code: String, expiresAt: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Pairing Code")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.onGlassSecondary)

                Spacer(minLength: 0)

                Button {
                    copyPairingCode(code)
                } label: {
                    Label(
                        didCopyPairingCode ? "Copied" : "Copy",
                        systemImage: didCopyPairingCode ? "checkmark" : "doc.on.doc"
                    )
                    .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(didCopyPairingCode ? .green : .blue)
            }

            Text(code)
                .font(.title3.weight(.bold))
                .monospaced()
                .textSelection(.enabled)
                .foregroundStyle(palette.onGlassPrimary)

            PairingCodeExpiryCountdown(expiresAt: expiresAt) {
                localAuthService.refreshPairingCodeState()
            }

            Text("Enter this code in your browser extension.")
                .font(.caption2)
                .foregroundStyle(palette.onGlassSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.blue.opacity(0.12))
        }
    }

    // MARK: - Paired browsers

    /// Lists the most recently paired browsers with a live connection indicator.
    private var pairedBrowsersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paired Browsers")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.onGlassSecondary)
                .textCase(.uppercase)

            if browserRows.isEmpty {
                Text("No browsers paired yet.")
                    .font(.caption)
                    .foregroundStyle(palette.onGlassSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: MenuBarPanelLayout.browserRowSpacing) {
                    ForEach(browserRows) { row in
                        MenuBarPairedBrowserRow(
                            browserName: row.browserName,
                            deviceName: row.deviceName,
                            systemImage: row.systemImage,
                            tint: row.tint,
                            isConnected: row.isConnected,
                            onOpen: { openPairedBrowser(row) },
                            onUnpair: { localAuthService.unpairClient(id: row.id) }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Footer

    /// Opens the main DynamicKey window from the MenuBar.
    private var openMainAppButton: some View {
        Button {
            NotificationCenter.default.post(name: .dynamicKeyMenuBarOpenMainApp, object: nil)
        } label: {
            Label("Open Main App", systemImage: "macwindow")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    menuBarButtonGlassBackground(
                        cornerRadius: 12,
                        tint: palette.onGlassSecondary.opacity(0.10)
                    )
                }
        }
        .buttonStyle(.plain)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(palette.onGlassPrimary)
    }

    // MARK: - Helpers

    /// Resolves the current MenuBar service state from profile and API status.
    private var serviceState: MenuBarServiceState {
        guard profileStore.hasProfile else { return .setupRequired }
        if localAuthService.isPausedByUser { return .paused }
        if localAuthService.isRunning { return .active }
        return .apiStopped
    }

    /// Secondary line under the main status title.
    private var headerSubtitle: String {
        switch serviceState {
        case .active:
            return "Extension API listening on localhost."
        case .paused:
            return "Protection paused until you resume."
        case .setupRequired:
            return "Enroll a profile in the main app first."
        case .apiStopped:
            return "Start or resume the extension API."
        }
    }

    /// Builds up to four browser rows from the normalized paired-client list.
    private var browserRows: [MenuBarBrowserRow] {
        let deviceName = Host.current().localizedName ?? "This Mac"
        let isConnected = localAuthService.isRunning && !localAuthService.isPausedByUser

        return localAuthService.pairedClients.prefix(4).map { client in
            let label = PairedBrowserDisplay.browserLabel(for: client)
            let family = PairedBrowserDisplay.resolvedFamily(
                browserFamily: client.browserFamily,
                clientName: client.clientName
            ) ?? "browser"
            let icon = PairedBrowserDisplay.iconDescriptor(forFamily: family)

            return MenuBarBrowserRow(
                id: client.id,
                browserName: label.name,
                deviceName: deviceName,
                systemImage: icon.systemImage,
                tint: label.color,
                isConnected: isConnected,
                browserFamily: family
            )
        }
    }

    /// Launches the paired browser app from the MenuBar row.
    private func openPairedBrowser(_ row: MenuBarBrowserRow) {
        _ = PairedBrowserDisplay.openBrowser(forFamily: row.browserFamily)
    }

    /// Shared capsule button style for MenuBar quick actions.
    private func menuBarActionButton(
        title: String,
        systemImage: String,
        prominent: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background {
                    menuBarButtonGlassBackground(
                        cornerRadius: 12,
                        tint: prominent
                            ? Color.accentColor.opacity(isEnabled ? 0.22 : 0.10)
                            : palette.onGlassSecondary.opacity(isEnabled ? 0.12 : 0.06)
                    )
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.onGlassPrimary)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }

    /// Liquid Glass button fill — soft blur with a light tint so the fingerprint stays partially visible.
    private func menuBarButtonGlassBackground(cornerRadius: CGFloat, tint: Color) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.clear)
            .glassEffect()
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint)
            }
    }

    /// Refreshes profile/API status and paired browser data when the panel opens.
    private func refreshPanelState() {
        appStatus.refresh()
        localAuthService.refreshPairedClients()
        localAuthService.refreshPairingCodeState()
    }

    /// Toggles user pause/resume for the extension API service.
    private func togglePauseResume() {
        if localAuthService.isPausedByUser {
            localAuthService.resumeByUser()
        } else {
            localAuthService.pauseByUser()
        }
        appStatus.refresh()
    }

    /// Generates a pairing code locally without opening the main app.
    private func pairNewBrowser() {
        didCopyPairingCode = false
        localAuthService.generatePairingCode()
    }

    /// Copies the pairing code to the clipboard for quick extension entry.
    private func copyPairingCode(_ code: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)
        didCopyPairingCode = true
    }
}
