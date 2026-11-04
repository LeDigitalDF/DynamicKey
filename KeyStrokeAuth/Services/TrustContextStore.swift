// TrustContextStore.swift
// Persists trusted keyboards and Wi-Fi networks; evaluates unlock context for Mac login and extension verify.
// Flow: load lists → compare current HID keyboard + SSID → gate unlock; fully trusted context can skip future cloud login.

import Combine
import Foundation
import SwiftUI

struct TrustContextEvaluation: Equatable {
    let allowed: Bool
    let denialReason: DenialReason?
    let statusMessage: String?
}

/// Settings UI state for a single trust dimension (keyboard or network).
enum TrustRuleUIState: Equatable {
    case unrestricted
    case detected
    case matchesRule
    case doesNotMatch
    case cannotVerify

    var statusLabel: String {
        switch self {
        case .unrestricted: return "No restrictions yet"
        case .detected: return "Connected"
        case .matchesRule: return "Trusted"
        case .doesNotMatch: return "Not trusted"
        case .cannotVerify: return "Can't verify"
        }
    }

    var indicatorColor: Color {
        switch self {
        case .unrestricted: return .secondary
        case .detected, .matchesRule: return .green
        case .doesNotMatch: return .orange
        case .cannotVerify: return .yellow
        }
    }
}

@MainActor
final class TrustContextStore: ObservableObject {
    static let shared = TrustContextStore()

    @Published private(set) var trustedKeyboards: [TrustedKeyboard] {
        didSet { persistKeyboards() }
    }

    @Published private(set) var trustedNetworks: [TrustedNetwork] {
        didSet { persistNetworks() }
    }

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private enum Keys {
        static let trustedKeyboards = "dynamicKeyTrustedKeyboards"
        static let trustedNetworks = "dynamicKeyTrustedNetworks"
    }

    private init() {
        trustedKeyboards = Self.loadKeyboards()
        trustedNetworks = Self.loadNetworks()
    }

    /// True when no keyboard trust list exists yet.
    var requiresKeyboardTrust: Bool {
        !trustedKeyboards.isEmpty
    }

    /// True when no network trust list exists yet.
    var requiresNetworkTrust: Bool {
        !trustedNetworks.isEmpty
    }

    /// Whether the currently connected keyboard matches a trusted entry.
    var isCurrentKeyboardTrusted: Bool {
        guard requiresKeyboardTrust else { return true }
        let connected = Set(HardwareContextService.connectedKeyboards().map(\.fingerprint))
        return trustedKeyboards.contains { connected.contains($0.fingerprint) }
    }

    /// Whether the current Wi-Fi network matches a trusted entry.
    var isCurrentNetworkTrusted: Bool {
        guard requiresNetworkTrust else { return true }
        guard let ssid = HardwareContextService.currentWiFiNetworkName() else { return false }
        return trustedNetworks.contains { $0.ssid.caseInsensitiveCompare(ssid) == .orderedSame }
    }

    /// Settings UI state for the keyboard trust card.
    var keyboardTrustUIState: TrustRuleUIState {
        let connected = HardwareContextService.connectedKeyboards()
        guard !connected.isEmpty else { return .cannotVerify }
        guard requiresKeyboardTrust else { return .detected }
        return isCurrentKeyboardTrusted ? .matchesRule : .doesNotMatch
    }

    /// Settings UI state for the network trust card.
    var networkTrustUIState: TrustRuleUIState {
        guard HardwareContextService.currentWiFiNetworkName() != nil else { return .cannotVerify }
        guard requiresNetworkTrust else { return .detected }
        return isCurrentNetworkTrusted ? .matchesRule : .doesNotMatch
    }

    /// Both configured trust dimensions pass for the current hardware/network context.
    var isFullyTrusted: Bool {
        isCurrentKeyboardTrusted && isCurrentNetworkTrusted
    }

    /// Future M6 cloud account gate — master-password-only login is allowed when context is fully trusted.
    var canSkipCloudAccountLogin: Bool {
        isFullyTrusted
    }

    /// Human-readable summary for Settings and login banners.
    var contextStatusSummary: String {
        if !requiresKeyboardTrust && !requiresNetworkTrust {
            return "No trust rules configured — all keyboards and networks are allowed."
        }
        if isFullyTrusted {
            return "Trusted context — this keyboard and network are approved."
        }
        if requiresKeyboardTrust && !isCurrentKeyboardTrusted {
            return "Current keyboard is not trusted."
        }
        if requiresNetworkTrust && !isCurrentNetworkTrusted {
            if HardwareContextService.currentWiFiNetworkName() == nil {
                return "Wi-Fi name unavailable — trusted network rules cannot be verified."
            }
            return "Current Wi-Fi network is not trusted."
        }
        return "Context trust check failed."
    }

    /// Adds all currently connected keyboards that are not already trusted.
    @discardableResult
    func trustCurrentKeyboards() -> Int {
        let connected = HardwareContextService.connectedKeyboards()
        var updated = trustedKeyboards
        var addedCount = 0
        for keyboard in connected {
            guard !updated.contains(where: { $0.fingerprint == keyboard.fingerprint }) else { continue }
            updated.append(
                TrustedKeyboard(
                    fingerprint: keyboard.fingerprint,
                    displayName: keyboard.displayName
                )
            )
            addedCount += 1
        }
        if addedCount > 0 {
            trustedKeyboards = updated
        }
        return addedCount
    }

    /// Adds the current Wi-Fi SSID when it can be read.
    @discardableResult
    func trustCurrentNetwork() -> Bool {
        guard let ssid = HardwareContextService.currentWiFiNetworkName() else { return false }
        guard !trustedNetworks.contains(where: { $0.ssid.caseInsensitiveCompare(ssid) == .orderedSame }) else {
            return false
        }
        var updated = trustedNetworks
        updated.append(TrustedNetwork(ssid: ssid))
        trustedNetworks = updated
        return true
    }

    /// Removes a trusted keyboard entry by id.
    func removeKeyboard(id: UUID) {
        trustedKeyboards = trustedKeyboards.filter { $0.id != id }
    }

    /// Removes a trusted network entry by id.
    func removeNetwork(id: UUID) {
        trustedNetworks = trustedNetworks.filter { $0.id != id }
    }

    /// Evaluates whether unlock should proceed for Mac login or extension verify.
    func evaluateForUnlock() -> TrustContextEvaluation {
        if requiresKeyboardTrust && !isCurrentKeyboardTrusted {
            return TrustContextEvaluation(
                allowed: false,
                denialReason: .untrustedKeyboard,
                statusMessage: "Unlock blocked — connect a trusted keyboard or add this one in Settings."
            )
        }

        if requiresNetworkTrust && !isCurrentNetworkTrusted {
            let message: String
            if HardwareContextService.currentWiFiNetworkName() == nil {
                message = "Unlock blocked — Wi-Fi name is unavailable. Allow Location for DynamicKey or join a trusted network."
            } else {
                message = "Unlock blocked — this Wi-Fi network is not on your trusted list."
            }
            return TrustContextEvaluation(
                allowed: false,
                denialReason: .untrustedNetwork,
                statusMessage: message
            )
        }

        return TrustContextEvaluation(allowed: true, denialReason: nil, statusMessage: nil)
    }

    private func persistKeyboards() {
        guard let data = try? encoder.encode(trustedKeyboards) else { return }
        UserDefaults.standard.set(data, forKey: Keys.trustedKeyboards)
    }

    private func persistNetworks() {
        guard let data = try? encoder.encode(trustedNetworks) else { return }
        UserDefaults.standard.set(data, forKey: Keys.trustedNetworks)
    }

    private static func loadKeyboards() -> [TrustedKeyboard] {
        guard let data = UserDefaults.standard.data(forKey: Keys.trustedKeyboards),
              let decoded = try? JSONDecoder().decode([TrustedKeyboard].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func loadNetworks() -> [TrustedNetwork] {
        guard let data = UserDefaults.standard.data(forKey: Keys.trustedNetworks),
              let decoded = try? JSONDecoder().decode([TrustedNetwork].self, from: data) else {
            return []
        }
        return decoded
    }
}
