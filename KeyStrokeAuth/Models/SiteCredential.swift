// SiteCredential.swift
// Per-origin website login stored in the Mac app for extension autofill (W3.1 / W3.5).
//
// Flow: auto-generated on first rhythm grant, or saved manually in Settings for import/testing.

import Foundation

struct SiteCredential: Codable, Identifiable, Equatable {
    let id: UUID
    let origin: String
    let username: String
    let password: String
    let createdAt: Date
    /// True when the Mac app generated this site password (W3.5).
    let isGenerated: Bool

    init(
        id: UUID = UUID(),
        origin: String,
        username: String,
        password: String,
        createdAt: Date = Date(),
        isGenerated: Bool = false
    ) {
        self.id = id
        self.origin = SiteCredential.storageKey(for: origin)
        self.username = username
        self.password = password
        self.createdAt = createdAt
        self.isGenerated = isGenerated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        origin = try container.decode(String.self, forKey: .origin)
        username = try container.decode(String.self, forKey: .username)
        password = try container.decode(String.self, forKey: .password)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        isGenerated = try container.decodeIfPresent(Bool.self, forKey: .isGenerated) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case origin
        case username
        case password
        case createdAt
        case isGenerated
    }

    /// Normalizes user input to a stable origin key (scheme + host, no path).
    static func normalizeOrigin(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        if let url = URL(string: trimmed), let host = url.host {
            let scheme = url.scheme?.lowercased() ?? "https"
            if let port = url.port, port != 80 && port != 443 {
                return "\(scheme)://\(host):\(port)"
            }
            return "\(scheme)://\(host)"
        }

        if trimmed.contains("://") {
            return trimmed.lowercased()
        }

        return "https://\(trimmed.lowercased())"
    }

    /// Common multi-part public suffixes used for registrable-domain extraction.
    private static let multiPartPublicSuffixes = [
        "co.uk", "org.uk", "com.au", "co.jp", "com.br", "co.nz", "com.mx",
    ]

    /// Extracts the registrable domain (e.g. accounts.spotify.com → spotify.com).
    static func registrableDomain(from host: String) -> String {
        let lowered = host.lowercased()
        if lowered == "localhost" || lowered == "127.0.0.1" {
            return lowered
        }

        let parts = lowered.split(separator: ".")
        guard parts.count >= 2 else { return lowered }

        for suffix in multiPartPublicSuffixes {
            let suffixParts = suffix.split(separator: ".")
            guard parts.count > suffixParts.count else { continue }
            let tail = parts.suffix(suffixParts.count).joined(separator: ".")
            if tail == suffix {
                let labelCount = suffixParts.count + 1
                return parts.suffix(labelCount).joined(separator: ".")
            }
        }

        return parts.suffix(2).joined(separator: ".")
    }

    /// Stable storage key for credentials and allowlist (site group, not exact subdomain).
    static func storageKey(for raw: String) -> String {
        let normalized = normalizeOrigin(raw)
        guard let url = URL(string: normalized), let host = url.host else { return normalized }

        if host == "localhost" || host == "127.0.0.1" {
            return normalized
        }

        let domain = registrableDomain(from: host)
        let scheme = url.scheme?.lowercased() ?? "https"
        return "\(scheme)://\(domain)"
    }

    /// True when two origins belong to the same website (e.g. accounts.spotify.com and open.spotify.com).
    static func sameSiteGroup(_ lhs: String, _ rhs: String) -> Bool {
        storageKey(for: lhs) == storageKey(for: rhs)
    }

    /// Returns equivalent origin keys (localhost ↔ 127.0.0.1, plus exact normalized origin).
    static func equivalentOrigins(for origin: String) -> [String] {
        let normalized = normalizeOrigin(origin)
        guard !normalized.isEmpty else { return [] }

        var keys = [normalized, storageKey(for: normalized)]
        if normalized.contains("://localhost") {
            keys.append(normalized.replacingOccurrences(of: "://localhost", with: "://127.0.0.1"))
        }
        if normalized.contains("://127.0.0.1") {
            keys.append(normalized.replacingOccurrences(of: "://127.0.0.1", with: "://localhost"))
        }
        return Array(Set(keys))
    }
}
