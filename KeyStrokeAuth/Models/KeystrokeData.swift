// KeystrokeData.swift
// Single keystroke timing sample captured during training or login.

import Foundation

struct KeystrokeData: Codable, Equatable {
    let character: String
    let dwellTime: TimeInterval
    let flightTime: TimeInterval
}
