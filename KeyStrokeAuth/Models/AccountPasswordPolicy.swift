// AccountPasswordPolicy.swift
// Validation and strength scoring for Supabase account passwords (not master password).

import Foundation

enum AccountPasswordStrength: Equatable {
    case empty
    case weak
    case fair
    case good
    case strong
    case matched
    case mismatch

    var label: String {
        switch self {
        case .empty: return "Enter a password"
        case .weak: return "Weak"
        case .fair: return "Fair"
        case .good: return "Good"
        case .strong: return "Strong"
        case .matched: return "Match"
        case .mismatch: return "Passwords do not match"
        }
    }

    /// 0…1 fill amount for the strength bar.
    var fillFraction: CGFloat {
        switch self {
        case .empty: return 0
        case .weak: return 0.25
        case .fair: return 0.5
        case .good: return 0.75
        case .strong, .matched: return 1
        case .mismatch: return 0.2
        }
    }

    static func confirmFieldStrength(password: String, repeatPassword: String) -> AccountPasswordStrength {
        if repeatPassword.isEmpty { return .empty }
        if repeatPassword != password { return .mismatch }
        return .matched
    }
}

enum AccountPasswordPolicy {
    static let minimumLength = PasswordPolicy.minimumLength

    static func validate(password: String, repeatPassword: String) -> String? {
        if password.isEmpty || repeatPassword.isEmpty {
            return "Password cannot be empty."
        }
        if password.count < minimumLength {
            return "Password must be at least \(minimumLength) characters."
        }
        if !containsLetter(password) {
            return "Password must include at least one letter."
        }
        if !containsDigit(password) {
            return "Password must include at least one number."
        }
        if !containsSymbol(password) {
            return "Password must include at least one symbol (e.g. ! @ # $)."
        }
        if password != repeatPassword {
            return "Passwords do not match."
        }
        return nil
    }

    static func strength(for password: String) -> AccountPasswordStrength {
        if password.isEmpty { return .empty }

        var score = 0
        if password.count >= minimumLength { score += 1 }
        if password.count >= 12 { score += 1 }
        if containsLetter(password) { score += 1 }
        if containsDigit(password) { score += 1 }
        if containsSymbol(password) { score += 1 }
        if containsUppercase(password) && containsLowercase(password) { score += 1 }

        switch score {
        case 0...2: return .weak
        case 3: return .fair
        case 4: return .good
        default: return .strong
        }
    }

    private static func containsLetter(_ value: String) -> Bool {
        value.rangeOfCharacter(from: .letters) != nil
    }

    private static func containsDigit(_ value: String) -> Bool {
        value.rangeOfCharacter(from: .decimalDigits) != nil
    }

    private static func containsSymbol(_ value: String) -> Bool {
        let symbols = CharacterSet.alphanumerics.inverted
        return value.rangeOfCharacter(from: symbols) != nil
    }

    private static func containsUppercase(_ value: String) -> Bool {
        value.rangeOfCharacter(from: .uppercaseLetters) != nil
    }

    private static func containsLowercase(_ value: String) -> Bool {
        value.rangeOfCharacter(from: .lowercaseLetters) != nil
    }
}
