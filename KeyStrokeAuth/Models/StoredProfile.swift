// StoredProfile.swift
// Keychain-persisted user profile: salted password hash and rhythm baseline.

import Foundation

struct StoredProfile: Codable, Equatable {
    let passwordSalt: Data
    let passwordHash: Data
    let rhythmProfile: RhythmProfile
}
