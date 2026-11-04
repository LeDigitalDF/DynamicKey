// SettingsDailySummaryAIContent.swift
// Settings controls for Daily Summary AI — Local template vs Muse Spark + Keychain API key.
// Flow: pick provider → optional masked key field → save to Keychain on commit.

import SwiftUI

struct SettingsDailySummaryAIContent: View {
    @EnvironmentObject private var preferences: AppPreferencesStore

    @State private var apiKeyDraft = ""
    @State private var showsKeyEditor = false
    @State private var statusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily Summary on Home uses counts only — never emails, site names, or passwords.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Summary AI", selection: $preferences.dailySummaryAIProvider) {
                ForEach(DailySummaryAIProvider.allCases) { provider in
                    Text(provider.title).tag(provider)
                }
            }
            .pickerStyle(.segmented)

            Text(preferences.dailySummaryAIProvider.subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if preferences.dailySummaryAIProvider == .muse {
                museKeySection
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var museKeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if MetaAPIKeychainStore.hasStoredKey, !showsKeyEditor {
                HStack {
                    Text("Meta API key")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text(maskedStoredKey)
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                }

                HStack(spacing: 10) {
                    SettingsCompactButton(title: "Replace Key", role: .primary, tint: .blue) {
                        apiKeyDraft = ""
                        showsKeyEditor = true
                    }
                    SettingsCompactButton(title: "Remove", role: .destructive) {
                        removeKey()
                    }
                }
            } else {
                SecureField("Paste Meta API key", text: $apiKeyDraft)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    SettingsCompactButton(title: "Save Key", role: .primary, tint: .blue) {
                        saveKey()
                    }
                    if showsKeyEditor {
                        SettingsCompactButton(title: "Cancel", role: .secondary) {
                            showsKeyEditor = false
                            apiKeyDraft = ""
                        }
                    }
                }
            }
        }
    }

    private var maskedStoredKey: String {
        guard let key = MetaAPIKeychainStore.loadAPIKey() else {
            return String(repeating: "•", count: 12)
        }
        return MetaAPIKeychainStore.maskedDisplay(for: key)
    }

    private func saveKey() {
        do {
            try MetaAPIKeychainStore.saveAPIKey(apiKeyDraft)
            apiKeyDraft = ""
            showsKeyEditor = false
            statusMessage = "API key saved in Keychain."
            MorningSummaryService.shared.clearCacheForTesting()
        } catch {
            statusMessage = "Could not save API key."
        }
    }

    private func removeKey() {
        do {
            try MetaAPIKeychainStore.deleteAPIKey()
            statusMessage = "API key removed."
            MorningSummaryService.shared.clearCacheForTesting()
        } catch {
            statusMessage = "Could not remove API key."
        }
    }
}
