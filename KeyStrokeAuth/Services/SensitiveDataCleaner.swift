// SensitiveDataCleaner.swift
// Clears password and keystroke buffers from memory when no longer needed (M3.3).

import Foundation

enum SensitiveDataCleaner {
    static func clear(_ value: inout String) {
        value = ""
    }

    static func clearLoginAttempt(text: inout String, data: inout [KeystrokeData]) {
        text = ""
        data = []
    }

    static func clearEnrollmentSample(text: inout String, data: inout [KeystrokeData]) {
        text = ""
        data = []
    }
}
