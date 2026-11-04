// TrustedNetwork.swift
// Persisted Wi-Fi network name used for optional unlock location trust.
// Flow: user adds current SSID → stored in TrustContextStore → matched before unlock.

import Foundation

struct TrustedNetwork: Codable, Identifiable, Equatable {
    let id: UUID
    let ssid: String
    let addedAt: Date

    init(id: UUID = UUID(), ssid: String, addedAt: Date = Date()) {
        self.id = id
        self.ssid = ssid
        self.addedAt = addedAt
    }
}
