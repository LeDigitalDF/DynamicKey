// SitePasswordGenerator.swift
// Generates cryptographically strong random passwords for per-site credentials (W3.5).
//
// Flow: SecRandomCopyBytes → map into URL-safe character set → return fixed-length secret.

import Foundation
import Security

enum SitePasswordGenerator {
    /// Default length for auto-generated site passwords.
    static let defaultLength = 24

    private static let lowers: [Character] = Array("abcdefghijklmnopqrstuvwxyz")
    private static let uppers: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    private static let digits: [Character] = Array("0123456789")
    private static let specials: [Character] = Array("!@#$%&*-_=+")
    private static let charset: [Character] = lowers + uppers + digits + specials

    /// Builds a random site password using the platform CSPRNG.
    /// Guarantees at least one lowercase, uppercase, digit, and symbol for strict site rules.
    static func generate(length: Int = defaultLength) -> String {
        let safeLength = max(16, min(length, 64))
        var chars: [Character] = [
            randomElement(from: lowers),
            randomElement(from: uppers),
            randomElement(from: digits),
            randomElement(from: specials)
        ]

        while chars.count < safeLength {
            chars.append(randomElement(from: charset))
        }

        return String(shuffle(chars))
    }

    private static func randomElement(from pool: [Character]) -> Character {
        var byte: UInt8 = 0
        let status = SecRandomCopyBytes(kSecRandomDefault, 1, &byte)
        guard status == errSecSuccess else {
            return pool[Int.random(in: 0..<pool.count)]
        }
        return pool[Int(byte) % pool.count]
    }

    private static func shuffle(_ input: [Character]) -> [Character] {
        var chars = input
        for index in stride(from: chars.count - 1, through: 1, by: -1) {
            var byte: UInt8 = 0
            _ = SecRandomCopyBytes(kSecRandomDefault, 1, &byte)
            let swapIndex = Int(byte) % (index + 1)
            chars.swapAt(index, swapIndex)
        }
        return chars
    }
}
