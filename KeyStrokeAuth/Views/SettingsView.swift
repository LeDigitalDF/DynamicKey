// SettingsView.swift
// Account profile and flippable widget-card settings grid.
// Flow: header → profile cover → flip cards (front = controls, back = description).

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var preferences: AppPreferencesStore
    @EnvironmentObject private var localAuthService: LocalAuthServiceManager
    @Environment(\.glassPalette) private var palette
    @ObservedObject private var launchAtLoginService = LaunchAtLoginService.shared
    @ObservedObject private var adaptiveRhythm = AdaptiveRhythmStore.shared
    @AppStorage(AppPreferencesStore.showMenuBarIconDefaultsKey) private var showMenuBarIcon = true

    @Binding var passThreshold: Int
    let rhythmProfile: RhythmProfile?
    let lastVerifiedAt: Date?
    let showsReenrollmentReminder: Bool
    var settingsNotice: String? = nil
    var settingsBackTitle: String = "Back to Home"
    var showsNavigationBack: Bool = true
    @Binding var pendingSecurityAction: SettingsSecurityAction?
    @Binding var pendingSettingsScroll: SettingsScrollAnchor?
    let onBack: () -> Void
    let onChangeMasterPasswordComplete: (String) -> Void
    let onRetrainTypingProfileComplete: () -> Void
    let onResetBiometricData: () -> Void

    @State private var showsResetBiometricConfirmation = false
    @ObservedObject private var safeMode = SafeModeStore.shared
    @State private var isTrustedKeyboardsPlusHovered = false
    @State private var isTrustedNetworksPlusHovered = false
    @State private var isResetDataWatermarkHovered = false
    @State private var isSafeModeWatermarkHovered = false

    var body: some View {
        ZStack {
            DetailPaneSectionIconWatermarkBackground(section: .settings)

            settingsScrollContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            localAuthService.refreshPairedClients()
            localAuthService.refreshPairingCodeState()
        }
        .onChange(of: passThreshold) { _, newValue in
            RhythmSettings.passThreshold = newValue
        }
        .alert(
            "Reset Biometric Data?",
            isPresented: $showsResetBiometricConfirmation
        ) {
            Button("Reset Biometric Data", role: .destructive, action: onResetBiometricData)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes your typing rhythm profile. You will need to train the app again.")
        }
    }

    private var settingsScrollContent: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: GlassTheme.sectionSpacing) {
                    if showsNavigationBack {
                        GlassBackButton(title: settingsBackTitle, action: onBack)
                    }

                    MainDetailSectionHeader(
                        section: .settings,
                        subtitle: "Account, security, and preferences.",
                        showsSectionIcon: false
                    )

                    if showsReenrollmentReminder {
                        GlassInfoBanner(
                            kind: .warning,
                            message: "Typing profile is over \(EnrollmentConfig.reenrollmentReminderDays) days old — consider retraining."
                        )
                    }

                    if let settingsNotice {
                        GlassInfoBanner(kind: .success, message: settingsNotice)
                    }

                    SettingsProfileHeaderView()

                    accountCard

                    rhythmLearningCard

                    settingsCardRow {
                        rhythmThresholdCard
                    } right: {
                        safeModeCard
                    }

                    settingsCardRow(minHeight: SettingsCardLayout.securityActionsCardHeight) {
                        securityActionsCard
                    } right: {
                        typingProfileCard
                    }
                    .id(SettingsScrollAnchor.securityActions)

                    settingsCardRow(minHeight: SettingsCardLayout.extensionPairingCardHeight) {
                        extensionStatusCard
                    } right: {
                        extensionPairingCard
                    }
                    .id(SettingsScrollAnchor.browserExtension)

                    settingsCardRow(minHeight: SettingsCardLayout.expandedCardHeight) {
                        trustedKeyboardsCard
                    } right: {
                        trustedNetworksCard
                    }

                    settingsCardRow {
                        launchAtLoginCard
                    } right: {
                        menuBarIconCard
                    }

                    dailySummaryAICard

                    settingsCardRow {
                        privacyCard
                    } right: {
                        resetDataCard
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 10)
                .padding(.bottom, 24)
                .frame(maxWidth: SettingsCardLayout.settingsContentMaxWidth, alignment: .center)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .onChange(of: pendingSecurityAction) { _, action in
                guard action != nil else { return }
                scrollToAnchor(.securityActions, using: scrollProxy)
            }
            .onChange(of: pendingSettingsScroll) { _, anchor in
                guard let anchor else { return }
                scrollToAnchor(anchor, using: scrollProxy)
                pendingSettingsScroll = nil
            }
            .onAppear {
                if pendingSecurityAction != nil {
                    scrollToAnchor(.securityActions, using: scrollProxy)
                } else if let anchor = pendingSettingsScroll {
                    scrollToAnchor(anchor, using: scrollProxy)
                    pendingSettingsScroll = nil
                }
            }
        }
    }

    private func scrollToAnchor(_ anchor: SettingsScrollAnchor, using proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeInOut(duration: 0.4)) {
                proxy.scrollTo(anchor, anchor: .center)
            }
        }
    }

    private var accountCard: some View {
        SettingsFlipWidgetCard(
            title: "Account",
            backDescription: "Your display name syncs across Macs through iCloud when you are signed in. Your master password, typing rhythm, and vault data always stay on this Mac — nothing secret is uploaded."
        ) {
            SettingsAccountCardContent()
        }
    }

    private func settingsCardRow<Left: View, Right: View>(
        minHeight: CGFloat = SettingsCardLayout.standardCardHeight,
        @ViewBuilder left: () -> Left,
        @ViewBuilder right: () -> Right
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            left()
                .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: minHeight, alignment: .topLeading)
            right()
                .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: minHeight, alignment: .topLeading)
        }
    }

    // Continuous-learning toggle plus an advisory (never automatic) suggestion to raise the threshold,
    // placed directly above the threshold slider. The suggestion only appears when recent genuine
    // sign-ins clear the current threshold comfortably.
    private var rhythmLearningCard: some View {
        let suggestion = adaptiveRhythm.suggestedThreshold(currentThreshold: passThreshold)
        let showsSuggestion = suggestion != nil

        return SettingsFlipWidgetCard(
            title: "Learn my typing rhythm",
            backDescription: "When enabled, each successful master-password sign-in that passes your rhythm threshold refines your profile on this Mac. DynamicKey never lowers your threshold automatically — it only learns to recognize you more accurately. Threshold suggestions appear when recent sign-ins consistently score well above your current match level; raising the slider is always your choice.",
            minHeight: SettingsCardLayout.rhythmLearningCardHeight(showsSuggestion: showsSuggestion),
            frontContentHeight: SettingsCardLayout.rhythmLearningFrontContentHeight(showsSuggestion: showsSuggestion),
            frontTintColor: showsSuggestion ? SettingsRhythmAdviceStyle.cardTint : nil,
            frontOverlay: {
                if let suggestion {
                    SettingsRhythmAdviceScoreWatermark(score: suggestion)
                } else {
                    EmptyView()
                }
            }
        ) {
            SettingsRhythmLearningCardContent(
                continuousLearningEnabled: $preferences.continuousLearningEnabled,
                passThreshold: passThreshold
            )
        }
    }

    private var rhythmThresholdCard: some View {
        let thresholdColor = SettingsRhythmThresholdStyle.color(for: passThreshold)

        return SettingsFlipWidgetCard(
            title: "Match Threshold",
            backDescription: "Sets how closely your typing rhythm must match your enrolled profile to unlock. Lower values are easier; higher values are stricter."
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(passThreshold)%")
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(thresholdColor)

                    Spacer(minLength: 0)

                    Text(passThreshold <= 60 ? "Easier" : (passThreshold >= 80 ? "Stricter" : "Balanced"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(thresholdColor.opacity(0.85))
                }

                Slider(
                    value: Binding(
                        get: { Double(passThreshold) },
                        set: { passThreshold = Int($0.rounded()) }
                    ),
                    in: Double(RhythmSettings.minimumThreshold)...Double(RhythmSettings.maximumThreshold),
                    step: 1
                )
                .tint(thresholdColor)

                HStack {
                    Text("\(RhythmSettings.minimumThreshold)%")
                    Spacer()
                    Text("\(RhythmSettings.maximumThreshold)%")
                }
                .font(.caption2)
                .foregroundStyle(palette.onGlassSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var safeModeCard: some View {
        SettingsFlipWidgetCard(
            title: "Safe Mode",
            backDescription: "Safe Mode is a temporary 24-hour option for when your typing rhythm may not match your profile — for example after a hand or arm injury.\n\nWhile active, the browser extension accepts Touch ID as if you had unlocked with your master password and rhythm. It turns off automatically after 24 hours, or tap Turn Off on the card front to end it immediately.\n\nLogging into the Mac app with rhythm or Touch ID is separate and is not controlled by this card.",
            frontTintColor: safeMode.isActive
                ? (SettingsPlusActionStyle.activeCardTint(for: .safeMode) ?? SettingsPlusActionStyle.cardTint(for: .safeMode))
                : SettingsPlusActionStyle.cardTint(for: .safeMode),
            usesScrollableBackDescription: true,
            frontOverlay: {
                SettingsPlusActionWatermark(
                    style: .safeMode,
                    isHovered: isSafeModeWatermarkHovered,
                    isEmphasized: safeMode.isActive
                )
            }
        ) {
            SettingsSafeModeCardContent(isWatermarkHovered: $isSafeModeWatermarkHovered)
        }
        .animation(.easeInOut(duration: 0.28), value: safeMode.isActive)
    }

    private var securityActionsCard: some View {
        SettingsSecurityActionsFlipCard(
            passThreshold: passThreshold,
            pendingAction: $pendingSecurityAction,
            onChangeMasterPasswordComplete: onChangeMasterPasswordComplete,
            onRetrainTypingProfileComplete: onRetrainTypingProfileComplete
        )
    }

    private var typingProfileCard: some View {
        SettingsFlipWidgetCard(
            title: "Typing Profile",
            backDescription: "A quick look at your enrolled rhythm — how long you hold keys, gaps between them, overall profile strength, and when you last verified successfully.",
            minHeight: SettingsCardLayout.securityActionsCardHeight,
            frontContentHeight: SettingsCardLayout.securityActionsFrontContentHeight
        ) {
            if let rhythmProfile {
                VStack(alignment: .leading, spacing: 6) {
                    profileStatRow(
                        label: "Average Dwell Time",
                        value: "\(rhythmProfile.averageDwellMilliseconds)ms"
                    )
                    profileStatRow(
                        label: "Average Flight Time",
                        value: "\(rhythmProfile.averageFlightMilliseconds)ms"
                    )
                    profileStatRow(
                        label: "Profile Strength",
                        value: rhythmProfile.profileStrength.label,
                        valueColor: strengthColor(for: rhythmProfile.profileStrength)
                    )
                    profileStatRow(
                        label: "Last Verified",
                        value: lastVerifiedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Not yet"
                    )
                }
            } else {
                Text("No profile enrolled yet.")
                    .font(.caption)
                    .foregroundStyle(palette.onGlassSecondary)
            }
        }
    }

    private func strengthColor(for strength: TypingProfileStrength) -> Color {
        switch strength {
        case .high: return .green
        case .medium: return .orange
        case .low: return .red
        }
    }

    private func profileStatRow(label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(palette.onGlassSecondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(valueColor)
        }
    }

    private var extensionStatusCard: some View {
        SettingsFlipWidgetCard(
            title: "Browser Extension",
            backDescription: "Shows which browsers are paired with DynamicKey on this Mac and whether the local extension API is running for verify and autofill.",
            minHeight: SettingsCardLayout.extensionPairingCardHeight,
            frontContentHeight: SettingsCardLayout.extensionPairingFrontContentHeight
        ) {
            BrowserExtensionStatusCardContent()
        }
    }

    private var extensionPairingCard: some View {
        SettingsExtensionPairingFlipCard()
    }

    private var trustedKeyboardsCard: some View {
        SettingsFlipWidgetCard(
            title: "Trusted Keyboards",
            backDescription: "Only rhythm captured from approved keyboards is accepted when this list is not empty. When keyboard and Wi-Fi are both trusted, a future cloud account step can be skipped.\n\nIf macOS cannot identify your physical keyboard, DynamicKey uses your input layout (for example Norwegian) as the device ID.",
            minHeight: SettingsCardLayout.expandedCardHeight,
            frontContentHeight: SettingsCardLayout.expandedFrontContentHeight,
            frontTintColor: SettingsPlusActionStyle.cardTint,
            frontOverlay: {
                SettingsPlusActionWatermark(isHovered: isTrustedKeyboardsPlusHovered)
            }
        ) {
            TrustedKeyboardsSettingsContent(isPlusHovered: $isTrustedKeyboardsPlusHovered)
        }
    }

    private var trustedNetworksCard: some View {
        SettingsFlipWidgetCard(
            title: "Trusted Networks",
            backDescription: "Restrict unlock to Wi-Fi networks you recognize. Leave the list empty to allow any network.",
            minHeight: SettingsCardLayout.expandedCardHeight,
            frontContentHeight: SettingsCardLayout.expandedFrontContentHeight,
            frontTintColor: SettingsPlusActionStyle.cardTint,
            frontOverlay: {
                SettingsPlusActionWatermark(isHovered: isTrustedNetworksPlusHovered)
            }
        ) {
            TrustedNetworksSettingsContent(isPlusHovered: $isTrustedNetworksPlusHovered)
        }
    }

    private var launchAtLoginCard: some View {
        SettingsFlipWidgetCard(
            title: "Launch at Login",
            backDescription: "Keeps DynamicKey available in the menu bar automatically when you sign in to this Mac."
        ) {
            VStack(alignment: .leading, spacing: 6) {
                compactToggleRow(
                    detail: "Open DynamicKey when you sign in.",
                    isOn: $preferences.launchAtLoginEnabled
                )

                if let error = launchAtLoginService.lastErrorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var menuBarIconCard: some View {
        SettingsFlipWidgetCard(
            title: "Menu Bar Icon",
            backDescription: "Show or hide the DynamicKey icon in the macOS menu bar."
        ) {
            compactToggleRow(
                detail: "Show the icon in the menu bar.",
                isOn: $showMenuBarIcon
            )
        }
    }

    private var dailySummaryAICard: some View {
        SettingsFlipWidgetCard(
            title: "AI — Daily Summary",
            backDescription: "Local AI builds the Daily Summary from counts on your Mac. Muse AI sends only a short count summary to Meta’s muse-spark-1.3 model — never emails, site names, passwords, or audit log text. Your Meta API key stays in the Keychain.",
            minHeight: SettingsCardLayout.dailySummaryAICardHeight,
            frontContentHeight: SettingsCardLayout.dailySummaryAIFrontContentHeight
        ) {
            SettingsDailySummaryAIContent()
        }
    }

    private var privacyCard: some View {
        SettingsFlipWidgetCard(
            title: "Privacy",
            backDescription: "DynamicKey keeps your master password, typing rhythm profile, and site credentials on this Mac only. Nothing is uploaded to the cloud."
        ) {
            Label {
                Text("Master password, rhythm profile, and credentials stay on this Mac.")
                    .font(.caption)
                    .foregroundStyle(palette.onGlassSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lock.shield.fill")
                    .font(.caption)
                    .foregroundStyle(palette.onGlassSecondary)
            }
            .labelStyle(.titleAndIcon)
        }
    }

    private var resetDataCard: some View {
        SettingsFlipWidgetCard(
            title: "Reset Data",
            backDescription: "Permanently removes your rhythm profile, master password, and saved credentials from this Mac. You will return to the initial setup screen.",
            frontTintColor: SettingsPlusActionStyle.cardTint(for: .destructive),
            frontOverlay: {
                SettingsPlusActionWatermark(style: .destructive, isHovered: isResetDataWatermarkHovered)
            }
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Removes your rhythm profile, master password, and site credentials. You will return to setup.")
                    .font(.caption)
                    .foregroundStyle(palette.onGlassSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: SettingsCardLayout.frontContentHeight,
                maxHeight: SettingsCardLayout.frontContentHeight,
                alignment: .topLeading
            )
            .overlay(alignment: .bottom) {
                SettingsSingleActionPlayActionStrip(
                    isWatermarkHovered: $isResetDataWatermarkHovered,
                    accessibilityLabel: "Reset Data",
                    action: { showsResetBiometricConfirmation = true }
                )
            }
        }
    }

    private func compactToggleRow(detail: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(detail)
                .font(.caption)
                .foregroundStyle(palette.onGlassSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}
