// ExtensionPairingStore.swift
// Keychain-backed pairing codes and paired extension client tokens (M5).
//
// Flow: user generates a short code in Settings → extension exchanges it for a bearer token.

import Foundation

extension Notification.Name {
    /// Posted when paired extension clients are added, replaced, or revoked.
    static let extensionPairingsDidChange = Notification.Name("KeyStrokeAuth.extensionPairingsDidChange")
}

enum ExtensionPairingError: Error, LocalizedError {
    case invalidOrExpiredCode
    case invalidAccessToken

    var errorDescription: String? {
        switch self {
        case .invalidOrExpiredCode:
            return "Pairing code is invalid or has expired."
        case .invalidAccessToken:
            return "Extension access token is not recognized."
        }
    }
}

final class ExtensionPairingStore {
    static let shared = ExtensionPairingStore()

    private let pendingKeychain = KeychainService(account: "extension.pairing.pending")
    private let clientsKeychain = KeychainService(account: "extension.pairing.clients")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    // MARK: - Pending pairing code

    /// Stores a new one-time pairing code with expiry.
    func savePendingCode(_ pending: PendingPairingCode) throws {
        let data = try encoder.encode(pending)
        try pendingKeychain.save(data: data)
    }

    /// Returns the active pending code if it has not expired.
    func activePendingCode(now: Date = Date()) -> PendingPairingCode? {
        guard let data = pendingKeychain.load(),
              let pending = try? decoder.decode(PendingPairingCode.self, from: data),
              pending.expiresAt > now else {
            return nil
        }
        return pending
    }

    /// Clears any unused pairing code from Keychain.
    func clearPendingCode() {
        try? pendingKeychain.delete()
    }

    // MARK: - Paired clients

    /// All extension clients that completed pairing.
    func pairedClients() -> [PairedExtensionClient] {
        guard let data = clientsKeychain.load(),
              let clients = try? decoder.decode([PairedExtensionClient].self, from: data) else {
            return []
        }
        return clients
    }

    /// Exchanges a valid pairing code for a long-lived access token.
    /// Replaces any existing pairing for the same browser family so re-pair does not stack duplicates.
    func pairClient(
        pairingCode: String,
        clientName: String?,
        browserFamily: String? = nil,
        now: Date = Date()
    ) throws -> PairedExtensionClient {
        guard let pending = activePendingCode(now: now),
              pending.code.caseInsensitiveCompare(pairingCode) == .orderedSame else {
            throw ExtensionPairingError.invalidOrExpiredCode
        }

        let resolvedFamily = PairedBrowserDisplay.resolvedFamily(
            browserFamily: browserFamily,
            clientName: clientName
        )
        let resolvedName = PairedBrowserDisplay.resolvedClientName(
            clientName: clientName,
            browserFamily: resolvedFamily
        )

        let client = PairedExtensionClient(
            id: UUID().uuidString,
            accessToken: UUID().uuidString,
            clientName: resolvedName,
            browserFamily: resolvedFamily,
            pairedAt: now
        )

        var clients = pairedClients()
        if let resolvedFamily {
            clients.removeAll { existing in
                PairedBrowserDisplay.resolvedFamily(
                    browserFamily: existing.browserFamily,
                    clientName: existing.clientName
                ) == resolvedFamily
            }
            // Safari often paired before browserFamily existed — drop the stale generic row on re-pair.
            if resolvedFamily == "safari" {
                clients.removeAll { existing in
                    PairedBrowserDisplay.resolvedFamily(
                        browserFamily: existing.browserFamily,
                        clientName: existing.clientName
                    ) == nil
                }
            }
        } else {
            // Generic legacy pairings without a browser family — keep one slot, replace on re-pair.
            clients.removeAll { existing in
                PairedBrowserDisplay.resolvedFamily(
                    browserFamily: existing.browserFamily,
                    clientName: existing.clientName
                ) == nil
            }
        }
        clients.append(client)
        try saveClients(clients)
        clearPendingCode()
        NotificationCenter.default.post(name: .extensionPairingsDidChange, object: nil)
        return client
    }

    /// Validates a bearer token from an extension request header.
    func client(forAccessToken token: String) -> PairedExtensionClient? {
        pairedClients().first { $0.accessToken == token }
    }

    /// Removes every paired extension client and any pending code.
    func revokeAllPairings() {
        clearPendingCode()
        try? clientsKeychain.delete()
        NotificationCenter.default.post(name: .extensionPairingsDidChange, object: nil)
    }

    /// Removes one paired extension client by id.
    func revokeClient(id: String) {
        var clients = pairedClients()
        let before = clients.count
        clients.removeAll { $0.id == id }
        guard clients.count != before else { return }
        try? saveClients(clients)
        NotificationCenter.default.post(name: .extensionPairingsDidChange, object: nil)
    }

    /// Replaces the full paired-client list (migration / dedupe).
    func replacePairedClients(_ clients: [PairedExtensionClient]) throws {
        try saveClients(clients)
    }

    private func saveClients(_ clients: [PairedExtensionClient]) throws {
        let data = try encoder.encode(clients)
        try clientsKeychain.save(data: data)
    }
}
