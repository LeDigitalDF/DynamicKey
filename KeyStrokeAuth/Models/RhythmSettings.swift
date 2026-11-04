// RhythmSettings.swift
// User-configurable rhythm verification threshold stored in UserDefaults.

import Foundation

enum RhythmSettings {
    private static let thresholdKey = "LeDigital.KeyStrokeAuth.rhythmPassThreshold"
    static let minimumThreshold = 50
    static let maximumThreshold = 90
    static let defaultThreshold = 70

    /// Adaptive learning only folds in logins that clear the threshold by at least this margin,
    /// so borderline sessions never loosen the model.
    static let learningMarginAboveThreshold = 10

    static var passThreshold: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: thresholdKey)
            return stored == 0 ? defaultThreshold : stored
        }
        set {
            let clamped = min(maximumThreshold, max(minimumThreshold, newValue))
            UserDefaults.standard.set(clamped, forKey: thresholdKey)
        }
    }
}
