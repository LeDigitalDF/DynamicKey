// EmailBreachCheckService.swift
// Queries public breach data for email addresses via the XposedOrNot API.
// Flow: URL-encode email → GET check-email → parse breach names or treat as safe.

import Foundation

enum EmailBreachCheckError: Error, LocalizedError {
    case invalidEmail
    case invalidResponse
    case rateLimited
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return "That address does not look like a valid email."
        case .invalidResponse:
            return "Could not read the email breach check response."
        case .rateLimited:
            return "Too many breach checks in a short time. Try again in a minute."
        case .network(let error):
            return error.localizedDescription
        }
    }
}

enum EmailBreachCheckService {
    private static let baseURL = "https://api.xposedornot.com/v1/check-email/"
    private static let requestDelayNanoseconds: UInt64 = 550_000_000

    /// Looks up one email and returns breach names when compromised.
    static func checkEmail(_ email: String) async throws -> [String] {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard LeakPeekEmailValidator.isEmail(trimmed) else {
            throw EmailBreachCheckError.invalidEmail
        }

        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: baseURL + encoded) else {
            throw EmailBreachCheckError.invalidEmail
        }

        var request = URLRequest(url: url)
        request.setValue("DynamicKey-LeakPeek", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw EmailBreachCheckError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw EmailBreachCheckError.invalidResponse
        }

        if http.statusCode == 429 {
            throw EmailBreachCheckError.rateLimited
        }

        if http.statusCode == 404 {
            return []
        }

        guard http.statusCode == 200 else {
            throw EmailBreachCheckError.invalidResponse
        }

        return try parseBreachNames(from: data)
    }

    /// XposedOrNot asks callers to stay under 2 requests per second.
    static func throttleBetweenChecks() async {
        try? await Task.sleep(nanoseconds: requestDelayNanoseconds)
    }

    private static func parseBreachNames(from data: Data) throws -> [String] {
        let object = try JSONSerialization.jsonObject(with: data)

        if let dictionary = object as? [String: Any],
           let error = dictionary["Error"] as? String,
           error.caseInsensitiveCompare("Not found") == .orderedSame {
            return []
        }

        guard let dictionary = object as? [String: Any] else {
            throw EmailBreachCheckError.invalidResponse
        }

        guard let breachGroups = dictionary["breaches"] as? [[String]] else {
            if dictionary["status"] as? String == "success" {
                return []
            }
            throw EmailBreachCheckError.invalidResponse
        }

        let names = breachGroups.flatMap { $0 }
        return Array(Set(names)).sorted()
    }
}
