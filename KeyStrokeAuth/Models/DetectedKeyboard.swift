// DetectedKeyboard.swift
// Ephemeral keyboard identity discovered from HID or input-source fallback.
// Flow: HardwareContextService scans devices → fingerprint compared to trusted list.

import Foundation

struct DetectedKeyboard: Identifiable, Equatable {
    let fingerprint: String
    let displayName: String
    /// True when HID devices were unavailable and the input layout name is used as a proxy.
    let isInputLayoutProxy: Bool

    var id: String { fingerprint }

    init(fingerprint: String, displayName: String, isInputLayoutProxy: Bool = false) {
        self.fingerprint = fingerprint
        self.displayName = displayName
        self.isInputLayoutProxy = isInputLayoutProxy
    }
}
