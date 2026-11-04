// SecurityActivityView.swift
// Popup screen showing the local security audit log for the current user.

import SwiftUI

struct SecurityActivityView: View {
    @Environment(\.glassPalette) private var palette

    let auditEvents: [AuditEvent]
    let onClose: () -> Void
    let onClearAuditLog: () -> Void

    var body: some View {
        ZStack {
            DynamicKeyDashboardBackground()

            VStack(spacing: GlassTheme.sectionSpacing) {
                PhaseHeader(
                    title: "Security Activity",
                    subtitle: "Review sign-in attempts and profile changes on this Mac.",
                    systemImage: "shield.checkered"
                )

                GlassPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Audit log")
                                .font(.headline)

                            Spacer()

                            if !auditEvents.isEmpty {
                                GlassTextButton(title: "Clear", action: onClearAuditLog)
                            }
                        }

                        if auditEvents.isEmpty {
                            Text("No security events recorded yet.")
                                .font(.subheadline)
                                .foregroundStyle(palette.onGlassSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 12) {
                                    ForEach(auditEvents) { event in
                                        auditEventRow(event)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .frame(maxHeight: 360)
                        }
                    }
                    .padding(GlassTheme.padding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GlassButton(
                    title: "Close",
                    role: .secondary,
                    expandsFullWidth: false,
                    submitOnReturn: true,
                    action: onClose
                )
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(maxWidth: GlassTheme.maxContentWidth + 80)
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 520, minHeight: 480)
    }

    private func auditEventRow(_ event: AuditEvent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(event.displayTitle)
                .font(.subheadline)
            Text(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(palette.onGlassSecondary)
            if let detail = event.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(palette.onGlassSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
