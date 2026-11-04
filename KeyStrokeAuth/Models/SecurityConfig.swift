// SecurityConfig.swift
// Rate limiting, lockout, and audit log constants for M3 security hardening.

import Foundation

enum SecurityConfig {
    static let maxFailedAttemptsBeforeLockout = 5
    static let failureWindowSeconds: TimeInterval = 15 * 60
    static let baseLockoutSeconds: TimeInterval = 60
    static let maxLockoutSeconds: TimeInterval = 15 * 60
    static let auditLogMaxEntries = 100
}
