// SecurityActivityTimelineView.swift
// Vertical security activity timeline — newest at top, colored dots per event type.
// Flow: empty state or centered stacked rows → hover dot expands detail popover.

import SwiftUI

struct SecurityActivityTimelineView: View {
    let events: [AuditEvent]
    let emptyMessage: String
    let period: SecurityActivityPeriod
    var textColor: Color? = nil

    private var resolvedTextColor: Color {
        textColor ?? period.timelineTextColor
    }

    var body: some View {
        HStack {
            Spacer(minLength: 0)

            Group {
                if events.isEmpty {
                    Text(emptyMessage)
                        .font(.subheadline)
                        .foregroundStyle(resolvedTextColor.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                            SecurityActivityTimelineRow(
                                event: event,
                                period: period,
                                textColor: resolvedTextColor,
                                isLast: index == events.count - 1
                            )
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }
}

// Single timeline row — colored dot, connector line, period-tinted summary text, hover popover.
private struct SecurityActivityTimelineRow: View {
    let event: AuditEvent
    let period: SecurityActivityPeriod
    var textColor: Color? = nil
    let isLast: Bool

    @State private var isHovered = false

    private let dotSize: CGFloat = 12
    private let connectorWidth: CGFloat = 2
    private let rowSpacing: CGFloat = 20

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            timelineColumn
                .onHover { isHovered = $0 }
                .popover(isPresented: $isHovered, arrowEdge: .leading) {
                    SecurityActivityTimelineDetailPopover(event: event)
                }

            summaryColumn
                .padding(.bottom, isLast ? 0 : rowSpacing)
        }
    }

    // Dot and vertical connector tinted by this event's category color.
    private var timelineColumn: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(event.timelineAccentColor)
                .frame(width: dotSize, height: dotSize)
                .shadow(color: event.timelineAccentColor.opacity(0.55), radius: 5)
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                }
                .padding(6)
                .contentShape(Rectangle())

            if !isLast {
                Rectangle()
                    .fill(event.timelineAccentColor.opacity(0.45))
                    .frame(width: connectorWidth)
                    .frame(minHeight: rowSpacing + 4)
            }
        }
        .frame(width: dotSize + 12)
    }

    private var resolvedTextColor: Color {
        textColor ?? period.timelineTextColor
    }

    // Compact label tinted by the selected period or category filter.
    private var summaryColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.caption.weight(.semibold))
                .foregroundStyle(resolvedTextColor.opacity(0.72))

            Text(event.timelineSummary)
                .font(.subheadline)
                .foregroundStyle(resolvedTextColor)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// Expanded detail card shown when hovering a timeline dot.
private struct SecurityActivityTimelineDetailPopover: View {
    let event: AuditEvent

    @Environment(\.glassPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(event.timelineAccentColor)
                    .frame(width: 10, height: 10)

                Text(event.displayTitle)
                    .font(.headline)
            }

            Text(event.timestamp.formatted(date: .abbreviated, time: .standard))
                .font(.caption)
                .foregroundStyle(.secondary)

            if let detail = event.detail, !detail.isEmpty {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(palette.onGlassPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(minWidth: 240, maxWidth: 320, alignment: .leading)
    }
}
