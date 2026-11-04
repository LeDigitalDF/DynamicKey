// SettingsSlideOver.swift
// Identifies which settings slide-over panel is presented from the main shell.

import Foundation

enum SettingsSlideOver: String, Identifiable {
    case changeMasterPassword

    var id: String { rawValue }
}
