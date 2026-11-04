// SettingsSecurityActionsFlipCard.swift
// Dual-action settings play-card — front picks Key or Pulse; info flip explains both; action flip runs a scrollable flow.
// Flow: tinted front with watermarks → flip icon (info) or icon tap (action) → fixed-height back with scroll → return to front.

import AppKit
import SwiftUI

enum SettingsSecurityAction: Equatable {
    case changePassword
    case retrainProfile
}

enum SettingsSecurityActionsBackMode: Equatable {
    case info
    case action(SettingsSecurityAction)
}

enum SettingsSecurityActionsStyle {
    static let frontCardTint = NSColor(calibratedRed: 0.14, green: 0.18, blue: 0.38, alpha: 0.34)
    static let keyCardTint = NSColor(calibratedRed: 0.58, green: 0.28, blue: 0.08, alpha: 0.36)
    static let pulseCardTint = NSColor(calibratedRed: 0.10, green: 0.28, blue: 0.62, alpha: 0.36)

    static let keyWatermarkColor = Color(red: 1.0, green: 0.72, blue: 0.36)
    static let pulseWatermarkColor = Color(red: 0.48, green: 0.78, blue: 1.0)

    static let keyIconColor = Color(red: 1.0, green: 0.62, blue: 0.18)
    static let pulseIconColor = Color(red: 0.28, green: 0.62, blue: 1.0)

    static func cardTint(for backMode: SettingsSecurityActionsBackMode?) -> NSColor {
        switch backMode {
        case .action(.changePassword):
            return keyCardTint
        case .action(.retrainProfile):
            return pulseCardTint
        case .info, nil:
            return frontCardTint
        }
    }
}

struct SettingsSecurityActionsWatermark: View {
    var body: some View {
        ZStack {
            watermarkIcon(
                systemName: "key.fill",
                color: SettingsSecurityActionsStyle.keyWatermarkColor,
                alignment: .bottomLeading,
                offsetX: -58,
                offsetY: 14
            )

            watermarkIcon(
                systemName: "waveform.path.ecg",
                color: SettingsSecurityActionsStyle.pulseWatermarkColor,
                alignment: .bottomTrailing,
                offsetX: 58,
                offsetY: 14
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
            .font(.system(size: 178, weight: .thin))
            .foregroundStyle(color.opacity(0.34))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .offset(x: offsetX, y: offsetY)
    }
}

struct SettingsSecurityActionsPicker: View {
    private enum Layout {
        /// Resting icon size before hover (Security Actions key + pulse only).
        static let foregroundIconSize: CGFloat = 56
        static let tapTargetSize: CGFloat = 76
        static let horizontalInset: CGFloat = 8
    }

    let onSelectChangePassword: () -> Void
    let onSelectRetrainProfile: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let centerY = proxy.size.height * 0.5
            let keyCenterX = Layout.tapTargetSize * 0.5
            let pulseCenterX = proxy.size.width - (Layout.tapTargetSize * 0.5)

            ZStack {
                SettingsDualActionIconButton(
                    systemImage: "key.fill",
                    accentColor: SettingsSecurityActionsStyle.keyIconColor,
                    accessibilityLabel: "Change Master Password",
                    action: onSelectChangePassword,
                    foregroundIconSize: Layout.foregroundIconSize,
                    tapTargetSize: Layout.tapTargetSize
                )
                .position(x: keyCenterX, y: centerY)

                SettingsDualActionIconButton(
                    systemImage: "waveform.path.ecg",
                    accentColor: SettingsSecurityActionsStyle.pulseIconColor,
                    accessibilityLabel: "Retrain Typing Profile",
                    action: onSelectRetrainProfile,
                    foregroundIconSize: Layout.foregroundIconSize,
                    tapTargetSize: Layout.tapTargetSize
                )
                .position(x: pulseCenterX, y: centerY)
            }
        }
        .padding(.horizontal, Layout.horizontalInset)
        .accessibilityElement(children: .contain)
    }
}

struct SettingsSecurityActionsFlipCard: View {
    @Environment(\.glassPalette) private var palette

    let passThreshold: Int
    @Binding var pendingAction: SettingsSecurityAction?
    let onChangeMasterPasswordComplete: (String) -> Void
    let onRetrainTypingProfileComplete: () -> Void

    @State private var backMode: SettingsSecurityActionsBackMode?
    @State private var flowResetToken = UUID()

    private let minHeight = SettingsCardLayout.securityActionsCardHeight
    private let infoDescription = """
    Change Master Password — verify your current password and typing rhythm, choose a new master password, then train your rhythm on the new password. Saved website credentials stay on this Mac.

    Retrain Typing Profile — replace your typing rhythm fingerprint with fresh measurements from sentence warm-up and password samples. Your master password and saved credentials stay the same.
    """

    private var isFlipped: Bool { backMode != nil }

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
        .onChange(of: pendingAction) { _, action in
            consumePendingAction(action)
        }
        .onAppear {
            consumePendingAction(pendingAction)
        }
    }

    private func consumePendingAction(_ action: SettingsSecurityAction?) {
        guard let action else { return }
        flipToAction(action)
        pendingAction = nil
    }

    private var frontCardFace: some View {
        ZStack {
            SettingsSecurityActionsPicker(
                onSelectChangePassword: { flipToAction(.changePassword) },
                onSelectRetrainProfile: { flipToAction(.retrainProfile) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 0) {
                headerRow(title: "Security Actions", trailingControl: .flipToInfo)
                Spacer(minLength: 0)
            }
        }
        .padding(GlassTheme.padding)
        .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: minHeight)
        .background { playCardBackground(tintColor: SettingsSecurityActionsStyle.frontCardTint, showsWatermark: true) }
        .clipShape(RoundedRectangle(cornerRadius: GlassTheme.cornerRadius, style: .continuous))
    }

    private var backCardFace: some View {
        Group {
            if case .action = backMode {
                actionBackCardFace
            } else {
                infoBackCardFace
            }
        }
    }

    private var infoBackCardFace: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow(
                title: backTitle,
                trailingControl: .flipToFront
            )

            scrollableBackContent
                .frame(height: SettingsCardLayout.securityActionsKeyBackContentHeight, alignment: .topLeading)
                .clipped()
        }
        .padding(GlassTheme.padding)
        .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: minHeight, alignment: .topLeading)
        .background {
            playCardBackground(
                tintColor: SettingsSecurityActionsStyle.cardTint(for: backMode),
                showsWatermark: false
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: GlassTheme.cornerRadius, style: .continuous))
    }

    private var actionBackCardFace: some View {
        VStack(alignment: .leading, spacing: 0) {
            GlassCircleIconButton(
                systemImage: "chevron.left",
                accessibilityLabel: "Back to Security Actions",
                size: 30,
                iconColor: actionAccentColor,
                action: flipToFront
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(backTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.onGlassPrimary)
                    .frame(maxWidth: .infinity, alignment: .center)

                actionBackContent
                    .frame(height: actionBackContentHeight, alignment: .topLeading)
                    .clipped()
            }
            .padding(.top, 8)
        }
        .padding(GlassTheme.padding)
        .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: minHeight, alignment: .topLeading)
        .background {
            playCardBackground(
                tintColor: SettingsSecurityActionsStyle.cardTint(for: backMode),
                showsWatermark: false
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: GlassTheme.cornerRadius, style: .continuous))
    }

    private var actionAccentColor: Color {
        switch backMode {
        case .action(.changePassword):
            return SettingsSecurityActionsStyle.keyIconColor
        case .action(.retrainProfile):
            return SettingsSecurityActionsStyle.pulseIconColor
        default:
            return .white.opacity(0.72)
        }
    }

    private var actionBackContentHeight: CGFloat {
        switch backMode {
        case .action(.retrainProfile):
            return SettingsCardLayout.securityActionsPulseBackContentHeight
        default:
            return SettingsCardLayout.securityActionsKeyBackContentHeight
        }
    }

    @ViewBuilder
    private var actionBackContent: some View {
        switch backMode {
        case .action(.changePassword):
            ChangeMasterPasswordFlowView(
                passThreshold: passThreshold,
                isCompactCard: true,
                onComplete: { notice in
                    flipToFront()
                    onChangeMasterPasswordComplete(notice)
                },
                onCancel: flipToFront
            )
            .id(flowResetToken)
        case .action(.retrainProfile):
            ScrollView(.vertical, showsIndicators: true) {
                RetrainTypingProfileFlowView(
                    isCompactCard: true,
                    onComplete: {
                        flipToFront()
                        onRetrainTypingProfileComplete()
                    },
                    onCancel: flipToFront
                )
                .id(flowResetToken)
                .padding(.bottom, SettingsCardLayout.scrollContentBottomInset)
            }
            .contentMargins(.bottom, SettingsCardLayout.scrollContentBottomInset, for: .scrollContent)
        default:
            EmptyView()
        }
    }

    private var scrollableBackContent: some View {
        ScrollView(.vertical, showsIndicators: true) {
            Group {
                switch backMode {
                case .info:
                    Text(infoDescription)
                        .font(.caption)
                        .foregroundStyle(palette.onGlassSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                default:
                    EmptyView()
                }
            }
            .padding(.bottom, SettingsCardLayout.scrollContentBottomInset)
        }
        .contentMargins(.bottom, SettingsCardLayout.scrollContentBottomInset, for: .scrollContent)
    }

    private var backTitle: String {
        switch backMode {
        case .info:
            return "Security Actions"
        case .action(.changePassword):
            return "Change Master Password"
        case .action(.retrainProfile):
            return "Retrain Typing Profile"
        case nil:
            return "Security Actions"
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

            switch trailingControl {
            case .flipToInfo:
                flipInfoButton
            case .flipToFront:
                flipInfoButton
            }
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
                SettingsSecurityActionsWatermark()
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
        flowResetToken = UUID()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            backMode = .info
        }
    }

    private func flipToAction(_ action: SettingsSecurityAction) {
        flowResetToken = UUID()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            backMode = .action(action)
        }
    }

    private func flipToFront() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            backMode = nil
        }
        flowResetToken = UUID()
    }
}
