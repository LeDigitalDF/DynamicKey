// SitePasswordChangeURLResolver.swift
// Best-effort URLs for LeakPeek "Fix It" — sites use different account/security paths.
// Flow: site-specific override → common security paths → append ?dynamickey-fix=1 for extension assist.

import Foundation

enum SitePasswordChangeURLResolver {
    /// Query flag the browser extension watches for Fix It assist mode.
    static let fixPasswordQueryName = "dynamickey-fix"
    static let fixPasswordQueryValue = "1"

    /// Legacy hash fragment — still recognized by the extension for older links.
    static let fixPasswordFragment = "dynamickey-fix-password"

    /// Known password-change pages keyed by registrable domain (spotify.com, not www.spotify.com).
    private static let siteSpecificURLs: [String: String] = [
        "spotify.com": "https://www.spotify.com/account/change-password/",
    ]

    /// Common account/security paths (registrable domain); order is most-specific first.
    private static let securityPathCandidates = [
        "/account/change-password",
        "/account/security",
        "/account/password",
        "/settings/security",
        "/settings/password",
        "/security/password",
        "/my-account/security",
        "/user/security",
        "/account",
        "/settings",
        "/my-account",
    ]

    /// Opens the best guess for a password-change page; extension shows assist UI via query flag.
    static func preferredFixURL(for origin: String) -> URL? {
        let normalized = SiteCredential.normalizeOrigin(origin)
        let storageKey = SiteCredential.storageKey(for: normalized)

        if let host = URL(string: storageKey)?.host {
            let domain = SiteCredential.registrableDomain(from: host)
            if let specific = siteSpecificURLs[domain] {
                return urlWithFixSignal(specific)
            }
        }

        guard let host = URL(string: normalized)?.host else {
            return urlWithFixSignal(normalized)
        }

        let scheme = URL(string: normalized)?.scheme?.lowercased() ?? "https"
        let root = "\(scheme)://\(host)"

        for path in securityPathCandidates {
            if let candidate = urlWithFixSignal("\(root)\(path)") {
                return candidate
            }
        }

        return urlWithFixSignal(normalized)
    }

    private static func urlWithFixSignal(_ urlString: String) -> URL? {
        guard var components = URLComponents(string: urlString) else { return nil }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == fixPasswordQueryName }
        items.append(URLQueryItem(name: fixPasswordQueryName, value: fixPasswordQueryValue))
        components.queryItems = items
        components.fragment = nil
        return components.url
    }
}
