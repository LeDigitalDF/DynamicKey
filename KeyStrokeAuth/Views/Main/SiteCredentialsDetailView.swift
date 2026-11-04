// SiteCredentialsDetailView.swift
// Website credentials — widget card grid (2 per row) matching the Home dashboard style.
// Flow: key icon watermark → title header → badge legend card → credential cards.

import SwiftUI

struct SiteCredentialsDetailView: View {
    @Environment(\.glassPalette) private var palette

    let credentials: [SiteCredential]
    var isSlideOver: Bool = false
    let onAddSiteCredential: (String, String, String, Bool) -> Void
    let onDeleteSiteCredential: (UUID) -> Void

    @State private var newSiteOrigin = ""
    @State private var newSiteUsername = ""
    @State private var revealedCredentialIDs: Set<UUID> = []
    @State private var isManualCredentialFlipped = false

    private var contentMaxWidth: CGFloat {
        isSlideOver ? 520 : 820
    }

    private var gridColumns: [GridItem] {
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
                DetailPaneSectionIconWatermarkBackground(section: .credentials)
            }

            detailScrollContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .scrollDisabled(isManualCredentialFlipped)
    }

    private var detailScrollContent: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: GlassTheme.sectionSpacing) {
                MainDetailSectionHeader(
                    section: .credentials,
                    subtitle: "Saved site logins for browser autofill.",
                    showsSectionIcon: false,
                    indentsForBackButton: !isSlideOver
                )

                badgeLegendCard

                credentialCardGrid
            }
            .padding(.horizontal, isSlideOver ? 16 : 24)
            .padding(.top, isSlideOver ? 4 : 10)
            .padding(.bottom, 24)
            .frame(maxWidth: contentMaxWidth, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollContentBackground(.hidden)
    }

    private var badgeLegendCard: some View {
        HomeWidgetCard(title: "Badge meanings", usesLiquidGlass: true) {
            VStack(alignment: .leading, spacing: 10) {
                Text("After a successful rhythm verify, DynamicKey auto-generates a strong 24-character site password per website.")
                    .font(.caption)
                    .foregroundStyle(palette.onGlassSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                badgeLegendRow(
                    label: "Generated",
                    detail: "Mac created this password after rhythm verify."
                )
                badgeLegendRow(
                    label: "Manual",
                    detail: "You saved this yourself (import or test)."
                )
            }
        }
    }

    private func badgeLegendRow(label: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background((label == "Generated" ? Color.accentColor : Color.orange).opacity(0.18))
                .clipShape(Capsule())

            Text(detail)
                .font(.caption)
                .foregroundStyle(palette.onGlassSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // Two-column card grid — saved credentials plus the manual flip card.
    private var credentialCardGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 16) {
            if credentials.isEmpty {
                HomeWidgetCard(usesLiquidGlass: true) {
                    Text("No site credentials saved yet.")
                        .font(.subheadline)
                        .foregroundStyle(palette.onGlassSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                }
            } else {
                ForEach(credentials) { credential in
                    SiteCredentialCard(
                        credential: credential,
                        isRevealed: revealedCredentialIDs.contains(credential.id),
                        onToggleReveal: {
                            if revealedCredentialIDs.contains(credential.id) {
                                revealedCredentialIDs.remove(credential.id)
                            } else {
                                revealedCredentialIDs.insert(credential.id)
                            }
                        },
                        onRemove: { onDeleteSiteCredential(credential.id) }
                    )
                }
            }

            ManualCredentialFlipCard(
                origin: $newSiteOrigin,
                username: $newSiteUsername,
                onSave: saveManualCredential,
                onFlipChanged: { isManualCredentialFlipped = $0 }
            )
            .frame(maxWidth: .infinity, minHeight: 220)
        }
    }

    private func saveManualCredential(origin: String, username: String, password: String) {
        onAddSiteCredential(origin, username, password, false)
        newSiteOrigin = ""
        newSiteUsername = ""
    }
}
