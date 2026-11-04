// AppHotkeyPreference.swift
// Stores and displays the DynamicKey global hotkey preference for Preferences → General.
//
// Flow: user presses Hotkey button → next key chord is captured → saved to UserDefaults → shown on button.

import AppKit
import Foundation

struct AppHotkeyPreference: Equatable, Codable {
    var keyCode: UInt16
    var modifierFlags: UInt

    /// Default chord: Option + Space.
    static var `default`: AppHotkeyPreference {
        var flags = NSEvent.ModifierFlags()
        flags.insert(.option)
        return AppHotkeyPreference(keyCode: 49, modifierFlags: flags.rawValue)
    }

    var displayString: String {
        var parts: [String] = []
        let flags = NSEvent.ModifierFlags(rawValue: modifierFlags)

        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        parts.append(Self.keyDisplayName(for: keyCode))
        // Raycast-style spacing between modifiers and the key name (e.g. "⌥ Space").
        return parts.joined(separator: " ")
    }

    private static func keyDisplayName(for keyCode: UInt16) -> String {
        switch keyCode {
        case 49: return "Space"
        case 36: return "Return"
        case 53: return "Esc"
        case 48: return "Tab"
        case 51: return "Delete"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            if let entry = Self.keyCodeMap[keyCode] {
                return entry
            }
            return "Key\(keyCode)"
        }
    }

    private static let keyCodeMap: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L",
        38: "J", 40: "K", 45: "N", 46: "M",
    ]
}
