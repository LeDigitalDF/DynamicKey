// LeakPeekBreachCheckOverlay.swift
// Full-window dimmed overlay with centered sonar radar and in-app breach results.
// Flow: heavy dim → sonar scan animation → action checklist → centered Done.

import SwiftUI

struct LeakPeekBreachCheckOverlay: View {
    let credentials: [SiteCredential]

    @ObservedObject private var identityStore = LeakPeekIdentityStore.shared

    private let accent = MainSidebarSection.leakPeek.accentColor

    private var scrimOpacity: Double {
        identityStore.isChecking ? 0.9 : 0.84
    }

    var body: some View {
        ZStack {
            Color.black.opacity(scrimOpacity)
                .ignoresSafeArea()
                .onTapGesture {
                    guard !identityStore.isChecking else { return }
                    identityStore.dismissOverlay()
                }

            if identityStore.isChecking {
                scanningLayout
            } else {
                resultsLayout
            }
        }
        .transition(.opacity)
    }

    // Running state — radar centered with a thin progress strip at the top.
    private var scanningLayout: some View {
        VStack(spacing: 0) {
            topProgressBar
                .padding(.top, 14)
                .padding(.horizontal, 40)

            Text(identityStore.statusMessage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
                .padding(.horizontal, 28)
                .padding(.top, 14)

            Spacer(minLength: 0)

            LeakPeekSonarRadarView(
                blips: identityStore.radarBlips,
                progress: identityStore.progress
            )
            .frame(maxWidth: 320, maxHeight: 320)
            .padding(.horizontal, 40)

            Text("Searching public breach records…")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
                .padding(.top, 18)

            Spacer(minLength: 0)
        }
    }

    // Finished / failed — results card only; no radar.
    private var resultsLayout: some View {
        VStack(spacing: 0) {
            topProgressBar
                .padding(.top, 14)
                .padding(.horizontal, 40)

            contentPanel
                .padding(.horizontal, 28)
                .padding(.top, 22)

            Spacer(minLength: 0)
        }
    }

    // Simple linear progress — no spinning chrome.
    private var topProgressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.1))

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.12, green: 0.92, blue: 0.52).opacity(0.85),
                                accent,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, proxy.size.width * identityStore.progress))
            }
        }
        .frame(height: 4)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var contentPanel: some View {
        switch identityStore.phase {
        case .idle:
            EmptyView()

        case .running:
            EmptyView()

        case .finished:
            finishedCard

        case .failed(let message):
            failedCard(message: message)
        }
    }

    private var finishedCard: some View {
        let activeStatuses = identityStore.activeCompromisedStatuses()
        let needsAction = !activeStatuses.isEmpty

        return GlassPanel {
            VStack(spacing: 16) {
                resultsHeader(needsAction: needsAction)

                if needsAction {
                    ScrollView {
                        LeakPeekBreachActionChecklist(credentials: credentials)
                    }
                    .frame(maxHeight: 280)
                } else {
                    Text(resolvedCopy)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }

                Text("Breach data provided by XposedOrNot. Email addresses are sent securely over HTTPS for lookup.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)

                GlassButton(
                    title: "Done",
                    tint: accent,
                    capsuleTintOverride: .enroll,
                    expandsFullWidth: false
                ) {
                    identityStore.dismissOverlay()
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(20)
            .frame(maxWidth: 520)
        }
    }

    private func resultsHeader(needsAction: Bool) -> some View {
        VStack(spacing: 8) {
            Image(systemName: needsAction ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
                .font(.title2)
                .foregroundStyle(needsAction ? .orange : .green)

            Text(needsAction ? "Action recommended" : "Emails look clear")
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)

            Text(identityStore.statusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var resolvedCopy: String {
        if case .finished = identityStore.phase {
            return "None of your saved email addresses have open breach actions, or you marked them resolved."
        }
        return "None of your saved email addresses matched known public breach databases."
    }

    private func failedCard(message: String) -> some View {
        GlassPanel {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.title2)
                        .foregroundStyle(.orange)

                    Text("Breach check could not finish")
                        .font(.title3.weight(.bold))
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)

                GlassButton(
                    title: "Close",
                    role: .secondary,
                    expandsFullWidth: false
                ) {
                    identityStore.dismissOverlay()
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(20)
            .frame(maxWidth: 460)
        }
    }
}
