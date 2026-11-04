// ContentView.swift
// Coordinates enrollment, persistence, and login verification across app phases.

import SwiftUI
import Combine
import AppKit

struct ContentView: View {
    @EnvironmentObject private var appStatus: AppStatusModel
    @EnvironmentObject private var localAuthService: LocalAuthServiceManager
    @EnvironmentObject private var appearance: AppAppearanceStore
    @EnvironmentObject private var preferences: AppPreferencesStore
    @Environment(\.openWindow) private var openWindow

    @State private var currentPhase: AppPhase = .landing
    @State private var hasResolvedLaunchPhase = false

    @State private var masterPassword = ""
    @State private var repeatPassword = ""
    @State private var passwordValidationMessage: String?

    @State private var loginAttemptText = ""
    @State private var loginData: [KeystrokeData] = []
    @State private var matchPercentage = 0
    @State private var denialReason: DenialReason?

    @State private var pendingRhythmProfile: RhythmProfile?
    @State private var passwordEnrollmentSamples: [[KeystrokeData]] = []
    @State private var currentSampleData: [KeystrokeData] = []
    @State private var currentSampleText = ""
    @State private var currentSampleIndex = 0
    @State private var enrollmentHasError = false
    @State private var enrollmentErrorMessage: String?

    @State private var trainingSentences: [String] = []
    @State private var currentSentenceIndex = 0
    @State private var sentenceTypedText = ""
    @State private var sentenceHasError = false

    @State private var saveErrorMessage: String?
    @State private var isEnrollmentTest = false
    @State private var isReenrollment = false
    @State private var isChangingMasterPassword = false
    @State private var changePasswordCurrent = ""
    @State private var changePasswordVerifyData: [KeystrokeData] = []
    @State private var changePasswordVerifiedCurrent = ""
    @State private var changePasswordVerifyError: String?
    @State private var settingsNotice: String?
    @State private var passThreshold = RhythmSettings.passThreshold
    @State private var lockoutClock = Date()
    @State private var auditEvents: [AuditEvent] = []
    @State private var landingMessage: String?
    @State private var siteCredentials: [SiteCredential] = []
    @State private var allowedOrigins: [String] = []
    @State private var disabledAllowlistOrigins: [String] = []
    @State private var trustedSenderDomains: [String] = []
    @State private var disabledTrustedSenderDomains: [String] = []
    @State private var mainSidebarSelection: MainSidebarSection = .home
    @State private var settingsSlideOver: SettingsSlideOver?
    @State private var pendingSecurityAction: SettingsSecurityAction?
    @State private var pendingSettingsScroll: SettingsScrollAnchor?
    @State private var lastLoginMatchPercentage: Int = 0
    @State private var loginContextMessage: String?
    @State private var isTouchIDInProgress = false
    @Environment(\.scenePhase) private var scenePhase

    private let profileStore = ProfileStore.shared
    @ObservedObject private var trustContext = TrustContextStore.shared

    var body: some View {
        Group {
            if currentPhase == .main {
                MainAppShellView(
                    selection: $mainSidebarSelection,
                    passThreshold: $passThreshold,
                    settingsSlideOver: $settingsSlideOver,
                    pendingSecurityAction: $pendingSecurityAction,
                    pendingSettingsScroll: $pendingSettingsScroll,
                    lastRhythmMatchPercentage: lastLoginMatchPercentage,
                    siteCredentials: siteCredentials,
                    allowedOrigins: allowedOrigins,
                    disabledAllowlistOrigins: disabledAllowlistOrigins,
                    trustedSenderDomains: trustedSenderDomains,
                    disabledTrustedSenderDomains: disabledTrustedSenderDomains,
                    auditEvents: auditEvents,
                    rhythmProfile: profileStore.loadProfile()?.rhythmProfile,
                    lastVerifiedAt: HomeDashboardModel.lastLoginDate(from: auditEvents),
                    showsReenrollmentReminder: shouldShowReenrollmentReminder,
                    settingsNotice: settingsNotice,
                    onLogout: logOutToLanding,
                    onPresentChangeMasterPassword: presentChangeMasterPassword,
                    onPresentRetrainTypingProfile: presentRetrainTypingProfile,
                    onPresentBrowserExtensionSettings: presentBrowserExtensionSettings,
                    onResetBiometricData: resetBiometricData,
                    onChangeMasterPasswordComplete: completeChangeMasterPassword,
                    onRetrainTypingProfileComplete: completeRetrainTypingProfile,
                    onClearAuditLog: clearAuditLog,
                    onResetLockout: { resetLockoutForTesting() },
                    onAddSiteCredential: { origin, username, password, isGenerated in
                        addSiteCredential(
                            origin: origin,
                            username: username,
                            password: password,
                            isGenerated: isGenerated
                        )
                    },
                    onDeleteSiteCredential: deleteSiteCredential,
                    onRegenerateSitePassword: regenerateSitePassword,
                    onAddAllowedOrigin: addAllowedOrigin,
                    onRemoveAllowedOrigin: removeAllowedOrigin,
                    onToggleAllowlistOrigin: toggleAllowlistOrigin,
                    onRemoveTrustedSenderDomain: removeTrustedSenderDomain,
                    onToggleTrustedSenderDomain: toggleTrustedSenderDomain,
                    onAddTrustedSenderDomain: addTrustedSenderDomain
                )
                .environmentObject(localAuthService)
            } else {
                authFlowContent
            }
        }
        .frame(
            minWidth: currentPhase == .main ? 920 : 640,
            minHeight: currentPhase == .main ? 640 : 560
        )
        .background {
            MainWindowChromeConfigurator(isLightMode: appearance.theme.resolvedColorScheme == .light)
        }
        .onAppear {
            Task { @MainActor in
                resolveLaunchPhase()
                refreshAuditEvents()
                refreshSiteSettings()
                appStatus.refresh()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            SafeModeStore.shared.refreshExpiryIfNeeded()
            refreshSiteSettings()
            refreshAuditEvents()
            Task { @MainActor in
                await LeakPeekStore.shared.runWeeklyScanIfNeeded(
                    credentials: CredentialStore.shared.credentials()
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .siteCredentialsDidChange)) { _ in
            Task { @MainActor in
                refreshSiteSettings()
                refreshAuditEvents()
                LeakPeekStore.shared.syncCredentialList(CredentialStore.shared.credentials())
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dynamicKeyExtensionOpenRetrain)) { _ in
            NSApp.activate(ignoringOtherApps: true)
            presentRetrainTypingProfile()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dynamicKeyMenuBarOpenMainApp)) { _ in
            NSApp.activate(ignoringOtherApps: true)
            if currentPhase == .main {
                mainSidebarSelection = .home
                pendingSettingsScroll = nil
                pendingSecurityAction = nil
            }
            bringMainWindowForward()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dynamicKeyMenuBarOpenPreferences)) { _ in
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "dynamickey-preferences")
        }
        .onReceive(NotificationCenter.default.publisher(for: .sitePolicyDidChange)) { _ in
            Task { @MainActor in
                refreshSiteSettings()
                refreshAuditEvents()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dynamicShieldPolicyDidChange)) { _ in
            Task { @MainActor in
                refreshSiteSettings()
            }
        }
        .onChange(of: localAuthService.isRunning) { _, _ in
            Task { @MainActor in
                appStatus.refresh()
            }
        }
        .onChange(of: localAuthService.isPausedByUser) { _, _ in
            Task { @MainActor in
                appStatus.refresh()
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            handleLockoutTimerTick(at: date)
        }
        .environment(\.glassPalette, appearance.palette)
        .preferredColorScheme(appearance.colorScheme)
    }

    private var authFlowContent: some View {
        ZStack {
            // Same backdrop as the Home Dashboard — seamless chrome with no title-bar band.
            DynamicKeyDashboardBackground()

            VStack(spacing: 0) {
                // Reserve the traffic-light zone so back buttons and titles never sit underneath.
                Color.clear
                    .frame(height: MainChromeLayout.rowHeight)
                    .accessibilityHidden(true)

                if !hasResolvedLaunchPhase {
                    launchBootstrapContent
                } else if currentPhase == .landing {
                    AuthLandingView(
                        landingMessage: landingMessage,
                        actionTitle: landingActionTitle,
                        onStart: beginFromLanding
                    )

                    if let saveErrorMessage {
                        VStack {
                            Spacer()
                            GlassInfoBanner(kind: .danger, message: saveErrorMessage)
                                .padding(.horizontal, 40)
                                .padding(.bottom, 24)
                        }
                    }
                } else {
                    ScrollView {
                        VStack(spacing: GlassTheme.sectionSpacing) {
                            phaseContent

                            if let saveErrorMessage {
                                GlassInfoBanner(kind: .danger, message: saveErrorMessage)
                            }
                        }
                        .padding(.horizontal, 40)
                        .padding(.top, 16)
                        .padding(.bottom, 32)
                        .frame(maxWidth: GlassTheme.maxContentWidth + 80)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch currentPhase {
        case .landing:
            EmptyView()

        case .welcome:
            WelcomeView(
                onContinue: startSentenceTraining,
                onBack: { applyLaunchRouting() }
            )

        case .sentenceTraining:
            SentenceTrainingView(
                currentSentenceIndex: currentSentenceIndex,
                totalSentences: trainingSentences.count,
                currentSentence: currentSentenceIndex < trainingSentences.count
                    ? trainingSentences[currentSentenceIndex]
                    : "",
                typedText: sentenceTypedText,
                hasError: sentenceHasError,
                isRetrainSession: isReenrollment,
                onKeystroke: handleSentenceTrainingKeystroke,
                onBack: {
                    if isReenrollment {
                        isReenrollment = false
                        currentPhase = .settings
                    } else {
                        currentPhase = .welcome
                    }
                }
            )

        case .setPassword:
            SetPasswordView(
                masterPassword: $masterPassword,
                repeatPassword: $repeatPassword,
                validationMessage: $passwordValidationMessage,
                flowTitle: isChangingMasterPassword
                    ? "Choose New Master Password"
                    : "Step 2: Create Master Password",
                flowSubtitle: isChangingMasterPassword
                    ? "Minimum \(PasswordPolicy.minimumLength) characters. Website passwords saved on this Mac are not removed."
                    : "Minimum \(PasswordPolicy.minimumLength) characters. Both fields show what you type.",
                continueTitle: isChangingMasterPassword
                    ? "Continue"
                    : "Continue",
                backTitle: isChangingMasterPassword ? "Back" : "Back",
                onContinue: continueToPasswordEnrollment,
                onBack: backFromSetPassword
            )

        case .changePasswordVerify:
            ChangePasswordVerifyView(
                typedLength: changePasswordCurrent.count,
                errorMessage: changePasswordVerifyError,
                passThreshold: passThreshold,
                onKeystroke: handleChangePasswordVerifyKeystroke,
                onVerify: verifyCurrentPasswordForChange,
                onBack: cancelChangeMasterPassword
            )

        case .passwordEnrollment:
            PasswordEnrollmentView(
                sampleIndex: currentSampleIndex,
                totalSamples: EnrollmentConfig.requiredSamples,
                typedLength: currentSampleText.count,
                liveMatchPercentage: enrollmentLiveMatchPercentage,
                hasError: enrollmentHasError,
                isReenrollment: isReenrollment,
                isChangingMasterPassword: isChangingMasterPassword,
                errorMessage: enrollmentErrorMessage,
                onKeystroke: handlePasswordEnrollmentKeystroke,
                onClearSample: clearCurrentEnrollmentSample,
                onBack: backFromPasswordEnrollment
            )

        case .explanation:
            ExplanationView(
                keystrokeCount: passwordEnrollmentSamples.flatMap { $0 }.count,
                positionCount: pendingRhythmProfile?.positionStats.count ?? 0,
                sampleCount: passwordEnrollmentSamples.count,
                onContinue: saveProfileAndContinue,
                onBack: {
                    resetCurrentSample()
                    currentPhase = .passwordEnrollment
                }
            )

        case .login:
            loginPhaseContent

        case .success:
            successResultContent

        case .denied:
            deniedResultContent

        case .settings:
            SettingsView(
                passThreshold: $passThreshold,
                rhythmProfile: profileStore.loadProfile()?.rhythmProfile,
                lastVerifiedAt: HomeDashboardModel.lastLoginDate(from: auditEvents),
                showsReenrollmentReminder: shouldShowReenrollmentReminder,
                settingsNotice: settingsNotice,
                settingsBackTitle: "Back to Log In",
                pendingSecurityAction: .constant(nil),
                pendingSettingsScroll: .constant(nil),
                onBack: { currentPhase = .login },
                onChangeMasterPasswordComplete: { notice in
                    settingsNotice = notice
                },
                onRetrainTypingProfileComplete: {
                    settingsNotice = "Typing profile retrained successfully."
                    AdaptiveRhythmStore.shared.reset()
                },
                onResetBiometricData: resetBiometricData
            )

        case .main:
            EmptyView()
        }
    }

    @ViewBuilder
    private var loginPhaseContent: some View {
        LoginView(
            title: isEnrollmentTest ? "Step 4: Test Your Profile" : "Log In",
            subtitle: isEnrollmentTest
                ? "Verify that your saved profile recognizes you."
                : "Enter your master password to log in.",
            loginAttemptText: loginAttemptText,
            isTestMode: isEnrollmentTest,
            showsReenrollmentReminder: shouldShowReenrollmentReminder,
            showsLegacyProfileReminder: shouldShowLegacyProfileReminder,
            passThreshold: passThreshold,
            lockoutStatus: isEnrollmentTest ? nil : profileStore.lockoutStatus(now: lockoutClock),
            contextBannerMessage: loginContextMessage,
            showsTouchIDFallback: !isEnrollmentTest && BiometricAuthService.isAvailable,
            isTouchIDAvailable: BiometricAuthService.isAvailable,
            isTouchIDInProgress: isTouchIDInProgress,
            onKeystroke: handleLoginKeystroke,
            onVerify: verifyLogin,
            onTouchID: isEnrollmentTest ? nil : { Task { await attemptTouchIDFallback() } },
            onRetry: { resetLoginAttempt() },
            onResetLockout: isEnrollmentTest ? nil : { resetLockoutForTesting() },
            onOpenSettings: isEnrollmentTest ? nil : {
                refreshAuditEvents()
                refreshSiteSettings()
                currentPhase = .settings
            },
            onBack: isEnrollmentTest ? nil : (loginContextMessage == nil ? { showLandingFromLogin() } : nil)
        )
    }

    @ViewBuilder
    private var successResultContent: some View {
        ResultView(
            granted: true,
            matchPercentage: matchPercentage,
            denialReason: nil,
            isTestMode: isEnrollmentTest,
            onTryAgain: { resetLoginAttempt() },
            onContinue: isEnrollmentTest ? { finishEnrollmentTest() } : nil,
            onResetLockout: isEnrollmentTest ? nil : { resetLockoutForTesting() }
        )
    }

    @ViewBuilder
    private var deniedResultContent: some View {
        ResultView(
            granted: false,
            matchPercentage: matchPercentage,
            denialReason: denialReason,
            isTestMode: isEnrollmentTest,
            onTryAgain: { resetLoginAttempt() },
            onContinue: nil,
            onResetLockout: isEnrollmentTest ? nil : { resetLockoutForTesting() }
        )
    }

    private var enrollmentLiveMatchPercentage: Int? {
        guard !isReenrollment, !isChangingMasterPassword else { return nil }
        guard !currentSampleData.isEmpty, !passwordEnrollmentSamples.isEmpty else { return nil }
        guard let profile = RhythmProfile.from(
            passwordSamples: passwordEnrollmentSamples,
            password: masterPassword
        ) else { return nil }

        return RhythmVerifier.matchPercentage(
            loginData: currentSampleData,
            password: masterPassword,
            profile: profile
        )
    }

    private func refreshAuditEvents() {
        auditEvents = AuditLogService.shared.events()
    }

    private func refreshSiteSettings() {
        siteCredentials = CredentialStore.shared.credentials()
        allowedOrigins = SitePolicyStore.shared.allowedOrigins()
        disabledAllowlistOrigins = SitePolicyStore.shared.disabledOrigins()
        trustedSenderDomains = DynamicShieldPolicyStore.shared.trustedSenderDomains()
        disabledTrustedSenderDomains = DynamicShieldPolicyStore.shared.disabledSenderDomains()
    }

    private var shouldShowReenrollmentReminder: Bool {
        guard let profile = profileStore.loadProfile()?.rhythmProfile else { return false }
        guard !profile.isLegacyProfile else { return false }
        return profile.daysSinceEnrollment() >= EnrollmentConfig.reenrollmentReminderDays
    }

    private var shouldShowLegacyProfileReminder: Bool {
        profileStore.loadProfile()?.rhythmProfile.isLegacyProfile ?? false
    }

    private func resolveLaunchPhase() {
        guard !hasResolvedLaunchPhase else { return }
        hasResolvedLaunchPhase = true
        passThreshold = RhythmSettings.passThreshold
        applyLaunchRouting()
    }

    /// Routes the auth flow from the local (Keychain) vault only: unlock when a vault exists, else landing.
    private func applyLaunchRouting() {
        landingMessage = nil
        saveErrorMessage = nil

        switch AppLaunchRouter.resolve(hasLocalMasterProfile: profileStore.hasProfile) {
        case .masterLogin:
            proceedToMasterLogin()
        case .landing:
            currentPhase = .landing
        }
    }

    /// Minimal placeholder while cloud session refresh and launch routing complete.
    private var launchBootstrapContent: some View {
        VStack(spacing: 16) {
            DynamicKeyBrandLogo(size: 88)
            ProgressView()
                .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleLockoutTimerTick(at date: Date) {
        guard currentPhase == .login || currentPhase == .denied else { return }
        if profileStore.lockoutStatus(now: date).isLocked {
            lockoutClock = date
        }
    }

    /// Landing button label reflects whether this Mac already has a vault (returning vs. first-run).
    private var landingActionTitle: String {
        profileStore.hasProfile ? "Welcome Back" : "Start Training"
    }

    /// Back from master login returns to the landing page (so the user can see it again).
    private func showLandingFromLogin() {
        landingMessage = nil
        saveErrorMessage = nil
        currentPhase = .landing
    }

    /// Single landing action: unlock when a vault exists, otherwise begin master-password enrollment.
    private func beginFromLanding() {
        landingMessage = nil
        saveErrorMessage = nil
        if profileStore.hasProfile {
            proceedToMasterLogin()
        } else {
            beginEnrollment()
        }
    }

    private func proceedToMasterLogin() {
        isEnrollmentTest = false
        isReenrollment = false
        loginAttemptText = ""
        loginData = []
        matchPercentage = 0
        denialReason = nil
        // Keyboard/Wi-Fi trust status is surfaced on the Home Dashboard, so the master-password
        // login screen stays clean and carries no trust banner message here.
        loginContextMessage = nil
        currentPhase = .login
    }

    private func beginEnrollment() {
        masterPassword = ""
        repeatPassword = ""
        passwordValidationMessage = nil
        passwordEnrollmentSamples = []
        pendingRhythmProfile = nil
        isReenrollment = false
        currentSampleIndex = 0
        trainingSentences = []
        currentSentenceIndex = 0
        sentenceTypedText = ""
        sentenceHasError = false
        resetCurrentSample()
        currentPhase = .welcome
    }

    private func startSentenceTraining() {
        trainingSentences = TrainingSentenceProvider.randomSentences()
        currentSentenceIndex = 0
        sentenceTypedText = ""
        sentenceHasError = false
        currentPhase = .sentenceTraining
    }

    private func backToSentenceTraining() {
        currentSentenceIndex = 0
        sentenceTypedText = ""
        sentenceHasError = false
        currentPhase = .sentenceTraining
    }

    private func handleSentenceTrainingKeystroke(_ data: KeystrokeData) {
        guard currentSentenceIndex < trainingSentences.count else { return }

        if isDeleteKey(data.character) {
            guard !sentenceTypedText.isEmpty else { return }
            sentenceTypedText.removeLast()
            sentenceHasError = false
            return
        }

        let currentSentence = trainingSentences[currentSentenceIndex]
        let nextIndex = sentenceTypedText.count
        guard nextIndex < currentSentence.count else { return }

        let targetIndex = currentSentence.index(currentSentence.startIndex, offsetBy: nextIndex)
        if String(currentSentence[targetIndex]) == data.character {
            sentenceHasError = false
            sentenceTypedText.append(data.character)

            if sentenceTypedText == currentSentence {
                completeCurrentSentence()
            }
        } else {
            sentenceHasError = true
        }
    }

    private func completeCurrentSentence() {
        sentenceTypedText = ""
        sentenceHasError = false

        if currentSentenceIndex < trainingSentences.count - 1 {
            currentSentenceIndex += 1
        } else if isReenrollment {
            passwordEnrollmentSamples = []
            currentSampleIndex = 0
            resetCurrentSample()
            currentPhase = .passwordEnrollment
        } else {
            currentPhase = .setPassword
        }
    }

    private func continueToPasswordEnrollment() {
        saveErrorMessage = nil
        passwordValidationMessage = PasswordPolicy.validate(
            password: masterPassword,
            repeatPassword: repeatPassword
        )
        guard passwordValidationMessage == nil else { return }

        if isChangingMasterPassword, masterPassword == changePasswordVerifiedCurrent {
            passwordValidationMessage = ProfileStoreError.newPasswordSameAsCurrent.localizedDescription
            return
        }

        passwordEnrollmentSamples = []
        currentSampleIndex = 0
        resetCurrentSample()
        currentPhase = .passwordEnrollment
    }

    private func backFromSetPassword() {
        if isChangingMasterPassword {
            masterPassword = ""
            repeatPassword = ""
            passwordValidationMessage = nil
            currentPhase = .changePasswordVerify
        } else {
            backToSentenceTraining()
        }
    }

    private func beginChangeMasterPassword() {
        guard profileStore.hasProfile else {
            saveErrorMessage = ProfileStoreError.profileNotFound.localizedDescription
            return
        }

        saveErrorMessage = nil
        settingsNotice = nil
        isChangingMasterPassword = true
        isReenrollment = false
        changePasswordCurrent = ""
        changePasswordVerifyData = []
        changePasswordVerifiedCurrent = ""
        changePasswordVerifyError = nil
        masterPassword = ""
        repeatPassword = ""
        passwordValidationMessage = nil
        passwordEnrollmentSamples = []
        pendingRhythmProfile = nil
        currentSampleIndex = 0
        resetCurrentSample()
        currentPhase = .changePasswordVerify
    }

    private func presentChangeMasterPassword() {
        guard profileStore.hasProfile else {
            saveErrorMessage = ProfileStoreError.profileNotFound.localizedDescription
            return
        }

        if currentPhase == .main {
            settingsSlideOver = .changeMasterPassword
        } else {
            beginChangeMasterPassword()
        }
    }

    private func completeChangeMasterPassword(notice: String) {
        settingsNotice = notice
        settingsSlideOver = nil
        refreshAuditEvents()
        appStatus.refresh()
    }

    private func presentRetrainTypingProfile() {
        guard profileStore.hasProfile else {
            saveErrorMessage = ProfileStoreError.profileNotFound.localizedDescription
            return
        }

        if currentPhase == .main {
            mainSidebarSelection = .settings
            pendingSecurityAction = .retrainProfile
        } else {
            beginReenrollment()
        }
    }

    private func presentBrowserExtensionSettings() {
        if currentPhase == .main {
            mainSidebarSelection = .settings
            pendingSettingsScroll = .browserExtension
        }
    }

    /// Brings the primary DynamicKey window forward without focusing Preferences.
    private func bringMainWindowForward() {
        let preferencesTitle = "DynamicKey Preferences"
        if let mainWindow = NSApp.windows.first(where: { window in
            window.canBecomeKey && window.title != preferencesTitle
        }) {
            mainWindow.makeKeyAndOrderFront(nil)
            return
        }

        NSApp.windows.first { $0.canBecomeKey }?.makeKeyAndOrderFront(nil)
    }

    private func completeRetrainTypingProfile() {
        settingsNotice = "Typing profile retrained successfully."
        settingsSlideOver = nil
        // The rhythm baseline changed, so past match scores no longer describe this profile.
        AdaptiveRhythmStore.shared.reset()
        refreshAuditEvents()
        appStatus.refresh()
    }

    private func resetBiometricData() {
        deleteProfile()
    }

    private func verifyCurrentPasswordForChange() {
        changePasswordVerifyError = nil

        let result = profileStore.verifyLogin(
            password: changePasswordCurrent,
            loginData: changePasswordVerifyData,
            enforceSecurity: false
        )

        guard result.granted else {
            changePasswordVerifyError = changePasswordDenialMessage(for: result)
            SensitiveDataCleaner.clearLoginAttempt(text: &changePasswordCurrent, data: &changePasswordVerifyData)
            return
        }

        changePasswordVerifiedCurrent = changePasswordCurrent
        SensitiveDataCleaner.clearLoginAttempt(text: &changePasswordCurrent, data: &changePasswordVerifyData)
        masterPassword = ""
        repeatPassword = ""
        passwordValidationMessage = nil
        currentPhase = .setPassword
    }

    private func handleChangePasswordVerifyKeystroke(_ data: KeystrokeData) {
        if data.character == "\r" {
            verifyCurrentPasswordForChange()
            return
        }

        if isDeleteKey(data.character) {
            guard !changePasswordCurrent.isEmpty, !changePasswordVerifyData.isEmpty else { return }
            changePasswordCurrent.removeLast()
            changePasswordVerifyData.removeLast()
            return
        }

        changePasswordVerifyData.append(data)
        changePasswordCurrent.append(data.character)
    }

    private func changePasswordDenialMessage(for result: LoginVerificationResult) -> String {
        switch result.denialReason {
        case .wrongPassword:
            return ProfileStoreError.wrongPassword.localizedDescription
        case .rhythmMismatch:
            return "Typing rhythm did not match (\(result.matchPercentage)% — need at least \(passThreshold)%)."
        case .emptyInput:
            return "Type your current master password first."
        case .lockedOut(let remaining):
            return "Sign-in is temporarily locked. Try again in \(remaining)s."
        case .untrustedKeyboard:
            return "This keyboard is not trusted. Update trusted keyboards in Settings or connect an approved device."
        case .untrustedNetwork:
            return "This Wi-Fi network is not trusted. Join a trusted network or update Settings."
        case .none:
            return "Verification failed. Try again."
        }
    }

    private func cancelChangeMasterPassword() {
        isChangingMasterPassword = false
        changePasswordCurrent = ""
        changePasswordVerifyData = []
        changePasswordVerifiedCurrent = ""
        changePasswordVerifyError = nil
        masterPassword = ""
        repeatPassword = ""
        passwordValidationMessage = nil
        returnToMainSettings()
    }

    private func finishChangeMasterPassword() {
        guard let rhythmProfile = pendingRhythmProfile else {
            saveErrorMessage = ProfileStoreError.invalidRhythmProfile.localizedDescription
            return
        }

        do {
            try profileStore.changeMasterPassword(
                currentPassword: changePasswordVerifiedCurrent,
                newPassword: masterPassword,
                rhythmProfile: rhythmProfile
            )
            clearSensitivePasswordFields()
            SensitiveDataCleaner.clear(&changePasswordVerifiedCurrent)
            isChangingMasterPassword = false
            pendingRhythmProfile = nil
            passwordEnrollmentSamples = []
            // New password → new rhythm baseline, so previous match scores are no longer relevant.
            AdaptiveRhythmStore.shared.reset()
            settingsNotice = "Master password updated. Use your new password in the browser extension and Mac log in."
            saveErrorMessage = nil
            refreshAuditEvents()
            appStatus.refresh()
            returnToMainSettings()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func beginReenrollment() {
        guard profileStore.hasProfile else {
            saveErrorMessage = ProfileStoreError.profileNotFound.localizedDescription
            return
        }

        isReenrollment = true
        passwordEnrollmentSamples = []
        pendingRhythmProfile = nil
        currentSampleIndex = 0
        enrollmentErrorMessage = nil
        saveErrorMessage = nil
        trainingSentences = TrainingSentenceProvider.randomSentences()
        currentSentenceIndex = 0
        sentenceTypedText = ""
        sentenceHasError = false
        resetCurrentSample()
        currentPhase = .sentenceTraining
    }

    private func backFromPasswordEnrollment() {
        resetCurrentSample()
        if isReenrollment {
            isReenrollment = false
            returnToMainSettings()
        } else if isChangingMasterPassword {
            currentPhase = .setPassword
        } else {
            currentPhase = .setPassword
        }
    }

    private func returnToMainSettings() {
        mainSidebarSelection = .settings
        currentPhase = .main
    }

    private func handlePasswordEnrollmentKeystroke(_ data: KeystrokeData) {
        if isReenrollment {
            handleReenrollmentKeystroke(data)
            return
        }

        if isDeleteKey(data.character) {
            guard !currentSampleText.isEmpty, !currentSampleData.isEmpty else { return }
            currentSampleText.removeLast()
            currentSampleData.removeLast()
            enrollmentHasError = false
            enrollmentErrorMessage = nil
            return
        }

        let targetPassword = masterPassword
        let nextIndex = currentSampleText.index(currentSampleText.startIndex, offsetBy: currentSampleText.count)
        guard nextIndex < targetPassword.endIndex else { return }

        if String(targetPassword[nextIndex]) == data.character {
            enrollmentHasError = false
            enrollmentErrorMessage = nil
            currentSampleText.append(data.character)
            currentSampleData.append(data)

            if currentSampleText == targetPassword {
                passwordEnrollmentSamples.append(currentSampleData)
                SensitiveDataCleaner.clearEnrollmentSample(text: &currentSampleText, data: &currentSampleData)
                if currentSampleIndex < EnrollmentConfig.requiredSamples - 1 {
                    currentSampleIndex += 1
                    resetCurrentSample()
                } else {
                    finishPasswordEnrollment()
                }
            }
        } else {
            enrollmentHasError = true
            enrollmentErrorMessage = "That character was incorrect. Continue from the mistake."
        }
    }

    private func handleReenrollmentKeystroke(_ data: KeystrokeData) {
        if data.character == "\r" {
            completeReenrollmentSample()
            return
        }

        if isDeleteKey(data.character) {
            guard !currentSampleText.isEmpty, !currentSampleData.isEmpty else { return }
            currentSampleText.removeLast()
            currentSampleData.removeLast()
            enrollmentHasError = false
            enrollmentErrorMessage = nil
            return
        }

        enrollmentHasError = false
        enrollmentErrorMessage = nil
        currentSampleData.append(data)
        currentSampleText.append(data.character)
    }

    private func completeReenrollmentSample() {
        guard !currentSampleText.isEmpty else {
            enrollmentHasError = true
            enrollmentErrorMessage = "Type your password, then press Enter."
            return
        }

        guard profileStore.verifyPassword(currentSampleText) else {
            enrollmentHasError = true
            enrollmentErrorMessage = "Incorrect password. Use Clear Sample and try again."
            return
        }

        enrollmentHasError = false
        enrollmentErrorMessage = nil
        passwordEnrollmentSamples.append(currentSampleData)
        SensitiveDataCleaner.clearEnrollmentSample(text: &currentSampleText, data: &currentSampleData)

        if currentSampleIndex < EnrollmentConfig.requiredSamples - 1 {
            currentSampleIndex += 1
            resetCurrentSample()
        } else {
            finishPasswordEnrollment()
        }
    }

    private func clearCurrentEnrollmentSample() {
        resetCurrentSample()
        enrollmentErrorMessage = nil
    }

    private func finishPasswordEnrollment() {
        if isChangingMasterPassword {
            pendingRhythmProfile = RhythmProfile.from(
                passwordSamples: passwordEnrollmentSamples,
                password: masterPassword
            )
            guard pendingRhythmProfile != nil else {
                saveErrorMessage = ProfileStoreError.invalidRhythmProfile.localizedDescription
                return
            }
            finishChangeMasterPassword()
            return
        }

        if isReenrollment {
            guard let lastSample = passwordEnrollmentSamples.last else { return }
            let rebuiltPassword = lastSample.map(\.character).joined()
            guard profileStore.verifyPassword(rebuiltPassword) else {
                saveErrorMessage = ProfileStoreError.wrongPassword.localizedDescription
                passwordEnrollmentSamples = []
                currentSampleIndex = 0
                enrollmentErrorMessage = ProfileStoreError.wrongPassword.localizedDescription
                resetCurrentSample()
                return
            }
            pendingRhythmProfile = RhythmProfile.from(
                passwordSamples: passwordEnrollmentSamples,
                password: rebuiltPassword
            )
            guard let pendingRhythmProfile else {
                saveErrorMessage = ProfileStoreError.invalidRhythmProfile.localizedDescription
                return
            }
            do {
                try profileStore.updateRhythmProfile(pendingRhythmProfile, verifyingPassword: rebuiltPassword)
                self.pendingRhythmProfile = nil
                isReenrollment = false
                settingsNotice = "Typing profile retrained successfully."
                saveErrorMessage = nil
                refreshAuditEvents()
                appStatus.refresh()
                refreshSiteSettings()
                returnToMainSettings()
            } catch {
                saveErrorMessage = error.localizedDescription
            }
            return
        }

        pendingRhythmProfile = RhythmProfile.from(
            passwordSamples: passwordEnrollmentSamples,
            password: masterPassword
        )
        guard pendingRhythmProfile != nil else {
            saveErrorMessage = ProfileStoreError.invalidRhythmProfile.localizedDescription
            return
        }
        currentPhase = .explanation
    }

    private func saveProfileAndContinue() {
        saveErrorMessage = nil

        guard let rhythmProfile = pendingRhythmProfile else {
            saveErrorMessage = ProfileStoreError.invalidRhythmProfile.localizedDescription
            return
        }

        do {
            try profileStore.saveProfile(password: masterPassword, rhythmProfile: rhythmProfile)
            clearSensitivePasswordFields()
            isEnrollmentTest = true
            resetLoginAttempt()
            refreshAuditEvents()
            appStatus.refresh()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func handleLoginKeystroke(_ data: KeystrokeData) {
        if data.character == "\r" {
            verifyLogin()
            return
        }

        if isDeleteKey(data.character) {
            guard !loginAttemptText.isEmpty, !loginData.isEmpty else { return }
            loginAttemptText.removeLast()
            loginData.removeLast()
            return
        }

        loginData.append(data)
        loginAttemptText.append(data.character)
    }

    private func verifyLogin() {
        let password = loginAttemptText
        let keystrokes = loginData

        if !isEnrollmentTest {
            let trustEvaluation = trustContext.evaluateForUnlock()
            guard trustEvaluation.allowed else {
                appendTrustFailureAudit(for: trustEvaluation.denialReason)
                denialReason = trustEvaluation.denialReason
                matchPercentage = 0
                SensitiveDataCleaner.clearLoginAttempt(text: &loginAttemptText, data: &loginData)
                refreshAuditEvents()
                currentPhase = .denied
                return
            }
        }

        let result = profileStore.verifyLogin(
            password: password,
            loginData: keystrokes,
            enforceSecurity: !isEnrollmentTest
        )
        matchPercentage = result.matchPercentage
        denialReason = result.denialReason
        SensitiveDataCleaner.clearLoginAttempt(text: &loginAttemptText, data: &loginData)
        refreshAuditEvents()
        if result.granted {
            // Adaptive learning: only genuine, real (non-test) logins that clear the threshold by a
            // comfortable margin refine the profile — this can only tighten/track the true rhythm and
            // never lowers the threshold itself. Every success also feeds the "raise threshold" advice.
            if !isEnrollmentTest {
                AdaptiveRhythmStore.shared.recordSuccessfulMatch(result.matchPercentage)
                if preferences.continuousLearningEnabled,
                   result.matchPercentage >= RhythmSettings.passThreshold + RhythmSettings.learningMarginAboveThreshold {
                    profileStore.refineRhythmProfile(password: password, loginData: keystrokes)
                }
            }
            completeSuccessfulLogin(isTest: isEnrollmentTest, matchPercentage: result.matchPercentage)
            return
        }

        currentPhase = .denied
    }

    /// Prompts Touch ID when the user taps the fallback button on the login screen.
    @MainActor
    private func attemptTouchIDFallback(password: String? = nil, expectedRhythmMismatch: Bool = false) async {
        let activePassword = password ?? loginAttemptText
        guard !activePassword.isEmpty else { return }

        let trustEvaluation = trustContext.evaluateForUnlock()
        guard trustEvaluation.allowed else {
            appendTrustFailureAudit(for: trustEvaluation.denialReason)
            denialReason = trustEvaluation.denialReason
            matchPercentage = 0
            SensitiveDataCleaner.clearLoginAttempt(text: &loginAttemptText, data: &loginData)
            refreshAuditEvents()
            currentPhase = .denied
            return
        }

        guard profileStore.verifyPassword(activePassword) else {
            if !expectedRhythmMismatch {
                denialReason = .wrongPassword
                matchPercentage = 0
                SensitiveDataCleaner.clearLoginAttempt(text: &loginAttemptText, data: &loginData)
                refreshAuditEvents()
                currentPhase = .denied
            }
            return
        }

        isTouchIDInProgress = true
        let approved = await BiometricAuthService.authenticate(
            reason: "Verify your identity to unlock DynamicKey."
        )
        isTouchIDInProgress = false

        if approved, let result = profileStore.grantLoginWithBiometricFallback(password: activePassword) {
            SensitiveDataCleaner.clearLoginAttempt(text: &loginAttemptText, data: &loginData)
            refreshAuditEvents()
            completeSuccessfulLogin(isTest: false, matchPercentage: result.matchPercentage)
            return
        }

        if expectedRhythmMismatch {
            denialReason = .rhythmMismatch
            matchPercentage = matchPercentage
            currentPhase = .denied
        }
    }

    /// Shared success path for rhythm and Touch ID fallback logins.
    private func completeSuccessfulLogin(isTest: Bool, matchPercentage grantedMatch: Int) {
        if isTest {
            matchPercentage = grantedMatch
            currentPhase = .success
        } else {
            lastLoginMatchPercentage = grantedMatch
            mainSidebarSelection = .home
            settingsNotice = nil
            loginContextMessage = nil
            currentPhase = .main
        }
    }

    /// Records audit events for context trust denials.
    private func appendTrustFailureAudit(for reason: DenialReason?) {
        switch reason {
        case .untrustedKeyboard:
            AuditLogService.shared.append(AuditEvent(type: .loginFailedUntrustedKeyboard))
        case .untrustedNetwork:
            AuditLogService.shared.append(AuditEvent(type: .loginFailedUntrustedNetwork))
        default:
            break
        }
    }

    private func logOutToLanding() {
        settingsNotice = nil
        settingsSlideOver = nil
        loginContextMessage = nil
        lastLoginMatchPercentage = 0
        mainSidebarSelection = .home
        loginAttemptText = ""
        loginData = []
        matchPercentage = 0
        denialReason = nil

        // Route in a single, coalesced transition so the window-chrome swap stays on one runloop turn.
        routeAfterLogout()
    }

    /// Logout always returns to the standard launch routing (master password login when a vault exists).
    private func routeAfterLogout() {
        applyLaunchRouting()
    }

    private func resetLoginAttempt() {
        loginAttemptText = ""
        loginData = []
        matchPercentage = 0
        denialReason = nil
        currentPhase = .login
    }

    private func finishEnrollmentTest() {
        isEnrollmentTest = false
        resetLoginAttempt()
    }

    private func resetCurrentSample() {
        currentSampleData = []
        currentSampleText = ""
        enrollmentHasError = false
        enrollmentErrorMessage = nil
    }

    private func clearSensitivePasswordFields() {
        masterPassword = ""
        repeatPassword = ""
        passwordValidationMessage = nil
    }

    private func deleteProfile() {
        do {
            try profileStore.deleteProfile()
            try CredentialStore.shared.deleteAll()
            SitePolicyStore.shared.setAllowedOrigins([])
            ExtensionPairingStore.shared.revokeAllPairings()
            AdaptiveRhythmStore.shared.reset()
            refreshAuditEvents()
            refreshSiteSettings()
            appStatus.refresh()
            landingMessage = nil
            applyLaunchRouting()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func clearAuditLog(for period: SecurityActivityPeriod) {
        AuditLogService.shared.clearEvents(for: period)
        refreshAuditEvents()
    }

    private func resetLockoutForTesting() {
        profileStore.resetLockout()
        lockoutClock = Date()
        denialReason = nil
        refreshAuditEvents()
        if currentPhase == .denied {
            currentPhase = .login
        }
    }

    private func isDeleteKey(_ character: String) -> Bool {
        character == "\u{7f}" || character == "\u{8}"
    }

    private func addSiteCredential(origin: String, username: String, password: String, isGenerated: Bool = false) {
        saveErrorMessage = nil
        let credential = SiteCredential(
            origin: origin,
            username: username,
            password: password,
            isGenerated: isGenerated
        )
        do {
            try CredentialStore.shared.save(credential)
            refreshSiteSettings()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func deleteSiteCredential(id: UUID) {
        do {
            try CredentialStore.shared.delete(id: id)
            refreshSiteSettings()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func regenerateSitePassword(id: UUID) {
        saveErrorMessage = nil
        do {
            let updated = try CredentialStore.shared.regeneratePassword(id: id)
            AuditLogService.shared.append(
                AuditEvent(
                    type: .siteCredentialGenerated,
                    detail: "\(updated.origin) — regenerated"
                )
            )
            refreshSiteSettings()
            refreshAuditEvents()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func addAllowedOrigin(_ origin: String) {
        SitePolicyStore.shared.addAllowedOrigin(origin)
        refreshSiteSettings()
    }

    private func removeAllowedOrigin(_ origin: String) {
        SitePolicyStore.shared.removeAllowedOrigin(origin)
        refreshSiteSettings()
    }

    private func toggleAllowlistOrigin(_ origin: String, isAllowed: Bool) {
        SitePolicyStore.shared.setOriginEnabled(origin, enabled: isAllowed)
        refreshSiteSettings()
    }

    private func removeTrustedSenderDomain(_ domain: String) {
        let normalized = DynamicShieldPolicyStore.normalizeSenderDomain(domain)
        DynamicShieldPolicyStore.shared.removeTrustedSenderDomain(domain)
        if !normalized.isEmpty {
            AuditLogService.shared.append(
                AuditEvent(
                    type: .extensionDynamicShieldRemoved,
                    detail: "Mac app · @\(normalized)"
                )
            )
        }
        refreshSiteSettings()
        refreshAuditEvents()
    }

    private func toggleTrustedSenderDomain(_ domain: String, isTrusted: Bool) {
        DynamicShieldPolicyStore.shared.setSenderDomainEnabled(domain, enabled: isTrusted)
        refreshSiteSettings()
    }

    private func addTrustedSenderDomain(_ domain: String) {
        let normalized = DynamicShieldPolicyStore.normalizeSenderDomain(domain)
        guard !normalized.isEmpty else { return }

        DynamicShieldPolicyStore.shared.addTrustedSenderDomain(domain)
        AuditLogService.shared.append(
            AuditEvent(
                type: .extensionDynamicShieldTrusted,
                detail: "Mac app · @\(normalized)"
            )
        )
        refreshSiteSettings()
        refreshAuditEvents()
    }
}
