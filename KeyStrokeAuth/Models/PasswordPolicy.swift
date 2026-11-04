// PasswordPolicy.swift
// Validation rules for master password enrollment.

import Foundation

enum PasswordPolicy {
    static let minimumLength = 8

    static func validate(password: String, repeatPassword: String) -> String? {
        if password.isEmpty || repeatPassword.isEmpty {
            return "Password cannot be empty."
        }
        if password.count < minimumLength {
            return "Password must be at least \(minimumLength) characters."
        }
        if password != repeatPassword {
            return "Passwords do not match."
        }
        return nil
    }

    /// Strength indicator for master password fields (length-based).
    static func strength(for password: String) -> AccountPasswordStrength {
        if password.isEmpty { return .empty }
        if password.count < minimumLength { return .weak }
        if password.count < 12 { return .fair }
        if password.count < 16 { return .good }
        return .strong
    }

    static func confirmFieldStrength(password: String, repeatPassword: String) -> AccountPasswordStrength {
        if repeatPassword.isEmpty { return .empty }
        if repeatPassword != password { return .mismatch }
        return .matched
    }
}
