// LeakPeekBreachCredentialMatcher.swift
// Maps a public breach name (Adobe, LinkedIn) to a saved DynamicKey site credential.
// Flow: known domain hint → registrable-domain match → fuzzy host label match.

import Foundation

enum LeakPeekBreachCredentialMatcher {
    /// Common breach labels mapped to registrable domains for Fix Now routing.
    private static let domainHints: [String: String] = [
        "adobe": "adobe.com",
        "linkedin": "linkedin.com",
        "dropbox": "dropbox.com",
        "spotify": "spotify.com",
        "twitter": "twitter.com",
        "yahoo": "yahoo.com",
        "myspace": "myspace.com",
        "canva": "canva.com",
        "chegg": "chegg.com",
        "duolingo": "duolingo.com",
        "github": "github.com",
        "gitlab": "gitlab.com",
        "facebook": "facebook.com",
        "instagram": "instagram.com",
        "netflix": "netflix.com",
        "paypal": "paypal.com",
        "reddit": "reddit.com",
        "slack": "slack.com",
        "tumblr": "tumblr.com",
        "uber": "uber.com",
        "zoom": "zoom.us",
        "lastfm": "last.fm",
        "last.fm": "last.fm",
        "patreon": "patreon.com",
        "trello": "trello.com",
        "wattpad": "wattpad.com",
        "zynga": "zynga.com",
        "disqus": "disqus.com",
        "dailymotion": "dailymotion.com",
        "myfitnesspal": "myfitnesspal.com",
        "roblox": "roblox.com",
        "coinmama": "coinmama.com",
        "stockx": "stockx.com",
        "houzz": "houzz.com",
        "stratfor": "stratfor.com",
        "soundcloud": "soundcloud.com",
        "500px": "500px.com",
        "animoto": "animoto.com",
        "armorgames": "armorgames.com",
        "bitly": "bitly.com",
        "bookmate": "bookmate.com",
        "cafepress": "cafepress.com",
        "collection1": "collection-1.com",
        "collection-1": "collection-1.com",
        "eatstreet": "eatstreet.com",
        "eyeem": "eyeem.com",
        "glofox": "glofox.com",
        "homechef": "homechef.com",
        "ixigo": "ixigo.com",
        "komplett": "komplett.no",
        "ledger": "ledger.com",
        "livejournal": "livejournal.com",
        "neimanmarcus": "neimanmarcus.com",
        "nitro": "gonitro.com",
        "poshmark": "poshmark.com",
        "shein": "shein.com",
        "ticketfly": "ticketfly.com",
        "vk": "vk.com",
        "zomato": "zomato.com",
    ]

    /// Finds a saved credential that likely belongs to this breach service.
    static func matchingCredential(
        breachName: String,
        in credentials: [SiteCredential]
    ) -> SiteCredential? {
        let token = normalizedToken(breachName)
        guard !token.isEmpty else { return nil }

        if let hintedDomain = hintedDomain(for: token),
           let match = credential(matchingDomain: hintedDomain, in: credentials) {
            return match
        }

        if let fuzzy = credentials.first(where: { credentialMatchesToken($0, token: token) }) {
            return fuzzy
        }

        return nil
    }

    private static func normalizedToken(_ breachName: String) -> String {
        breachName
            .lowercased()
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map { String($0) }
            .joined()
    }

    private static func hintedDomain(for token: String) -> String? {
        if let direct = domainHints[token] {
            return direct
        }

        return domainHints.first { key, _ in
            token.contains(key) || key.contains(token)
        }?.value
    }

    private static func credential(
        matchingDomain domain: String,
        in credentials: [SiteCredential]
    ) -> SiteCredential? {
        credentials.first { credential in
            guard let host = URL(string: credential.origin)?.host?.lowercased() else { return false }
            let registrable = SiteCredential.registrableDomain(from: host)
            return registrable == domain || host.hasSuffix(".\(domain)") || host == domain
        }
    }

    private static func credentialMatchesToken(_ credential: SiteCredential, token: String) -> Bool {
        guard let host = URL(string: credential.origin)?.host?.lowercased() else { return false }
        let registrable = SiteCredential.registrableDomain(from: host)
        let label = registrable.split(separator: ".").first.map(String.init) ?? registrable
        let hostToken = label.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map { String($0) }
            .joined()

        guard hostToken.count >= 3, token.count >= 3 else { return false }
        return hostToken.contains(token) || token.contains(hostToken)
    }
}
