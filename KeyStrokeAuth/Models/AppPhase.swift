// AppPhase.swift
// High-level navigation states for the enrollment and login flow.

import Foundation

enum AppPhase: Equatable {
    case landing
    case welcome
    case sentenceTraining
    case setPassword
    case passwordEnrollment
    case explanation
    case login
    case success
    case denied
    case settings
    case changePasswordVerify
    case main
}

enum DenialReason: Equatable {
    case wrongPassword
    case rhythmMismatch
    case emptyInput
    case lockedOut(remainingSeconds: Int)
    case untrustedKeyboard
    case untrustedNetwork
}

struct LoginVerificationResult: Equatable {
    let granted: Bool
    let matchPercentage: Int
    let denialReason: DenialReason?
}
