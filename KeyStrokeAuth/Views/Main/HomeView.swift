// HomeView.swift
// Post-unlock dashboard — widget cards for status, score, stats, activity, and quick actions.
// Flow: static brand watermark → centered header (title only) → scrollable widget cards.

import SwiftUI

struct HomeView: View {
    @Environment(\.glassPalette) private var palette
    @ObservedObject private var safeModeStore = SafeModeStore.shared

    let lastRhythmMatchPercentage: Int
    let passThreshold: Int
    let protectedSiteCount: Int
    let pairedExtensionCount: Int
    let pairedExtensionClients: [PairedExtensionClient]
    let isExtensionAPIRunning: Bool
    let showsReenrollmentReminder: Bool
    let auditEvents: [AuditEvent]
    let siteCredentials: [SiteCredential]
    let onOpenBrowserExtension: () -> Void
    let onRetrainProfile: () -> Void
    let onOpenLeakPeek: () -> Void
    let onOpenSecurityActivity: () -> Void

    private var securityScore: Int {
        HomeDashboardModel.securityScore(
            isExtensionAPIRunning: isExtensionAPIRunning,
            pairedExtensionCount: pairedExtensionCount,
            protectedSiteCount: protectedSiteCount,
            showsReenrollmentReminder: showsReenrollmentReminder,
            lastRhythmMatchPercentage: lastRhythmMatchPercentage,
            passThreshold: passThreshold
        )
    }

    private var recentActivity: [HomeActivityRow] {
        HomeDashboardModel.recentActivity(from: auditEvents)
    }

    private var lastLoginDate: Date? {
        HomeDashboardModel.lastLoginDate(from: auditEvents)
    }

    var body: some View {
        ZStack {
            DetailPaneBrandWatermarkBackground()

            homeScrollContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // Scrollable dashboard cards — transparent scroll chrome so the watermark shows through.
    private var homeScrollContent: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: GlassTheme.sectionSpacing) {
                header

                HomeDailySummaryCard(
                    auditEvents: auditEvents,
                    passThreshold: passThreshold,
                    showsReenrollmentReminder: showsReenrollmentReminder,
                    onRetrainProfile: onRetrainProfile,
                    onOpenLeakPeek: onOpenLeakPeek,
                    onOpenSecurityActivity: onOpenSecurityActivity
                )

                systemStatusCard

                HStack(alignment: .top, spacing: 16) {
                    securityScoreCard
                    leakPeekCard
                }
                .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 16) {
                    quickStatsCard
                    recentActivityCard
                }
                .fixedSize(horizontal: false, vertical: true)

                quickActionsCard
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 24)
            .frame(maxWidth: 820, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollContentBackground(.hidden)
    }

    private var header: some View {
        MainDetailSectionHeader(
            section: .home,
            subtitle: safeModeStore.isActive
                ? "Safe Mode active — \(safeModeStore.formattedRemainingTime) remaining (Mac + extension)."
                : "You're unlocked and ready.",
            showsSectionIcon: false
        )
    }

    // TOP — unlocked state + extension health (actions live in Quick Actions below).
    // Liquid Glass: all Home dashboard cards use the real NSGlassEffectView material.
    private var systemStatusCard: some View {
        HomeWidgetCard(title: "System Status", usesLiquidGlass: true) {
            VStack(alignment: .leading, spacing: 12) {
                if safeModeStore.isActive {
                    HStack(spacing: 8) {
                        Image(systemName: "touchid")
                            .foregroundStyle(.orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Safe Mode active")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.orange)

                            Text("Mac + extension · \(safeModeStore.formattedRemainingTime) remaining")
                                .font(.caption)
                                .foregroundStyle(palette.onGlassSecondary)
                                .monospacedDigit()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.orange.opacity(0.12))
                    }
                }

                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Unlocked", systemImage: "checkmark.seal.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.green)

                        Text("Master password and typing rhythm verified on this Mac.")
                            .font(.caption)
                            .foregroundStyle(palette.onGlassSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 8) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(isExtensionAPIRunning ? Color.green : Color.red)
                                .frame(width: 8, height: 8)

                            Text(isExtensionAPIRunning ? "Extension connected" : "Extension offline")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(isExtensionAPIRunning ? .green : .red)
                        }

                        Text("\(pairedExtensionCount) paired browser\(pairedExtensionCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(palette.onGlassSecondary)
                    }
                }
            }
        }
    }

    // MIDDLE LEFT — circular security score ring.
    private var securityScoreCard: some View {
        HomeWidgetCard(title: "Security Score", usesLiquidGlass: true) {
            VStack(spacing: 18) {
                securityScoreRing

                Text(securityScoreCaption)
                    .font(.caption)
                    .foregroundStyle(palette.onGlassSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var securityScoreRing: some View {
        let progress = CGFloat(securityScore) / 100
        // Gradient angles follow the untrimmed circle (trim starts at 3 o'clock); -90° rotation puts start at 12 o'clock.
        let arcGradient = AngularGradient(
            colors: [.green, .blue],
            center: .center,
            startAngle: .degrees(0),
            endAngle: .degrees(360 * Double(progress))
        )

        return ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 12)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    arcGradient,
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: securityScore)

            VStack(spacing: 2) {
                Text("\(securityScore)%")
                    .font(.title2.weight(.bold))
                Text("Secure")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.onGlassSecondary)
            }
        }
        .frame(width: 128, height: 128)
        .frame(maxWidth: .infinity)
    }

    // MIDDLE RIGHT — LeakPeek donut summary + Scan Now.
    private var leakPeekCard: some View {
        HomeLeakPeekCard(
            credentials: siteCredentials,
            onOpenLeakPeek: onOpenLeakPeek
        )
    }

    private var securityScoreCaption: String {
        if securityScore >= 85 {
            return "Your setup looks strong. Retrain your typing profile if it has been a while."
        }
        if securityScore >= 65 {
            return "You're on track. Connect a browser and add more protected sites."
        }
        return "Pair your browser extension and save site passwords to raise your score."
    }

    // MIDDLE RIGHT — protected sites and last login.
    private var quickStatsCard: some View {
        HomeWidgetCard(title: "Quick Stats", usesLiquidGlass: true) {
            VStack(alignment: .leading, spacing: 14) {
                statRow(
                    icon: "globe.badge.chevron.backward",
                    tint: .green,
                    title: "Protected Sites",
                    value: "\(protectedSiteCount)"
                )

                Divider()

                statRow(
                    icon: "clock.fill",
                    tint: .blue,
                    title: "Last Login",
                    value: formattedLastLogin
                )

                if lastRhythmMatchPercentage > 0 {
                    Divider()

                    statRow(
                        icon: "waveform.path.ecg",
                        tint: .orange,
                        title: "Last Rhythm Match",
                        value: "\(lastRhythmMatchPercentage)%"
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statRow(icon: String, tint: Color, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(palette.onGlassSecondary)
                Text(value)
                    .font(.title3.weight(.semibold))
            }

            Spacer(minLength: 0)
        }
    }

    private var formattedLastLogin: String {
        guard let lastLoginDate else { return "Not recorded yet" }
        return lastLoginDate.formatted(date: .abbreviated, time: .shortened)
    }

    // BOTTOM LEFT — recent sign-in / verify attempts.
    private var recentActivityCard: some View {
        HomeWidgetCard(title: "Recent Activity", usesLiquidGlass: true) {
            if recentActivity.isEmpty {
                Text("No security activity recorded yet.")
                    .font(.caption)
                    .foregroundStyle(palette.onGlassSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(recentActivity) { row in
                        activityRow(row)

                        if row.id != recentActivity.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func activityRow(_ row: HomeActivityRow) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: activityIcon(for: row))
                .font(.caption)
                .foregroundStyle(activityIconColor(for: row))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.site)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Text(row.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(palette.onGlassSecondary)
            }

            Spacer(minLength: 0)

            if let match = row.matchPercentage {
                Text("\(match)%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(row.succeeded ? .green : .orange)
            }
        }
    }

    private func activityIcon(for row: HomeActivityRow) -> String {
        if row.isDynamicShield {
            return "shield.lefthalf.filled"
        }
        return row.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private func activityIconColor(for row: HomeActivityRow) -> Color {
        if row.isDynamicShield {
            return row.succeeded ? .cyan : .orange
        }
        return row.succeeded ? .green : .red
    }

    // BOTTOM — emergency lock + shortcut grid.
    private var quickActionsCard: some View {
        HomeQuickActionsCard(
            showsReenrollmentReminder: showsReenrollmentReminder,
            isExtensionAPIRunning: isExtensionAPIRunning,
            pairedExtensionClients: pairedExtensionClients,
            onUpdateTypingRhythm: onRetrainProfile,
            onOpenBrowserExtension: onOpenBrowserExtension
        )
    }
}
