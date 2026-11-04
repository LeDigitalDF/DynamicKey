// MetaAPIKeychainStore.swift
// Stores the Meta Model API key in the macOS Keychain (never UserDefaults or source).
// Flow: Settings secure field → save → masked display; MorningSummaryService reads for Muse calls.

import Foundation

enum MetaAPIKeychainStore {
    private static let keychain = KeychainService(
        service: "LeDigital.KeyStrokeAuth",
        account: "meta.model.api.key"
    )

    static func loadAPIKey() -> String? {
        guard let data = keychain.load(),
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else {
            return nil
        }
        return key
    }

    static func saveAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try keychain.delete()
            return
        }
        guard let data = trimmed.data(using: .utf8) else { return }
        try keychain.save(data: data)
    }

    static func deleteAPIKey() throws {
        try keychain.delete()
    }

    /// Masked label for Settings — same idea as hiding a long pairing token.
    static func maskedDisplay(for key: String) -> String {
        guard key.count > 4 else { return String(repeating: "•", count: 8) }
        let suffix = key.suffix(4)
        return String(repeating: "•", count: 12) + suffix
    }

    static var hasStoredKey: Bool {
        loadAPIKey() != nil
    }
}
