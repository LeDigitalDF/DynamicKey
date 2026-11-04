// AppPreferencesStore.swift
// Persists non-vault Settings preferences (launch at login, profile images).
// Menu bar visibility uses @AppStorage via showMenuBarIconDefaultsKey.
// Flow: load from UserDefaults on init → publish changes → save on update → apply system side effects.

import Combine
import SwiftUI

@MainActor
final class AppPreferencesStore: ObservableObject {
    static let shared = AppPreferencesStore()

    @Published var launchAtLoginEnabled: Bool {
        didSet {
            save(Keys.launchAtLoginEnabled, launchAtLoginEnabled)
            guard !isLoadingPreferences else { return }
            Task { @MainActor in
                LaunchAtLoginService.shared.applyPreference(launchAtLoginEnabled)
            }
        }
    }

    @Published var profileImageBookmark: Data? {
        didSet { UserDefaults.standard.set(profileImageBookmark, forKey: Keys.profileImageBookmark) }
    }

    @Published var profileBackgroundBookmark: Data? {
        didSet { UserDefaults.standard.set(profileBackgroundBookmark, forKey: Keys.profileBackgroundBookmark) }
    }

    /// When true, each genuine, margin-passing master-password login refines the typing rhythm profile.
    @Published var continuousLearningEnabled: Bool {
        didSet { UserDefaults.standard.set(continuousLearningEnabled, forKey: Keys.continuousLearningEnabled) }
    }

    @Published var appHotkey: AppHotkeyPreference {
        didSet { saveHotkey(appHotkey) }
    }

    @Published var dailySummaryAIProvider: DailySummaryAIProvider {
        didSet {
            UserDefaults.standard.set(dailySummaryAIProvider.rawValue, forKey: Keys.dailySummaryAIProvider)
        }
    }

    private enum Keys {
        static let launchAtLoginEnabled = "dynamicKeyLaunchAtLoginEnabled"
        static let showMenuBarIcon = "dynamicKeyShowMenuBarIcon"
        static let profileImageBookmark = "dynamicKeyProfileImageBookmark"
        static let profileBackgroundBookmark = "dynamicKeyProfileBackgroundBookmark"
        static let continuousLearningEnabled = "dynamicKeyContinuousLearningEnabled"
        static let appHotkey = "dynamicKeyAppHotkey"
        static let dailySummaryAIProvider = "dynamicKeyDailySummaryAIProvider"
    }

    /// UserDefaults key shared with `@AppStorage` for menu bar visibility.
    static let showMenuBarIconDefaultsKey = Keys.showMenuBarIcon

    private var isLoadingPreferences = true

    private init() {
        launchAtLoginEnabled = UserDefaults.standard.bool(forKey: Keys.launchAtLoginEnabled)
        profileImageBookmark = UserDefaults.standard.data(forKey: Keys.profileImageBookmark)
        profileBackgroundBookmark = UserDefaults.standard.data(forKey: Keys.profileBackgroundBookmark)
        if UserDefaults.standard.object(forKey: Keys.continuousLearningEnabled) == nil {
            continuousLearningEnabled = true
        } else {
            continuousLearningEnabled = UserDefaults.standard.bool(forKey: Keys.continuousLearningEnabled)
        }
        appHotkey = Self.loadHotkey()
        let aiRaw = UserDefaults.standard.string(forKey: Keys.dailySummaryAIProvider)
        dailySummaryAIProvider = DailySummaryAIProvider(rawValue: aiRaw ?? "") ?? .local
        isLoadingPreferences = false
    }

    private func save(_ key: String, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private func saveHotkey(_ hotkey: AppHotkeyPreference) {
        guard let data = try? JSONEncoder().encode(hotkey) else { return }
        UserDefaults.standard.set(data, forKey: Keys.appHotkey)
    }

    private static func loadHotkey() -> AppHotkeyPreference {
        guard let data = UserDefaults.standard.data(forKey: Keys.appHotkey),
              let hotkey = try? JSONDecoder().decode(AppHotkeyPreference.self, from: data) else {
            return .default
        }
        return hotkey
    }
}
