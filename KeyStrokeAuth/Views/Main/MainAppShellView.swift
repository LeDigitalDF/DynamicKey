// MainAppShellView.swift
// Post-login shell: custom collapsible sidebar, detail pane, glass back navigation, account footer.
// Flow: fixed sidebar column → detail with optional back chrome → settings embedded on gear selection.

import SwiftUI

struct MainAppShellView: View {
    @EnvironmentObject private var localAuthService: LocalAuthServiceManager
    @EnvironmentObject private var appearance: AppAppearanceStore
    @EnvironmentObject private var preferences: AppPreferencesStore
    @EnvironmentObject private var accountProfile: AccountProfileStore
    @Environment(\.glassPalette) private var palette
    @ObservedObject private var safeModeStore = SafeModeStore.shared

    @Binding var selection: MainSidebarSection
    @Binding var passThreshold: Int
    @Binding var settingsSlideOver: SettingsSlideOver?
    @Binding var pendingSecurityAction: SettingsSecurityAction?
    @Binding var pendingSettingsScroll: SettingsScrollAnchor?

    let lastRhythmMatchPercentage: Int
    let siteCredentials: [SiteCredential]
    let allowedOrigins: [String]
    let disabledAllowlistOrigins: [String]
    let trustedSenderDomains: [String]
    let disabledTrustedSenderDomains: [String]
    let auditEvents: [AuditEvent]
    let rhythmProfile: RhythmProfile?
    let lastVerifiedAt: Date?
    let showsReenrollmentReminder: Bool
    var settingsNotice: String?

    let onLogout: () -> Void
    let onPresentChangeMasterPassword: () -> Void
    let onPresentRetrainTypingProfile: () -> Void
    let onPresentBrowserExtensionSettings: () -> Void
    let onResetBiometricData: () -> Void
    let onChangeMasterPasswordComplete: (String) -> Void
    let onRetrainTypingProfileComplete: () -> Void
    let onClearAuditLog: (SecurityActivityPeriod) -> Void
    let onResetLockout: () -> Void
    let onAddSiteCredential: (String, String, String, Bool) -> Void
    let onDeleteSiteCredential: (UUID) -> Void
    let onRegenerateSitePassword: (UUID) -> Void
    let onAddAllowedOrigin: (String) -> Void
    let onRemoveAllowedOrigin: (String) -> Void
    let onToggleAllowlistOrigin: (String, Bool) -> Void
    let onRemoveTrustedSenderDomain: (String) -> Void
    let onToggleTrustedSenderDomain: (String, Bool) -> Void
    let onAddTrustedSenderDomain: (String) -> Void

    @State private var isSidebarCollapsed = false
    @State private var homeSlideOverSection: MainSidebarSection? = nil
    @State private var showLockConfirm = false

    @ObservedObject private var leakPeekIdentity = LeakPeekIdentityStore.shared

    private var sidebarWidth: CGFloat {
        isSidebarCollapsed ? 72 : 248
    }

    // Corner radius for the selected-row Liquid Glass container (tighter than the standard 20 so it
    // reads as a row highlight rather than a button).
    private let sidebarSelectionCornerRadius: CGFloat = 12

    // Trailing inset (expanded only) that shortens the selection glass on the right end. Increase to
    // pull the right edge further in; the left edge stays aligned under the icon.
    private let sidebarSelectionTrailingInset: CGFloat = 22

    var body: some View {
        ZStack {
            DynamicKeyDashboardBackground()

            // Dark mode needs an overlaid chrome row (VStack seam shows Color.black).
            // Light mode keeps the original stacked layout (overlay padding causes a visible seam).
            if appearance.colorScheme == .dark {
                darkModeShellLayout
            } else {
                lightModeShellLayout
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if leakPeekIdentity.showsOverlay {
                LeakPeekBreachCheckOverlay(credentials: siteCredentials)
                    .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: leakPeekIdentity.showsOverlay)
        .confirmationDialog(
            safeModeDialogTitle,
            isPresented: $showLockConfirm,
            titleVisibility: .visible
        ) {
            if safeModeStore.isActive {
                Button("Turn Off Safe Mode") {
                    safeModeStore.deactivate()
                }
                Button("Cancel", role: .cancel) {}
            } else {
                Button("Activate Safe Mode", role: .destructive) {
                    safeModeStore.activate()
                }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            Text(safeModeDialogMessage)
        }
    }

    private var safeModeDialogTitle: String {
        safeModeStore.isActive ? "Safe Mode is active" : "Activate Safe Mode?"
    }

    private var safeModeDialogMessage: String {
        if safeModeStore.isActive {
            return "Safe Mode is on for \(safeModeStore.formattedRemainingTime) more. Turn off Safe Mode in the Mac app or browser extension."
        }
        return "Enables Safe Mode for 24 hours on this Mac and in the browser extension. Use when your typing rhythm may not match your profile."
    }

    // MARK: - Shell layout (theme-specific seam avoidance)

    private var topChromeRow: some View {
        MainTopChromeRow(
            sidebarWidth: sidebarWidth,
            showsDetailBack: selection != .home && homeSlideOverSection == nil,
            onToggleSidebar: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSidebarCollapsed.toggle()
                }
            },
            onDetailBack: { selection = .home },
            isSidebarCollapsed: isSidebarCollapsed
        )
    }

    private var sidebarAndDetailRow: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: sidebarWidth)
                .frame(maxHeight: .infinity)

            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
                .clipped()
        }
    }

    private var darkModeShellLayout: some View {
        ZStack(alignment: .top) {
            sidebarAndDetailRow
                .padding(.top, MainChromeLayout.themeControlHeight)

            topChromeRow
        }
    }

    private var lightModeShellLayout: some View {
        VStack(spacing: 0) {
            topChromeRow
            sidebarAndDetailRow
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                ForEach(MainSidebarSection.sidebarItems, id: \.self) { section in
                    sidebarNavButton(section)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            Spacer(minLength: 0)

            accountFooter
                .padding(12)
        }
    }

    private func sidebarNavButton(_ section: MainSidebarSection) -> some View {
        let isSelected = selection == section

        return Button {
            dismissHomeSlideOver()
            selection = section
        } label: {
            HStack(spacing: 10) {
                sidebarIconBadge(
                    section: section,
                    isSelected: isSelected,
                    isCollapsed: isSidebarCollapsed
                )

                if !isSidebarCollapsed {
                    Text(section.title)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? palette.onGlassPrimary : palette.onGlassSecondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, isSidebarCollapsed ? 0 : 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: isSidebarCollapsed ? .center : .leading)
            .background {
                // Selected row sits inside a real Liquid Glass container. It spans the row when
                // expanded and shrinks to a compact rounded glass around the icon when collapsed.
                // Uses a tighter radius than the standard 20 so the row reads as a highlight, not a button.
                // The trailing inset (expanded only) shortens the glass on the right end.
                if isSelected {
                    LiquidGlassSurface(cornerRadius: sidebarSelectionCornerRadius)
                        .padding(.trailing, isSidebarCollapsed ? 0 : sidebarSelectionTrailingInset)
                        .allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(.plain)
        .help(section.title)
    }

    // Colored icon tile; collapsed selection uses glow instead of a highlight bar.
    private func sidebarIconBadge(
        section: MainSidebarSection,
        isSelected: Bool,
        isCollapsed: Bool
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(section.accentColor.opacity(isSelected ? 1.0 : 0.88))
                .frame(width: 28, height: 28)

            Image(systemName: section.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 28, height: 28)
        .shadow(
            color: isCollapsed && isSelected ? section.accentColor.opacity(0.75) : .clear,
            radius: 5,
            x: 0,
            y: 0
        )
        .shadow(
            color: isCollapsed && isSelected ? section.accentColor.opacity(0.45) : .clear,
            radius: 11,
            x: 0,
            y: 0
        )
        .accessibilityHidden(true)
    }

    /// Safe Mode — syncs with the browser extension; tap to activate or turn off.
    private var sidebarLockButton: some View {
        Button {
            showLockConfirm = true
        } label: {
            Image(systemName: safeModeStore.isActive ? "lock.shield.fill" : "lock.shield")
                .font(.title3)
                .foregroundStyle(safeModeStore.isActive ? .orange : palette.onGlassSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(safeModeStore.isActive ? "Safe Mode active" : "Safe Mode")
        .help(
            safeModeStore.isActive
                ? "Safe Mode active — \(safeModeStore.formattedRemainingTime) remaining. Tap to turn off."
                : "Activate Safe Mode for 24 hours (Mac app and browser extension)."
        )
    }

    private var accountFooter: some View {
        Group {
            if isSidebarCollapsed {
                VStack(spacing: 12) {
                    AccountAvatarView(size: 30)

                    GlassSettingsIconButton(
                        accessibilityLabel: "Settings",
                        action: { selection = .settings }
                    )
                    .help("Settings")

                    sidebarLockButton

                    GlassIconButton(
                        systemImage: "rectangle.portrait.and.arrow.right",
                        accessibilityLabel: "Log out",
                        action: onLogout
                    )
                    .help("Log out")
                }
                .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 10) {
                    AccountAvatarView(size: 34)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(accountProfile.resolvedDisplayName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text("On this Mac")
                            .font(.caption)
                            .foregroundStyle(palette.onGlassSecondary)
                    }

                    Spacer(minLength: 0)

                    GlassSettingsIconButton(
                        accessibilityLabel: "Settings",
                        action: { selection = .settings }
                    )
                    .help("Settings")

                    sidebarLockButton

                    GlassIconButton(
                        systemImage: "rectangle.portrait.and.arrow.right",
                        accessibilityLabel: "Log out",
                        action: onLogout
                    )
                    .help("Log out")
                }
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .home:
            HomeView(
                lastRhythmMatchPercentage: lastRhythmMatchPercentage,
                passThreshold: passThreshold,
                protectedSiteCount: siteCredentials.count,
                pairedExtensionCount: localAuthService.pairedClientCount,
                pairedExtensionClients: localAuthService.pairedClients,
                isExtensionAPIRunning: localAuthService.isRunning,
                showsReenrollmentReminder: showsReenrollmentReminder,
                auditEvents: auditEvents,
                siteCredentials: siteCredentials,
                onOpenBrowserExtension: onPresentBrowserExtensionSettings,
                onRetrainProfile: onPresentRetrainTypingProfile,
                onOpenLeakPeek: { selection = .leakPeek },
                onOpenSecurityActivity: { selection = .securityActivity }
            )

        case .credentials:
            detailWithBack {
                SiteCredentialsDetailView(
                    credentials: siteCredentials,
                    onAddSiteCredential: onAddSiteCredential,
                    onDeleteSiteCredential: onDeleteSiteCredential
                )
            }

        case .allowlist:
            detailWithBack {
                SiteAllowlistDetailView(
                    allowedOrigins: allowedOrigins,
                    disabledAllowlistOrigins: disabledAllowlistOrigins,
                    trustedSenderDomains: trustedSenderDomains,
                    disabledTrustedSenderDomains: disabledTrustedSenderDomains,
                    onAddAllowedOrigin: onAddAllowedOrigin,
                    onRemoveAllowedOrigin: onRemoveAllowedOrigin,
                    onToggleOriginAllowed: onToggleAllowlistOrigin,
                    onRemoveTrustedSenderDomain: onRemoveTrustedSenderDomain,
                    onToggleTrustedSenderDomain: onToggleTrustedSenderDomain,
                    onAddTrustedSenderDomain: onAddTrustedSenderDomain
                )
            }

        case .securityActivity:
            detailWithBack {
                SecurityActivityDetailView(
                    auditEvents: auditEvents,
                    onClearAuditLog: onClearAuditLog
                )
            }

        case .leakPeek:
            detailWithBack {
                LeakPeekDetailView(credentials: siteCredentials)
            }

        case .extensionPairing, .settings:
            ZStack {
                SettingsView(
                    passThreshold: $passThreshold,
                    rhythmProfile: rhythmProfile,
                    lastVerifiedAt: lastVerifiedAt,
                    showsReenrollmentReminder: showsReenrollmentReminder,
                    settingsNotice: settingsNotice,
                    showsNavigationBack: false,
                    pendingSecurityAction: $pendingSecurityAction,
                    pendingSettingsScroll: $pendingSettingsScroll,
                    onBack: { selection = .home },
                    onChangeMasterPasswordComplete: onChangeMasterPasswordComplete,
                    onRetrainTypingProfileComplete: onRetrainTypingProfileComplete,
                    onResetBiometricData: onResetBiometricData
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                if let slideOver = settingsSlideOver {
                    settingsSlideOverContent(for: slideOver)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: settingsSlideOver)

        }
    }

    // Opens a glass slide-over on Home without changing sidebar selection.
    private func presentHomeSlideOver(_ section: MainSidebarSection) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            homeSlideOverSection = section
        }
    }

    private func dismissHomeSlideOver() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            homeSlideOverSection = nil
        }
    }

    @ViewBuilder
    private func homeSlideOverContent(for section: MainSidebarSection) -> some View {
        switch section {
        case .credentials:
            SiteCredentialsDetailView(
                credentials: siteCredentials,
                isSlideOver: true,
                onAddSiteCredential: onAddSiteCredential,
                onDeleteSiteCredential: onDeleteSiteCredential
            )
        case .allowlist:
            SiteAllowlistDetailView(
                allowedOrigins: allowedOrigins,
                disabledAllowlistOrigins: disabledAllowlistOrigins,
                trustedSenderDomains: trustedSenderDomains,
                disabledTrustedSenderDomains: disabledTrustedSenderDomains,
                isSlideOver: true,
                onAddAllowedOrigin: onAddAllowedOrigin,
                onRemoveAllowedOrigin: onRemoveAllowedOrigin,
                onToggleOriginAllowed: onToggleAllowlistOrigin,
                onRemoveTrustedSenderDomain: onRemoveTrustedSenderDomain,
                onToggleTrustedSenderDomain: onToggleTrustedSenderDomain,
                onAddTrustedSenderDomain: onAddTrustedSenderDomain
            )
        default:
            EmptyView()
        }
    }

    private func dismissSettingsSlideOver() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            settingsSlideOver = nil
        }
    }

    @ViewBuilder
    private func settingsSlideOverContent(for slideOver: SettingsSlideOver) -> some View {
        switch slideOver {
        case .changeMasterPassword:
            SettingsDetailSlideOver(
                title: "Change Master Password",
                systemImage: "key.fill",
                accentColor: MainSidebarSection.settings.accentColor,
                onDismiss: dismissSettingsSlideOver
            ) {
                ChangeMasterPasswordFlowView(
                    passThreshold: passThreshold,
                    onComplete: onChangeMasterPasswordComplete,
                    onCancel: dismissSettingsSlideOver
                )
            }
        }
    }

    // Detail sections use the shared top chrome row for back navigation.
    private func detailWithBack<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
