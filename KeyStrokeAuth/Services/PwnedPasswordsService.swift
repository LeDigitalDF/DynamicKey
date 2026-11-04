// PwnedPasswordsService.swift
// Queries the Have I Been Pwned Pwned Passwords API using k-anonymity (SHA-1 prefix only).
// Flow: hash password locally → send first 5 hex chars → match suffixes locally in the response.

import CryptoKit
import Foundation

enum PwnedPasswordsError: Error, LocalizedError {
    case invalidResponse
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Could not read breach check response."
        case .network(let error):
            return error.localizedDescription
        }
    }
}

enum PwnedPasswordsService {
    private static let rangeURL = "https://api.pwnedpasswords.com/range/"
    private static let requestDelayNanoseconds: UInt64 = 1_600_000_000

    /// Returns true when the password appears in known breach corpora.
    static func isPasswordCompromised(_ password: String) async throws -> Bool {
        let digest = Insecure.SHA1.hash(data: Data(password.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined().uppercased()
        let prefix = String(hash.prefix(5))
        let suffix = String(hash.dropFirst(5))

        guard let url = URL(string: rangeURL + prefix) else {
            throw PwnedPasswordsError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("KeyStrokeAuth-LeakPeek", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw PwnedPasswordsError.network(error)
        }

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw PwnedPasswordsError.invalidResponse
        }

        guard let body = String(data: data, encoding: .utf8) else {
            throw PwnedPasswordsError.invalidResponse
        }

        return body
            .split(whereSeparator: \.isNewline)
            .contains { line in
                let token = line.split(separator: ":", maxSplits: 1).first
                return token == Substring(suffix)
            }
    }

    /// HIBP asks callers to pause between range requests to preserve anonymity.
    static func throttleBetweenChecks() async {
        try? await Task.sleep(nanoseconds: requestDelayNanoseconds)
    }
}
