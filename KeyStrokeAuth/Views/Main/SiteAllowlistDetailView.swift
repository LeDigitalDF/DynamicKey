// SiteAllowlistDetailView.swift
// Allowed List + DynamicShield — twin info cards and twin list columns, flip add card below.
// Flow: globe icon watermark → title header → info cards → lists → manual flip add cards.

import SwiftUI

private enum PolicyListPanelMetrics {
    /// Default visible rows — empty panels match this height; more rows scroll inside the card.
    static let visibleRows = 5
    static let rowHeight: CGFloat = 56
    static var panelHeight: CGFloat { CGFloat(visibleRows) * rowHeight }
}

struct SiteAllowlistDetailView: View {
    @Environment(\.glassPalette) private var palette

    let allowedOrigins: [String]
    let disabledAllowlistOrigins: [String]
    let trustedSenderDomains: [String]
    let disabledTrustedSenderDomains: [String]
    var isSlideOver: Bool = false
    let onAddAllowedOrigin: (String) -> Void
    let onRemoveAllowedOrigin: (String) -> Void
    let onToggleOriginAllowed: (String, Bool) -> Void
    let onRemoveTrustedSenderDomain: (String) -> Void
    let onToggleTrustedSenderDomain: (String, Bool) -> Void
    let onAddTrustedSenderDomain: (String) -> Void

    private var contentMaxWidth: CGFloat {
        isSlideOver ? 520 : 920
    }

    private var twinColumns: [GridItem] {
        if isSlideOver {
            return [GridItem(.flexible(), spacing: 16)]
        }
        return [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16),
        ]
    }

    var body: some View {
        ZStack {
            if !isSlideOver {
                DetailPaneSectionIconWatermarkBackground(section: .allowlist)
            }

            detailScrollContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
    }

    private var detailScrollContent: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: GlassTheme.sectionSpacing) {
                MainDetailSectionHeader(
                    section: .allowlist,
                    subtitle: "Manage website access and DynamicShield trusted email senders.",
                    showsSectionIcon: false,
                    indentsForBackButton: !isSlideOver
                )

                LazyVGrid(columns: twinColumns, alignment: .leading, spacing: 16) {
                    allowedListInfoCard
                    dynamicShieldInfoCard
                }

                LazyVGrid(columns: twinColumns, alignment: .leading, spacing: 16) {
                    allowlistGroupedSection
                    dynamicShieldGroupedSection
                }

                LazyVGrid(columns: twinColumns, alignment: .leading, spacing: 16) {
                    ManualAllowlistFlipCard(onAdd: onAddAllowedOrigin)
                        .frame(maxWidth: .infinity, minHeight: 220)

                    ManualDynamicShieldFlipCard(onAdd: onAddTrustedSenderDomain)
                        .frame(maxWidth: .infinity, minHeight: 220)
                }
            }
            .padding(.horizontal, isSlideOver ? 16 : 24)
            .padding(.top, isSlideOver ? 4 : 10)
            .padding(.bottom, 24)
            .frame(maxWidth: contentMaxWidth, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollContentBackground(.hidden)
    }

    private var allowedListInfoCard: some View {
        HomeWidgetCard(title: "Connected Sites", usesLiquidGlass: true) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Only websites on your Protected Websites list can use the extension login popup for rhythm verify and autofill. Add a site below or from the extension when prompted. Subdomains share one entry (e.g. accounts.spotify.com → spotify.com).")
                    .font(.caption)
                    .foregroundStyle(palette.onGlassSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                statusLegendRow(allowedLabel: "Protected", deniedLabel: "Paused")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var dynamicShieldInfoCard: some View {
        HomeWidgetCard(title: "DynamicShield", usesLiquidGlass: true) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Scans webmail for phishing patterns. Trusted senders skip future warnings. Add senders manually below or from a DynamicShield warning in the extension.")
                    .font(.caption)
                    .foregroundStyle(palette.onGlassSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                statusLegendRow(allowedLabel: "Trusted", deniedLabel: "Not trusted")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func statusLegendRow(allowedLabel: String, deniedLabel: String) -> some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                AllowlistStatusDot(isAllowed: true)
                Text(allowedLabel)
                    .font(.caption2)
                    .foregroundStyle(palette.onGlassSecondary)
            }

            HStack(spacing: 6) {
                AllowlistStatusDot(isAllowed: false)
                Text(deniedLabel)
                    .font(.caption2)
                    .foregroundStyle(palette.onGlassSecondary)
            }
        }
    }

    private var allowlistGroupedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Protected Websites")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.onGlassSecondary)

            policyListPanel(
                isEmpty: allowedOrigins.isEmpty,
                itemCount: allowedOrigins.count,
                emptyMessage: "No protected websites yet. Add a site below so the extension can show the login popup in its password field. Sites not listed here will never offer master password sign-in."
            ) {
                ForEach(allowedOrigins, id: \.self) { origin in
                    allowlistRow(origin: origin)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            deleteAllowlistAction(for: origin)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            deleteAllowlistAction(for: origin)
                        }
                }
                .onDelete(perform: deleteOrigins)
            }
            .background {
                LiquidGlassSurface(cornerRadius: GlassTheme.cornerRadius)
            }
            .clipShape(RoundedRectangle(cornerRadius: GlassTheme.cornerRadius, style: .continuous))
        }
        .id("allowlist-list-\(disabledAllowlistOrigins.joined(separator: "|"))")
    }

    private var dynamicShieldGroupedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trusted senders")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.onGlassSecondary)

            policyListPanel(
                isEmpty: trustedSenderDomains.isEmpty,
                itemCount: trustedSenderDomains.count,
                emptyMessage: "No trusted senders yet. Add one below or mark a sender as safe from a DynamicShield warning in the extension."
            ) {
                ForEach(trustedSenderDomains, id: \.self) { domain in
                    trustedSenderRow(domain: domain)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            deleteTrustedSenderAction(for: domain)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            deleteTrustedSenderAction(for: domain)
                        }
                }
                .onDelete(perform: deleteTrustedSenders)
            }
            .background {
                LiquidGlassSurface(cornerRadius: GlassTheme.cornerRadius)
            }
            .clipShape(RoundedRectangle(cornerRadius: GlassTheme.cornerRadius, style: .continuous))
        }
        .id("dynamicshield-list-\(disabledTrustedSenderDomains.joined(separator: "|"))")
    }

    /// Fixed-height glass list shell — empty state fills five rows; longer lists scroll inside only.
    private func policyListPanel<Rows: View>(
        isEmpty: Bool,
        itemCount: Int,
        emptyMessage: String,
        @ViewBuilder rows: () -> Rows
    ) -> some View {
        Group {
            if isEmpty {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(palette.onGlassSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 12)
            } else {
                Form {
                    Section {
                        rows()
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .backgroundStyle(.clear)
                .scrollDisabled(itemCount <= PolicyListPanelMetrics.visibleRows)
            }
        }
        .frame(height: PolicyListPanelMetrics.panelHeight)
        .frame(maxWidth: .infinity, alignment: .top)
        .clipped()
        .background { AllowlistFormBackgroundClearer() }
    }

    private func allowlistRow(origin: String) -> some View {
        let allowed = isOriginEnabled(origin)

        return HStack(alignment: .top, spacing: 12) {
            AllowlistStatusDot(isAllowed: allowed, animatesOnToggle: true)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                Text(displayOrigin(origin))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(formattedAllowedDate(for: origin))
                    .font(.caption)
                    .foregroundStyle(palette.onGlassSecondary)
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onToggleOriginAllowed(origin, !allowed)
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Tap to toggle allowed or not allowed. Swipe to delete.")
    }

    private func trustedSenderRow(domain: String) -> some View {
        let trusted = isSenderDomainEnabled(domain)

        return HStack(alignment: .top, spacing: 12) {
            AllowlistStatusDot(isAllowed: trusted, animatesOnToggle: true)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                Text(displaySenderDomain(domain))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(formattedTrustedDate(for: domain))
                    .font(.caption)
                    .foregroundStyle(palette.onGlassSecondary)
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onToggleTrustedSenderDomain(domain, !trusted)
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Tap to toggle trusted or not trusted. Swipe to delete.")
    }

    private func deleteAllowlistAction(for origin: String) -> some View {
        Button(role: .destructive) {
            onRemoveAllowedOrigin(origin)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func deleteTrustedSenderAction(for domain: String) -> some View {
        Button(role: .destructive) {
            onRemoveTrustedSenderDomain(domain)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func deleteOrigins(at offsets: IndexSet) {
        for index in offsets {
            onRemoveAllowedOrigin(allowedOrigins[index])
        }
    }

    private func deleteTrustedSenders(at offsets: IndexSet) {
        for index in offsets {
            onRemoveTrustedSenderDomain(trustedSenderDomains[index])
        }
    }

    private func displayOrigin(_ origin: String) -> String {
        let normalized = SiteCredential.normalizeOrigin(origin)
        guard !normalized.isEmpty else { return origin }
        return normalized
    }

    private func displaySenderDomain(_ domain: String) -> String {
        let normalized = DynamicShieldPolicyStore.normalizeSenderDomain(domain)
        guard !normalized.isEmpty else { return domain }
        return "@\(normalized)"
    }

    private func isOriginEnabled(_ origin: String) -> Bool {
        !disabledAllowlistOrigins.contains { SiteCredential.sameSiteGroup($0, origin) }
    }

    private func isSenderDomainEnabled(_ domain: String) -> Bool {
        !disabledTrustedSenderDomains.contains {
            DynamicShieldPolicyStore.sameSenderDomain($0, domain)
        }
    }

    private func formattedAllowedDate(for origin: String) -> String {
        let date = SitePolicyStore.shared.allowedAt(for: origin) ?? Date()
        return Self.listDateFormatter.string(from: date)
    }

    private func formattedTrustedDate(for domain: String) -> String {
        let date = DynamicShieldPolicyStore.shared.trustedAt(for: domain) ?? Date()
        return Self.listDateFormatter.string(from: date)
    }

    private static let listDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
