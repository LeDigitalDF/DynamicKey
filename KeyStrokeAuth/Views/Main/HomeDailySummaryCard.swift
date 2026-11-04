// HomeDailySummaryCard.swift
// First-launch-of-day security brief on Home — expandable / slim bar like DynamicShield-style panels.
// Flow: MorningSummaryService headline → fact rows → suggested action; minimize persists across launches.

import SwiftUI

struct HomeDailySummaryCard: View {
    @Environment(\.glassPalette) private var palette
    @EnvironmentObject private var preferences: AppPreferencesStore
    @ObservedObject private var summaryService = MorningSummaryService.shared
    @ObservedObject private var leakPeek = LeakPeekStore.shared

    let auditEvents: [AuditEvent]
    let passThreshold: Int
    let showsReenrollmentReminder: Bool
    let onRetrainProfile: () -> Void
    let onOpenLeakPeek: () -> Void
    let onOpenSecurityActivity: () -> Void

    var body: some View {
        Group {
            if summaryService.isMinimized {
                minimizedBar
            } else {
                expandedCard
            }
        }
        .animation(.easeInOut(duration: 0.22), value: summaryService.isMinimized)
        .task(id: taskRefreshToken) {
            await summaryService.prepareDailySummaryIfNeeded(
                auditEvents: auditEvents,
                passThreshold: passThreshold,
                showsReenrollmentReminder: showsReenrollmentReminder,
                compromisedPasswordCount: compromisedCount,
                leakPeekLastScanDate: leakPeek.lastScanDate,
                aiProvider: preferences.dailySummaryAIProvider
            )
        }
    }

    private var taskRefreshToken: String {
        "\(auditEvents.count)-\(passThreshold)-\(showsReenrollmentReminder)-\(compromisedCount)-\(preferences.dailySummaryAIProvider.rawValue)"
    }

    private var compromisedCount: Int {
        leakPeek.statuses.values.filter(\.isCompromised).count
    }

    private var todayTitle: String {
        Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    // Slim bar — tap anywhere to expand again.
    private var minimizedBar: some View {
        Button {
            summaryService.isMinimized = false
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sun.horizon.fill")
                    .foregroundStyle(.yellow.opacity(0.9))

                Text("Daily Summary · \(todayTitle)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.onGlassPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.onGlassSecondary)
            }
            .padding(.horizontal, GlassTheme.padding)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                LiquidGlassSurface(cornerRadius: GlassTheme.cornerRadius)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Expand daily summary")
    }

    private var expandedCard: some View {
        HomeWidgetCard(title: nil, usesLiquidGlass: true) {
            VStack(alignment: .leading, spacing: 12) {
                headerRow

                if summaryService.isGenerating, summaryService.presentation == nil {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else if let presentation = summaryService.presentation {
                    Text(presentation.headline)
                        .font(.body)
                        .foregroundStyle(palette.onGlassPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    factsGrid(for: presentation.counts)

                    if presentation.counts.suggestedAction != .none {
                        Button(action: performSuggestedAction) {
                            Text(presentation.counts.suggestedAction.buttonTitle)
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }

                    summarySourceCaption(for: presentation)

                    testSummarySection
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            minimizeButton
                .padding(10)
        }
    }

    private var headerRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Daily Summary")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.onGlassPrimary)
            Text(todayTitle)
                .font(.caption)
                .foregroundStyle(palette.onGlassSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 36)
    }

    private var minimizeButton: some View {
        Button {
            summaryService.isMinimized = true
        } label: {
            Image(systemName: "chevron.up")
                .font(.caption.weight(.bold))
                .foregroundStyle(palette.onGlassSecondary)
                .padding(8)
                .background {
                    Circle()
                        .fill(palette.onGlassPrimary.opacity(0.08))
                }
        }
        .buttonStyle(.plain)
        .help("Minimize daily summary")
    }

    private func factsGrid(for counts: DailySummaryCounts) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            factRow(
                title: "Overnight sign-ins",
                value: DailySummaryWording.overnightSignInsFactLine(counts)
            )
            factRow(
                title: "LeakPeek",
                value: DailySummaryWording.leakPeekFactLine(counts)
            )
            factRow(
                title: "Passwords to review",
                value: DailySummaryWording.passwordsToReviewFactLine(counts.passwordsNeedingAttention)
            )
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.onGlassPrimary.opacity(0.06))
        }
    }

    private func factRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.onGlassSecondary)
                .frame(width: 132, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(palette.onGlassPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func summarySourceCaption(for presentation: DailySummaryPresentation) -> some View {
        if presentation.usedMuseAI {
            Text("Summary wording by Muse Spark")
                .font(.caption2)
                .foregroundStyle(palette.onGlassSecondary)
        } else if preferences.dailySummaryAIProvider == .local {
            Text("Summary wording: Local AI template")
                .font(.caption2)
                .foregroundStyle(palette.onGlassSecondary)
        }
    }

    /// Testing-only control to regenerate today’s headline with Local or Muse (Settings).
    private var testSummarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                Task {
                    await summaryService.regenerateDailySummaryForTesting(
                        auditEvents: auditEvents,
                        passThreshold: passThreshold,
                        showsReenrollmentReminder: showsReenrollmentReminder,
                        compromisedPasswordCount: compromisedCount,
                        leakPeekLastScanDate: leakPeek.lastScanDate,
                        aiProvider: preferences.dailySummaryAIProvider
                    )
                }
            } label: {
                HStack(spacing: 8) {
                    if summaryService.isGenerating {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    Text("Test summary · \(preferences.dailySummaryAIProvider.title)")
                        .font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(summaryService.isGenerating)

            Text("Testing only — regenerates today’s sentence with your Settings AI choice.")
                .font(.caption2)
                .foregroundStyle(palette.onGlassSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let status = summaryService.testRegenerationStatus {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(palette.onGlassSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
    }

    private func performSuggestedAction() {
        guard let action = summaryService.presentation?.counts.suggestedAction else { return }
        switch action {
        case .reviewFailedSignIns:
            onOpenSecurityActivity()
        case .retrainTypingProfile:
            onRetrainProfile()
        case .runLeakPeekScan, .reviewCompromisedPasswords:
            onOpenLeakPeek()
        case .none:
            break
        }
    }
}
