// SettingsAccountCardContent.swift
// Account summary in Settings — one row: current name (left), edit field (middle), Save (right).
// Flow: read AccountProfileStore → edit in middle field → Save updates display name via SwiftData / iCloud.

import SwiftUI

struct SettingsAccountCardContent: View {
    @EnvironmentObject private var accountProfile: AccountProfileStore
    @Environment(\.glassPalette) private var palette

    @FocusState private var isDisplayNameFocused: Bool
    @State private var displayNameDraft: String = ""
    @State private var statusMessage: String?

    private let displayNameColumnWidth: CGFloat = 108
    private let sectionSpacing: CGFloat = 20
    private let fieldToSaveSpacing: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !accountProfile.isCloudSyncAvailable {
                iCloudSyncDisabledBadge
            }

            HStack(alignment: .top, spacing: sectionSpacing) {
                displayNameColumn
                changeNameColumn
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(palette.onGlassSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            displayNameDraft = accountProfile.displayName
            accountProfile.refreshCloudSyncAvailability()
        }
    }

    // Left — current saved display name as plain text (not editable here).
    private var displayNameColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Display Name")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.onGlassSecondary)

            Text(accountProfile.resolvedDisplayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(width: displayNameColumnWidth, alignment: .leading)
    }

    private var isSaveDisabled: Bool {
        displayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines) == accountProfile.displayName
    }

    // Middle + right — caption, long field, and Save as the third section on one row.
    private var changeNameColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Change Name")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.onGlassSecondary)

            HStack(alignment: .top, spacing: fieldToSaveSpacing) {
                GlassCompactInputField(
                    text: $displayNameDraft,
                    placeholder: "New display name",
                    isFocused: $isDisplayNameFocused,
                    cornerRadius: 12,
                    onSubmit: saveDisplayName
                )
                .frame(maxWidth: .infinity)

                Button(action: saveDisplayName) {
                    Text("Save")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GlassTheme.buttonLabelColor)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 16)
                        .glassEffect()
                        .overlay {
                            LiquidGlassButtonSparkleBackground()
                                .blendMode(.plusLighter)
                                .opacity(1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Save")
                .disabled(isSaveDisabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var iCloudSyncDisabledBadge: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.onGlassSecondary)
            Text("iCloud sync disabled. Your display name stays on this Mac only.")
                .font(.caption)
                .foregroundStyle(palette.onGlassSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.10))
        }
    }

    private func saveDisplayName() {
        accountProfile.updateDisplayName(displayNameDraft)
        displayNameDraft = accountProfile.displayName
        statusMessage = displayNameDraft.isEmpty
            ? "Using \(accountProfile.resolvedDisplayName) until you set a name."
            : "Name saved."
    }
}
