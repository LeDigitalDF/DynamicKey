// HomeLeakPeekCard.swift
// Home dashboard LeakPeek summary — donut ring + compact Quick Scan button in the center.
// Flow: ring shows safe / compromised / pending → Quick Scan checks saved passwords on this Mac.

import SwiftUI

struct HomeLeakPeekCard: View {
    @Environment(\.glassPalette) private var palette

    let credentials: [SiteCredential]
    let onOpenLeakPeek: () -> Void

    @ObservedObject private var leakPeek = LeakPeekStore.shared

    private var summary: LeakPeekRingSummary {
        LeakPeekRingSummary.from(credentials: credentials) { leakPeek.siteStatus(for: $0) }
    }

    var body: some View {
        HomeWidgetCard(title: "LeakPeek", usesLiquidGlass: true) {
            VStack(spacing: 12) {
                if credentials.isEmpty {
                    emptyState
                } else {
                    ringAndScanButton

                    countLabels

                    footerRow
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.title2)
                .foregroundStyle(MainSidebarSection.leakPeek.accentColor.opacity(0.8))

            Text("Add website credentials to check them against known breaches.")
                .font(.caption)
                .foregroundStyle(palette.onGlassSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var ringAndScanButton: some View {
        ZStack {
            LeakPeekDonutRing(summary: summary)
                .frame(width: 132, height: 132)

            LeakPeekRoundActionButton(
                title: "Quick Scan",
                subtitle: "",
                systemImage: "bolt.shield.fill",
                layout: .compact,
                sparklePalette: .indigo,
                isLoading: leakPeek.isScanning,
                isEnabled: !credentials.isEmpty
            ) {
                Task {
                    await leakPeek.scan(credentials: credentials)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
    }

    private var countLabels: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Saved passwords:")
                .foregroundStyle(palette.onGlassSecondary)

            HStack(spacing: 0) {
                countChip(value: summary.safe, label: "Safe", color: Color(red: 0.18, green: 0.78, blue: 0.42))

                if summary.compromised > 0 {
                    Text(" • ")
                        .fontWeight(.semibold)
                        .foregroundStyle(palette.onGlassSecondary)
                    countChip(
                        value: summary.compromised,
                        label: "Compromised",
                        color: Color(red: 0.95, green: 0.45, blue: 0.22)
                    )
                }

                if summary.pending > 0 {
                    Text(" • ")
                        .fontWeight(.semibold)
                        .foregroundStyle(palette.onGlassSecondary)
                    countChip(value: summary.pending, label: "Pending", color: .secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lineLimit(2)
        .minimumScaleFactor(0.85)
    }

    private func countChip(value: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .foregroundStyle(palette.onGlassSecondary)
        }
    }

    private var footerRow: some View {
        HStack(spacing: 8) {
            Text(lastScannedCaption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button("Details", action: onOpenLeakPeek)
                .font(.caption2.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(MainSidebarSection.leakPeek.accentColor)
        }
    }

    private var lastScannedCaption: String {
        guard let date = leakPeek.lastScanDate else {
            return "Not scanned yet"
        }
        return "Last scanned \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}

// Segmented donut ring — green safe, orange compromised, gray pending.
private struct LeakPeekDonutRing: View {
    let summary: LeakPeekRingSummary

    private let lineWidth: CGFloat = 13

    private struct Segment: Identifiable {
        let id: Int
        let start: Double
        let fraction: Double
        let color: Color
    }

    private var segments: [Segment] {
        let total = max(summary.total, 1)
        let specs: [(Int, Color)] = [
            (summary.safe, Color(red: 0.18, green: 0.78, blue: 0.42)),
            (summary.compromised, Color(red: 0.95, green: 0.45, blue: 0.22)),
            (summary.pending, Color.secondary.opacity(0.38)),
        ]

        var cursor = 0.0
        var result: [Segment] = []
        var index = 0

        for (count, color) in specs where count > 0 {
            let fraction = Double(count) / Double(total)
            result.append(Segment(id: index, start: cursor, fraction: fraction, color: color))
            cursor += fraction
            index += 1
        }

        if result.isEmpty {
            return [Segment(id: 0, start: 0, fraction: 1, color: Color.secondary.opacity(0.25))]
        }

        return result
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.07), lineWidth: lineWidth)

            ForEach(segments) { segment in
                Circle()
                    .trim(from: segment.start, to: segment.start + segment.fraction)
                    .stroke(
                        segment.color,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.45), value: summary)
            }
        }
    }
}
