// HardwareContextService.swift
// Reads connected keyboards (IOKit HID) and the current Wi-Fi SSID (CoreWLAN).
// Flow: scan devices → build fingerprints → expose current network name for trust UI and checks.

import Carbon
import CoreWLAN
import Foundation
import IOKit.hid

enum HardwareContextService {
    /// Returns unique keyboard fingerprints currently connected to this Mac.
    static func connectedKeyboards() -> [DetectedKeyboard] {
        let hidKeyboards = keyboardsFromHID()
        if !hidKeyboards.isEmpty {
            return deduplicated(hidKeyboards)
        }
        return fallbackInputSourceKeyboard()
    }

    /// Reads the active Wi-Fi network name when CoreWLAN and permissions allow it.
    static func currentWiFiNetworkName() -> String? {
        guard let interface = CWWiFiClient.shared().interface() else { return nil }
        let ssid = interface.ssid()?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let ssid, !ssid.isEmpty else { return nil }
        return ssid
    }

    /// Builds a short user-facing label for the current Wi-Fi state.
    static func currentWiFiStatusLabel() -> String {
        if let ssid = currentWiFiNetworkName() {
            return ssid
        }
        return "Wi-Fi name unavailable"
    }

    /// Guidance when SSID cannot be read — Location Services, not Input Monitoring.
    static var wiFiUnavailableGuidance: String {
        "Allow Location for DynamicKey under System Settings → Privacy & Security → Location Services, then return here."
    }

    // MARK: - HID

    /// Enumerates generic-desktop keyboard HID devices and maps them to fingerprints.
    private static func keyboardsFromHID() -> [DetectedKeyboard] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keyboard
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            return []
        }
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return []
        }

        return deviceSet.compactMap { device in
            let vendor = hidIntProperty(device, key: kIOHIDVendorIDKey as String) ?? 0
            let product = hidIntProperty(device, key: kIOHIDProductIDKey as String) ?? 0
            let productName = hidStringProperty(device, key: kIOHIDProductKey as String) ?? "Keyboard"
            let manufacturer = hidStringProperty(device, key: kIOHIDManufacturerKey as String)
            let displayName = manufacturer.map { "\($0) \(productName)" } ?? productName
            let fingerprint = "hid:\(vendor)-\(product)-\(sanitizeFingerprintToken(productName))"
            return DetectedKeyboard(fingerprint: fingerprint, displayName: displayName)
        }
    }

    /// Falls back to the active keyboard input source when HID enumeration is unavailable.
    private static func fallbackInputSourceKeyboard() -> [DetectedKeyboard] {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return []
        }

        let bundleID = inputSourceString(source, key: kTISPropertyInputSourceID) ?? "unknown-input-source"
        let localizedName = inputSourceString(source, key: kTISPropertyLocalizedName) ?? "Current Keyboard"
        let fingerprint = "tis:\(sanitizeFingerprintToken(bundleID))"
        return [DetectedKeyboard(
            fingerprint: fingerprint,
            displayName: "\(localizedName) (input layout)",
            isInputLayoutProxy: true
        )]
    }

    /// Removes duplicate fingerprints while preserving first-seen order.
    private static func deduplicated(_ keyboards: [DetectedKeyboard]) -> [DetectedKeyboard] {
        var seen = Set<String>()
        var results: [DetectedKeyboard] = []
        for keyboard in keyboards {
            guard seen.insert(keyboard.fingerprint).inserted else { continue }
            results.append(keyboard)
        }
        return results
    }

    private static func hidIntProperty(_ device: IOHIDDevice, key: String) -> Int? {
        guard let value = IOHIDDeviceGetProperty(device, key as CFString) else { return nil }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return nil
    }

    private static func hidStringProperty(_ device: IOHIDDevice, key: String) -> String? {
        guard let value = IOHIDDeviceGetProperty(device, key as CFString) else { return nil }
        return value as? String
    }

    private static func inputSourceString(_ source: TISInputSource, key: CFString) -> String? {
        guard let value = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFTypeRef>.fromOpaque(value).takeUnretainedValue() as? String
    }

    /// Normalizes free-form strings into stable fingerprint tokens.
    private static func sanitizeFingerprintToken(_ value: String) -> String {
        let lowered = value.lowercased()
        let allowed = lowered.map { character -> Character in
            if character.isLetter || character.isNumber { return character }
            return "-"
        }
        return String(allowed)
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
