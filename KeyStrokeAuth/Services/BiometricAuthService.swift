// BiometricAuthService.swift
// Wraps LocalAuthentication Touch ID / Apple Watch prompts for login fallback.
// Flow: caller requests biometric → LAContext evaluates policy → success/failure returned to login flow.

import Foundation
import LocalAuthentication

enum BiometricAuthService {
    /// Prompts for Touch ID or Apple Watch approval.
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &policyError) else {
            return false
        }

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            ) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    /// Whether biometric hardware is available for fallback unlock.
    static var isAvailable: Bool {
        let context = LAContext()
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }
}
