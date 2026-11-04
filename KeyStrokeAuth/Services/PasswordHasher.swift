// PasswordHasher.swift
// Salted SHA-256 hashing for master password storage and verification.

import CryptoKit
import Foundation

enum PasswordHasher {
    static func generateSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    static func hash(password: String, salt: Data) -> Data {
        var combined = salt
        combined.append(Data(password.utf8))
        return Data(SHA256.hash(data: combined))
    }

    static func verify(password: String, salt: Data, expectedHash: Data) -> Bool {
        let computed = hash(password: password, salt: salt)
        return computed == expectedHash
    }
}
