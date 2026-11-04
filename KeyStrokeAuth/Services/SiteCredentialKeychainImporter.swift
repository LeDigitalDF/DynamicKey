// SiteCredentialKeychainImporter.swift
// Best-effort import of macOS internet-password Keychain items (W3.4).
//
// Flow: Settings → Import from Keychain → reads Safari/system internet passwords when permitted.
// Sandboxed apps often cannot read Apple Passwords entries; CSV import remains the supported migration path.

import Foundation
import Security

enum SiteCredentialKeychainImporterError: Error, LocalizedError {
    case accessDenied
    case noEntriesFound
    case queryFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return """
            KeyStrokeAuth cannot read Apple Passwords directly while sandboxed. \
            In the Passwords app choose File → Export Passwords, then use Import CSV here.
            """
        case .noEntriesFound:
            return "No internet passwords were found in Keychain that KeyStrokeAuth can access."
        case .queryFailed(let status):
            return "Keychain query failed (status \(status))."
        }
    }
}

enum SiteCredentialKeychainImporter {
    /// Attempts to copy internet-password Keychain entries into site credentials.
    static func importAccessiblePasswords(into store: CredentialStore = .shared) throws -> SiteCredentialImportResult {
        let items = try fetchInternetPasswordItems()

        var importedCount = 0
        var skippedCount = 0
        var rowErrors: [String] = []

        for (index, item) in items.enumerated() {
            guard let origin = origin(from: item) else {
                rowErrors.append("Entry \(index + 1): missing website URL.")
                skippedCount += 1
                continue
            }

            let username = item[kSecAttrAccount as String] as? String ?? ""
            guard let passwordData = item[kSecValueData as String] as? Data,
                  let password = String(data: passwordData, encoding: .utf8),
                  !password.isEmpty else {
                rowErrors.append("Entry \(index + 1): missing password.")
                skippedCount += 1
                continue
            }

            let credential = SiteCredential(
                origin: origin,
                username: username,
                password: password,
                isGenerated: false
            )

            do {
                try store.save(credential)
                importedCount += 1
            } catch {
                rowErrors.append("Entry \(index + 1): \(error.localizedDescription)")
                skippedCount += 1
            }
        }

        if importedCount > 0 {
            AuditLogService.shared.append(
                AuditEvent(
                    type: .siteCredentialsImported,
                    detail: "Keychain import: \(importedCount), skipped \(skippedCount)"
                )
            )
        }

        return SiteCredentialImportResult(
            importedCount: importedCount,
            skippedCount: skippedCount,
            rowErrors: rowErrors
        )
    }

    private static func fetchInternetPasswordItems() throws -> [[String: Any]] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            break
        case errSecItemNotFound:
            throw SiteCredentialKeychainImporterError.noEntriesFound
        case errSecMissingEntitlement, errSecNotAvailable:
            throw SiteCredentialKeychainImporterError.accessDenied
        default:
            throw SiteCredentialKeychainImporterError.queryFailed(status)
        }

        if let items = result as? [[String: Any]] {
            return items
        }
        if let item = result as? [String: Any] {
            return [item]
        }

        throw SiteCredentialKeychainImporterError.noEntriesFound
    }

    private static func origin(from item: [String: Any]) -> String? {
        guard let server = item[kSecAttrServer as String] as? String, !server.isEmpty else {
            return nil
        }

        let protocolValue = (item[kSecAttrProtocol as String] as? String)?.lowercased()
        let scheme: String
        switch protocolValue {
        case "http", "http:":
            scheme = "http"
        default:
            scheme = "https"
        }

        if let port = item[kSecAttrPort as String] as? Int, port != 80 && port != 443 {
            return SiteCredential.normalizeOrigin("\(scheme)://\(server):\(port)")
        }

        return SiteCredential.normalizeOrigin("\(scheme)://\(server)")
    }
}
