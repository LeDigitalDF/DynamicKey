// LoginView.swift
// Password entry with hidden keystroke capture for rhythm verification.

import SwiftUI

// Layout tuning specific to the master-password Login screen (kept local so other phases are unaffected).
private enum LoginScreenLayout {
    /// Extra space above the lettered title to push the content further down from the top of the window.
    static let headerTopPadding: CGFloat = 60
    /// Lettered title size for this screen — larger than the trust badges so the title reads clearly.
    static let titleLetterHeight: CGFloat = 56
}

struct LoginView: View {
    @Environment(\.glassPalette) private var palette

    let title: String
    let subtitle: String
    let loginAttemptText: String
    let isTestMode: Bool
    let showsReenrollmentReminder: Bool
    let showsLegacyProfileReminder: Bool
    let passThreshold: Int
    let lockoutStatus: LockoutStatus?
    var contextBannerMessage: String? = nil
    var showsTouchIDFallback: Bool = false
    var isTouchIDAvailable: Bool = false
    var isTouchIDInProgress: Bool = false
    let onKeystroke: (KeystrokeData) -> Void
    let onVerify: () -> Void
    let onTouchID: (() -> Void)?
    let onRetry: () -> Void
    let onResetLockout: (() -> Void)?
    let onOpenSettings: (() -> Void)?
    let onBack: (() -> Void)?

    var body: some View {
        PhaseScreenLayout {
            if !isTestMode {
                HStack {
                    if let onBack {
                        // Liquid glass back control (matches the app's round glass buttons).
                        GlassCircleIconButton(
                            systemImage: "chevron.left",
                            accessibilityLabel: "Back",
                            action: onBack
                        )
                    }

                    Spacer()

                    if let onOpenSettings {
                        GlassIconButton(
                            systemImage: "gearshape",
                            accessibilityLabel: "Settings",
                            action: onOpenSettings
                        )
                    }
                }
            } else {
                // Step 4 (test mode): Retry lives as a top-right icon. Same action as the old
                // Retry button; hovering reveals what it does, and a single tap clears the attempt.
                HStack {
                    Spacer()

                    GlassCircleIconButton(
                        systemImage: "arrow.clockwise",
                        accessibilityLabel: "Retry",
                        action: onRetry
                    )
                    .keyboardShortcut("r", modifiers: .command)
                    .help("Retry — clears your current attempt (⌘R).")
                }
            }

            if isTestMode {
                PhaseHeader(title: title, subtitle: subtitle)
            } else {
                // Login screen: title rendered with the Lettertype glyphs (matches the landing / Set Up Vault look),
                // pushed down from the top by the local header padding.
                LettertypeTitleView(
                    phrase: title,
                    letterHeight: LoginScreenLayout.titleLetterHeight,
                    letterSpacing: CloudAuthScreenLayout.titleLetterSpacing,
                    wordSpacing: CloudAuthScreenLayout.titleWordSpacing,
                    animate: false
                )
                .padding(.top, LoginScreenLayout.headerTopPadding)

                // Subtitle is its own element so the section spacing above (title) and below (field)
                // is equal — visually centering it between the header letters and the password field.
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(palette.onGlassSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let contextBannerMessage {
                GlassInfoBanner(
                    kind: .warning,
                    message: contextBannerMessage
                )
            }

            if let lockoutStatus, lockoutStatus.isLocked, let remaining = lockoutStatus.remainingSeconds {
                GlassInfoBanner(
                    kind: .danger,
                    message: "Too many failed attempts. Try again in \(formattedLockoutTime(remaining)).",
                    accessory: onResetLockout.map { reset in
                        AnyView(GlassTextButton(title: "Reset Lockout (Testing)", action: reset))
                    }
                )
            } else if let lockoutStatus,
                      case .available(let remainingAttempts) = lockoutStatus,
                      !isTestMode,
                      remainingAttempts < SecurityConfig.maxFailedAttemptsBeforeLockout {
                GlassInfoBanner(
                    kind: .warning,
                    message: "\(remainingAttempts) sign-in attempt\(remainingAttempts == 1 ? "" : "s") remaining before temporary lockout."
                )
            }

            if showsLegacyProfileReminder {
                GlassInfoBanner(
                    kind: .info,
                    message: "Your profile uses the older rhythm format. Update your typing profile in Settings for improved accuracy."
                )
            }

            if showsReenrollmentReminder {
                GlassInfoBanner(
                    kind: .warning,
                    message: "Your typing profile is older than \(EnrollmentConfig.reenrollmentReminderDays) days. Update it in Settings for better accuracy."
                )
            }

            if isTestMode {
                // Single, narrower info for Step 4 (Retry guidance now lives in the top-right icon's tooltip).
                GlassInfoBanner(
                    kind: .warning,
                    message: "Type your master password at normal speed. Pass threshold: \(passThreshold)%."
                )
                .frame(maxWidth: 380)
            }

            PasswordDotsDisplay(
                length: loginAttemptText.count,
                caption: passwordFieldCaption,
                // Login screen: flat frosted capsule, no gradient border (matches the sign-up fields).
                // Step 4 test mode keeps the standard border.
                borderStyle: isTestMode ? .standard : .none
            )

            KeystrokeMonitorViewRepresentable(onKeystroke: onKeystroke)
                .frame(width: 1, height: 1)

            // Action buttons use the same style as the Login / Sign Up landing buttons:
            // full-width capsules inside a fixed 250pt-wide column, so every button is identical in size.
            VStack(spacing: 10) {
                if showsTouchIDFallback, isTouchIDAvailable, let onTouchID {
                    GlassButton(
                        title: isTouchIDInProgress ? "Checking…" : "Use Touch ID",
                        role: .secondary,
                        isEnabled: lockoutStatus?.isLocked != true && !loginAttemptText.isEmpty && !isTouchIDInProgress,
                        expandsFullWidth: true,
                        action: onTouchID
                    )
                }

                LiquidGlassSparkleButton(
                    title: "Verify",
                    horizontalPadding: 24,
                    verticalPadding: 0,
                    font: .system(size: 19, weight: .semibold),
                    minHeight: GlassTheme.actionButtonHeight,
                    expandsFullWidth: true,
                    usesCapsuleShape: true,
                    sparklePalette: .blue,
                    showsDropShadow: true,
                    isEnabled: lockoutStatus?.isLocked != true,
                    submitOnReturn: true,
                    action: onVerify
                )
            }
            .frame(width: GlassTheme.actionButtonMaxWidth)
            .frame(maxWidth: .infinity)
        }
    }

    // Caption under the password dots. On the login screen the default hint is removed (the subtitle
    // already guides the user); only the lockout notice is shown. Step 4 keeps its original hint.
    private var passwordFieldCaption: String? {
        if lockoutStatus?.isLocked == true {
            return "Sign-in is temporarily locked."
        }
        return isTestMode ? "Type your password, then press Enter or Verify." : nil
    }

    private func formattedLockoutTime(_ seconds: Int) -> String {
        if seconds >= 60 {
            let minutes = seconds / 60
            let remainder = seconds % 60
            if remainder == 0 { return "\(minutes)m" }
            return "\(minutes)m \(remainder)s"
        }
        return "\(seconds)s"
    }
}
