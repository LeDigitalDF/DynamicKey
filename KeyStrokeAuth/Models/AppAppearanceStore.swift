// AppAppearanceStore.swift
// Persists DynamicKey light/dark/system appearance and exposes palette tokens for glass UI.
// Flow: load saved theme (default dark) → publish palette + colorScheme to SwiftUI environment.

import AppKit
import Combine
import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case light
    case dark
    case system

    var id: String { rawValue }

    /// Explicit light/dark choices used by the main-window toolbar control.
    static let toolbarCases: [AppTheme] = [.dark, .light]

    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    var label: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }

    var preferencesSystemImage: String {
        switch self {
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        case .system: return "circle.lefthalf.filled"
        }
    }

    /// Resolves the concrete scheme for palette selection.
    var resolvedColorScheme: ColorScheme {
        switch self {
        case .light:
            return .light
        case .dark:
            return .dark
        case .system:
            let appearance = NSApp.effectiveAppearance
            let matched = appearance.bestMatch(from: [.darkAqua, .aqua])
            return matched == .darkAqua ? .dark : .light
        }
    }
}

@MainActor
final class AppAppearanceStore: ObservableObject {
    @Published private(set) var theme: AppTheme

    private static let storageKey = "dynamicKeyAppTheme"

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.storageKey),
           let saved = AppTheme(rawValue: raw) {
            theme = saved
        } else {
            theme = .dark
        }
    }

    /// Nil means follow the system appearance.
    var colorScheme: ColorScheme? { theme.colorScheme }

    var palette: GlassPalette {
        theme.resolvedColorScheme == .dark ? .dark : .light
    }

    func setTheme(_ theme: AppTheme) {
        guard self.theme != theme else { return }
        self.theme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: Self.storageKey)
    }
}
