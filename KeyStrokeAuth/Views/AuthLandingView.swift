// AuthLandingView.swift
// First-run / returning entry — a single state-driven button (no cloud login choices).
// Identity is the user's iCloud account, so there is no Sign Up / Log In here anymore.
//
// Flow: logo → animated title → a typewriter intro that explains the app (types itself out) → one
//       button ("Start Training" for new users, "Welcome Back" when a local vault already exists).
// The button is dimmed and disabled while the intro types; clicking anywhere skips the animation and
// reveals the full text immediately. Once the intro finishes (or is skipped) the button is enabled.

import SwiftUI

private enum AuthLandingLayout {
    static let logoSize: CGFloat = 120
    static let horizontalPadding: CGFloat = 40
    static let blockSpacing: CGFloat = 14
    static let actionSpacing: CGFloat = 10
    /// Width of the primary landing button — adjust this to resize it.
    static let actionButtonWidth: CGFloat = 250
    /// Gap between the title letters and the intro animation — increase to push the text further down.
    static let titleToIntroSpacing: CGFloat = 48
    /// Gap between the intro text and the button — increase to push the button further down.
    static let infoToButtonsSpacing: CGFloat = 100
    /// Max width of the typewriter intro paragraph (keeps line lengths comfortable).
    static let introTextWidth: CGFloat = 420
    /// Seconds between each revealed character of the intro.
    static let introCharacterInterval: TimeInterval = 0.028
}

// Short explanation typed out on first launch. Kept concise so the animation stays snappy.
private let landingIntroText =
    "DynamicKey verifies you by how you type — not just what you type. You'll train a master password once, and from then on your unique typing rhythm unlocks the vault. Everything stays on this Mac."

struct AuthLandingView: View {
    var landingMessage: String?
    /// Label for the single primary action (e.g. "Start Training" or "Welcome Back").
    let actionTitle: String
    let onStart: () -> Void

    // True once the intro has finished typing (or was skipped). Drives button enable/dim.
    @State private var isIntroComplete = false
    // Incremented to request an immediate skip of the typewriter animation.
    @State private var skipToken = 0

    // The button is active when there is a message to show (no intro) or the intro has finished.
    private var buttonEnabled: Bool {
        landingMessage != nil || isIntroComplete
    }

    // The tap-anywhere skip layer is only active while the intro is still typing.
    private var showsSkipLayer: Bool {
        landingMessage == nil && !isIntroComplete
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: AuthLandingLayout.blockSpacing) {
                    DynamicKeyBrandLogo(size: AuthLandingLayout.logoSize)
                        .frame(maxWidth: .infinity)

                    DynamicKeyAnimatedTitle()

                    // Extra top spacing centers the intro text between the title and the button.
                    Group {
                        if let landingMessage {
                            // An error/notice replaces the intro; the button is immediately usable.
                            AuthLandingHintRow(message: landingMessage, tint: .orange)
                        } else {
                            LandingTypewriterText(
                                text: landingIntroText,
                                characterInterval: AuthLandingLayout.introCharacterInterval,
                                maxWidth: AuthLandingLayout.introTextWidth,
                                skipToken: skipToken,
                                onComplete: { isIntroComplete = true }
                            )
                        }
                    }
                    .padding(.top, AuthLandingLayout.titleToIntroSpacing)

                    // Single entry point — routing is decided by the caller based on vault presence.
                    VStack(spacing: AuthLandingLayout.actionSpacing) {
                        LiquidGlassSparkleButton(
                            title: actionTitle,
                            horizontalPadding: 24,
                            verticalPadding: 0,
                            font: .system(size: 19, weight: .semibold),
                            minHeight: GlassTheme.actionButtonHeight,
                            expandsFullWidth: true,
                            usesCapsuleShape: true,
                            sparklePalette: .enroll,
                            showsDropShadow: true,
                            widthAnchorTitle: "Welcome Back",
                            isEnabled: buttonEnabled,
                            action: onStart
                        )
                    }
                    .frame(width: AuthLandingLayout.actionButtonWidth)
                    .padding(.top, AuthLandingLayout.infoToButtonsSpacing)
                }
                .frame(maxWidth: GlassTheme.maxContentWidth)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AuthLandingLayout.horizontalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Transparent layer that lets the user click anywhere to skip the intro animation.
            if showsSkipLayer {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { skipToken += 1 }
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Short inline hint — icon + text only, no glass panel (used for error/notice messages).
private struct AuthLandingHintRow: View {
    @Environment(\.glassPalette) private var palette

    let message: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.subheadline)
                .foregroundStyle(tint)

            Text(message)
                .font(.caption)
                .foregroundStyle(palette.onGlassSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
    }
}

/// Types a string out one character at a time, revealing the full text when `skipToken` changes.
/// Reserves space for the full paragraph up front so the layout does not jump while typing.
private struct LandingTypewriterText: View {
    @Environment(\.glassPalette) private var palette

    let text: String
    let characterInterval: TimeInterval
    let maxWidth: CGFloat
    /// Changing this value (from the parent) instantly reveals the full text.
    let skipToken: Int
    let onComplete: () -> Void

    @State private var visibleCount = 0
    @State private var timer: Timer?
    @State private var hasCompleted = false

    var body: some View {
        ZStack(alignment: .top) {
            // Invisible full text reserves the final height so the paragraph doesn't reflow/jump.
            styled(Text(text)).hidden()
            // Visible prefix that grows over time.
            styled(Text(String(text.prefix(visibleCount))))
        }
        .frame(maxWidth: maxWidth)
        .accessibilityLabel(text)
        .onAppear(perform: startTyping)
        .onDisappear { timer?.invalidate() }
        .onChange(of: skipToken) { _, _ in finishNow() }
    }

    // Shared styling for both the reserved (hidden) and visible text.
    private func styled(_ view: Text) -> some View {
        view
            .font(.callout)
            .foregroundStyle(palette.onGlassSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }

    // Starts the per-character reveal timer.
    private func startTyping() {
        guard timer == nil, !hasCompleted else { return }
        timer = Timer.scheduledTimer(withTimeInterval: characterInterval, repeats: true) { _ in
            Task { @MainActor in advance() }
        }
    }

    // Reveals the next character, completing when the whole string is shown.
    private func advance() {
        guard visibleCount < text.count else {
            finishNow()
            return
        }
        visibleCount += 1
        if visibleCount >= text.count {
            finishNow()
        }
    }

    // Reveals everything, stops the timer, and notifies the parent exactly once.
    private func finishNow() {
        timer?.invalidate()
        timer = nil
        visibleCount = text.count
        guard !hasCompleted else { return }
        hasCompleted = true
        onComplete()
    }
}