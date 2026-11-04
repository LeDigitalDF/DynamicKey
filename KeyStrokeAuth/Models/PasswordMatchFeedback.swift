// PasswordMatchFeedback.swift
// Live feedback while the user confirms their master password.

import Foundation

struct PasswordMatchFeedback: Equatable {
    let message: String
    let isPositive: Bool
    let percentage: Int?

    static func evaluate(master: String, repeat repeatPassword: String) -> PasswordMatchFeedback? {
        guard !repeatPassword.isEmpty else { return nil }

        if master == repeatPassword {
            return PasswordMatchFeedback(
                message: "Passwords match (100%)",
                isPositive: true,
                percentage: 100
            )
        }

        let masterChars = Array(master)
        let repeatChars = Array(repeatPassword)

        if repeatChars.count > masterChars.count {
            return PasswordMatchFeedback(
                message: "Passwords do not match",
                isPositive: false,
                percentage: nil
            )
        }

        for (index, character) in repeatChars.enumerated() where masterChars[index] != character {
            return PasswordMatchFeedback(
                message: "Passwords do not match",
                isPositive: false,
                percentage: nil
            )
        }

        let percentage = Int((Double(repeatChars.count) / Double(masterChars.count)) * 100)
        return PasswordMatchFeedback(
            message: "Matching: \(percentage)%",
            isPositive: true,
            percentage: percentage
        )
    }
}
