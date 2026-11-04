// SettingsExtensionPairingFlipCard.swift
// Extension Pairing dual play-card — front picks Generate or Revoke; info flip explains both; action flip runs each flow.
// Flow: neutral tint + dual watermarks → icon tap or info flip → round back + sparkle buttons on action backs → return to front.

import AppKit
import SwiftUI

private let extensionPairingButtonTrueBlack = Color(red: 0, green: 0, blue: 0)

enum SettingsExtensionPairingAction: Equatable {
    case generateCode
    case revokePairings
}

enum SettingsExtensionPairingBackMode: Equatable {
    case info
    case action(SettingsExtensionPairingAction)
}

enum SettingsExtensionPairingStyle {
    static let frontCardTint = NSColor(calibratedRed: 0.14, green: 0.18, blue: 0.38, alpha: 0.34)
    static let generateCardTint = NSColor(calibratedRed: 0.10, green: 0.28, blue: 0.62, alpha: 0.36)
    static let revokeCardTint = NSColor(calibratedRed: 0.58, green: 0.14, blue: 0.14, alpha: 0.36)

    static let generateWatermarkColor = Color(red: 0.48, green: 0.72, blue: 1.0)
    static let revokeWatermarkColor = Color(red: 1.0, green: 0.48, blue: 0.42)

    static let generateIconColor = Color(red: 0.48, green: 0.72, blue: 1.0)
    static let revokeIconColor = Color(red: 1.0, green: 0.42, blue: 0.38)

    static func cardTint(for backMode: SettingsExtensionPairingBackMode?) -> NSColor {
        switch backMode {
        case .action(.generateCode):
            return generateCardTint
        case .action(.revokePairings):
            return revokeCardTint
        case .info, nil:
            return frontCardTint
        }
    }

    static func actionAccentColor(for backMode: SettingsExtensionPairingBackMode?) -> Color {
        switch backMode {
        case .action(.generateCode):
            return generateIconColor
        case .action(.revokePairings):
            return revokeIconColor
        case .info, nil:
            return generateIconColor
        }
    }
}

struct SettingsExtensionPairingWatermark: View {
    private let watermarkSize: CGFloat = 162
    private let generateOffsetX: CGFloat = -86
    private let generateOffsetY: CGFloat = 16
    private let revokeOffsetX: CGFloat = 86
    private let revokeOffsetY: CGFloat = 16

    var body: some View {
        ZStack {
            watermarkIcon(
                systemName: "qrcode",
                color: SettingsExtensionPairingStyle.generateWatermarkColor,
                alignment: .bottomLeading,
                offsetX: generateOffsetX,
                offsetY: generateOffsetY
            )

            watermarkIcon(
                systemName: "xmark.circle.fill",
                color: SettingsExtensionPairingStyle.revokeWatermarkColor,
                alignment: .bottomTrailing,
                offsetX: revokeOffsetX,
                offsetY: revokeOffsetY
            )
        }
    }

    private func watermarkIcon(
        systemName: String,
        color: Color,
        alignment: Alignment,
        offsetX: CGFloat,
        offsetY: CGFloat
    ) -> some View {
        Image(systemName: systemName)
            .font(.system(size: watermarkSize, weight: .thin))
            .foregroundStyle(color.opacity(0.34))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .offset(x: offsetX, y: offsetY)
    }
}

struct SettingsExtensionPairingPicker: View {
    let onSelectGenerate: () -> Void
    let onSelectRevoke: () -> Void

    var body: some View {
        HStack {
            SettingsDualActionIconButton(
                systemImage: "qrcode",
                accentColor: SettingsExtensionPairingStyle.generateIconColor,
                accessibilityLabel: "Generate pairing code",
                action: onSelectGenerate
            )

            Spacer(minLength: 0)

            SettingsDualActionIconButton(
                systemImage: "xmark.circle.fill",
                accentColor: SettingsExtensionPairingStyle.revokeIconColor,
                accessibilityLabel: "Revoke pairings",
                action: onSelectRevoke
            )
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: SettingsDualActionIconButtonStyle.tapTargetSize, alignment: .center)
        .accessibilityElement(children: .contain)
    }
}

struct SettingsExtensionPairingFlipCard: View {
    @EnvironmentObject private var localAuthService: LocalAuthServiceManager
    @Environment(\.glassPalette) private var palette

    @State private var backMode: SettingsExtensionPairingBackMode?

    private let minHeight = SettingsCardLayout.extensionPairingCardHeight
    private let frontContentHeight = SettingsCardLayout.extensionPairingFrontContentHeight
    private let infoDescription = """
    Generate Pairing Code — create a short-lived code your browser extension uses to pair with DynamicKey on this Mac. Copy the code into the extension when prompted.

    Revoke Pairings — remove all paired browsers at once. You will need to generate a new code and pair each browser again.
    """

    private var isFlipped: Bool { backMode != nil }

    private var isActionBack: Bool {
        if case .action = backMode { return true }
        return false
    }

    var body: some View {
        ZStack {
            frontCardFace
                .opacity(isFlipped ? 0 : 1)
                .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                .allowsHitTesting(!isFlipped)

            backCardFace
                .opacity(isFlipped ? 1 : 0)
                .rotation3DEffect(.degrees(isFlipped ? 0 : -180), axis: (x: 0, y: 1, z: 0))
                .allowsHitTesting(isFlipped)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: minHeight, alignment: .topLeading)
        .clipped()
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: backMode)
        .onAppear {
            localAuthService.refreshPairingCodeState()
            localAuthService.refreshPairedClients()
        }
    }

    private var frontCardFace: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow(title: "Extension Pairing", trailingControl: .flipToInfo)

            SettingsExtensionPairingPicker(
                onSelectGenerate: { flipToAction(.generateCode) },
                onSelectRevoke: { flipToAction(.revokePairings) }
            )
            .frame(
                maxWidth: .infinity,
                minHeight: frontContentHeight,
                maxHeight: frontContentHeight,
                alignment: .center
            )
        }
        .padding(GlassTheme.padding)
        .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: minHeight, alignment: .topLeading)
        .background { playCardBackground(tintColor: SettingsExtensionPairingStyle.frontCardTint, showsWatermark: true) }
        .clipShape(RoundedRectangle(cornerRadius: GlassTheme.cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var backCardFace: some View {
        if isActionBack {
            actionBackCardFace
        } else {
            infoBackCardFace
        }
    }

    // Info back — title row + scrollable description.
    private var infoBackCardFace: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow(title: backTitle, trailingControl: .flipToFront)

            ScrollView(.vertical, showsIndicators: true) {
                Text(infoDescription)
                    .font(.caption)
                    .foregroundStyle(palette.onGlassSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, SettingsCardLayout.scrollContentBottomInset)
            }
            .contentMargins(.bottom, SettingsCardLayout.scrollContentBottomInset, for: .scrollContent)
            .frame(height: frontContentHeight, alignment: .topLeading)
            .clipped()
        }
        .padding(GlassTheme.padding)
        .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: minHeight, alignment: .topLeading)
        .background {
            playCardBackground(
                tintColor: SettingsExtensionPairingStyle.cardTint(for: backMode),
                showsWatermark: false
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: GlassTheme.cornerRadius, style: .continuous))
    }

    // Action back — round glass back control, title, and sparkle buttons without scrolling.
    private var actionBackCardFace: some View {
        VStack(alignment: .leading, spacing: 0) {
            GlassCircleIconButton(
                systemImage: "chevron.left",
                accessibilityLabel: "Back to Extension Pairing",
                size: 30,
                iconColor: SettingsExtensionPairingStyle.actionAccentColor(for: backMode),
                action: flipToFront
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(backTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.onGlassPrimary)
                    .frame(maxWidth: .infinity, alignment: .center)

                Group {
                    switch backMode {
                    case .action(.generateCode):
                        generateCodeBackContent
                    case .action(.revokePairings):
                        revokePairingsBackContent
                    default:
                        EmptyView()
                    }
                }
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(GlassTheme.padding)
        .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: minHeight, alignment: .topLeading)
        .background {
            playCardBackground(
                tintColor: SettingsExtensionPairingStyle.cardTint(for: backMode),
                showsWatermark: false
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: GlassTheme.cornerRadius, style: .continuous))
    }

    private var generateCodeBackContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enter this code in your browser extension before it expires.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let code = localAuthService.activePairingCode,
               let expiresAt = localAuthService.pairingCodeExpiresAt {
                pairingCodeBlock(code: code, expiresAt: expiresAt)
            } else {
                Text("No active code yet.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                LiquidGlassSparkleButton(
                    title: localAuthService.activePairingCode == nil ? "Generate Code" : "New Code",
                    sparklePalette: .blue,
                    action: { localAuthService.generatePairingCode() }
                )

                if localAuthService.activePairingCode != nil {
                    LiquidGlassSparkleButton(
                        title: "Copy",
                        sparklePalette: .neutral,
                        titleColor: extensionPairingButtonTrueBlack,
                        action: copyActivePairingCode
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 2)
        }
    }

    private var revokePairingsBackContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Remove every paired browser extension from this Mac. You will need to pair again with a new code.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(localAuthService.pairedClientCount) browser\(localAuthService.pairedClientCount == 1 ? "" : "s") currently paired.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            HStack(spacing: 12) {
                LiquidGlassSparkleButton(
                    title: "Cancel",
                    sparklePalette: .neutral,
                    titleColor: extensionPairingButtonTrueBlack,
                    action: flipToFront
                )

                LiquidGlassSparkleButton(
                    title: "Revoke All",
                    sparklePalette: .destructive,
                    action: {
                        localAuthService.revokeAllPairings()
                        flipToFront()
                    }
                )
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
        }
    }

    private func pairingCodeBlock(code: String, expiresAt: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(code)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .tracking(2)

            PairingCodeExpiryCountdown(expiresAt: expiresAt) {
                localAuthService.refreshPairingCodeState()
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.10))
        }
    }

    private func copyActivePairingCode() {
        guard let code = localAuthService.activePairingCode else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
    }

    private var backTitle: String {
        switch backMode {
        case .info:
            return "Extension Pairing"
        case .action(.generateCode):
            return "Pairing Code"
        case .action(.revokePairings):
            return "Revoke Pairings"
        case nil:
            return "Extension Pairing"
        }
    }

    private enum HeaderTrailingControl {
        case flipToInfo
        case flipToFront
    }

    private func headerRow(title: String, trailingControl: HeaderTrailingControl) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.onGlassPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)

            flipInfoButton
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if trailingControl == .flipToInfo {
                flipToInfo()
            }
        }
    }

    private var flipInfoButton: some View {
        SettingsCardInfoFlipButton(
            isShowingInfo: backMode == .info,
            action: toggleInfoFlip
        )
    }

    private func playCardBackground(tintColor: NSColor?, showsWatermark: Bool) -> some View {
        ZStack {
            LiquidGlassSurface(
                cornerRadius: GlassTheme.cornerRadius,
                tintColor: tintColor
            )

            if showsWatermark {
                SettingsExtensionPairingWatermark()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: GlassTheme.cornerRadius, style: .continuous))
    }

    private func toggleInfoFlip() {
        if backMode == .info {
            flipToFront()
        } else {
            flipToInfo()
        }
    }

    private func flipToInfo() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            backMode = .info
        }
    }

    private func flipToAction(_ action: SettingsExtensionPairingAction) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            backMode = .action(action)
        }

        if action == .generateCode, localAuthService.activePairingCode == nil {
            localAuthService.generatePairingCode()
        }
    }

    private func flipToFront() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            backMode = nil
        }
    }
}
