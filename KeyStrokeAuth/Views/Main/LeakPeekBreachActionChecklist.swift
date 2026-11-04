// LeakPeekBreachActionChecklist.swift
// Expandable per-email breach checklist with Fix Now, Ignore, and Mark as Resolved actions.
// Flow: tap email → list services → Fix Now if saved in DynamicKey → dismiss old breaches.

import AppKit
import SwiftUI

struct LeakPeekBreachActionChecklist: View {
    let credentials: [SiteCredential]

    @ObservedObject private var identityStore = LeakPeekIdentityStore.shared
    @State private var expandedEmail: String?

    var body: some View {
        VStack(spacing: 10) {
            ForEach(identityStore.activeCompromisedStatuses()) { result in
                emailSection(result)
            }
        }
    }

    private func emailSection(_ result: LeakPeekIdentityStatus) -> some View {
        let isExpanded = expandedEmail == result.email
        let activeBreaches = identityStore.activeBreachNames(for: result)

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    expandedEmail = isExpanded ? nil : result.email
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isExpanded ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                        .foregroundStyle(.orange)

                    Text(result.email)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text("\(activeBreaches.count) service\(activeBreaches.count == 1 ? "" : "s")")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                .padding(12)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(activeBreaches, id: \.self) { breachName in
                        breachServiceRow(email: result.email, breachName: breachName)
                    }

                    Button {
                        identityStore.markEmailResolved(result.email)
                        if expandedEmail == result.email {
                            expandedEmail = nil
                        }
                    } label: {
                        Label("Mark as Resolved", systemImage: "checkmark.circle")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: GlassTheme.cornerRadius - 4, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        }
        .overlay {
            RoundedRectangle(cornerRadius: GlassTheme.cornerRadius - 4, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.2), lineWidth: 1)
        }
    }

    private func breachServiceRow(email: String, breachName: String) -> some View {
        let savedCredential = LeakPeekBreachCredentialMatcher.matchingCredential(
            breachName: breachName,
            in: credentials
        )

        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(breachName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Text(savedCredential == nil ? "Not saved in DynamicKey" : "Saved in DynamicKey")
                    .font(.caption2)
                    .foregroundStyle(savedCredential == nil ? .secondary : Color.green.opacity(0.85))
            }

            Spacer(minLength: 8)

            if let credential = savedCredential {
                Button {
                    openFixNow(for: credential)
                } label: {
                    Text("Fix Now")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(GlassTheme.buttonLabelColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background {
                            Capsule(style: .continuous)
                                .fill(Color(red: 0.95, green: 0.28, blue: 0.24))
                        }
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    identityStore.dismissBreach(email: email, breachName: breachName)
                } label: {
                    Text("Ignore")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background {
                            Capsule(style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
    }

    private func openFixNow(for credential: SiteCredential) {
        guard let url = SitePasswordChangeURLResolver.preferredFixURL(for: credential.origin) else { return }
        NSWorkspace.shared.open(url)
    }
}
