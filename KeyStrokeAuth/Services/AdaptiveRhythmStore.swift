// AdaptiveRhythmStore.swift
// Tracks recent genuine login match percentages to advise (never force) raising the threshold slider.
// Flow: each successful rhythm login records its match% → when recent logins clear the current
//       threshold comfortably and consistently, suggestedThreshold() returns a higher value to offer.
// Privacy: only aggregate match percentages are kept locally (UserDefaults), never keystrokes.

import Combine
import Foundation

@MainActor
final class AdaptiveRhythmStore: ObservableObject {
    static let shared = AdaptiveRhythmStore()

    /// Rolling window of the most recent successful match percentages (oldest first).
    @Published private(set) var recentMatchScores: [Int]

    private let maxScores = 20
    private let minScoresForSuggestion = 8
    /// Headroom kept below the user's consistent low score so a suggestion stays comfortably clearable.
    private let suggestionBuffer = 8

    private let storageKey = "dynamicKeyRecentRhythmScores"

    private init() {
        recentMatchScores = UserDefaults.standard.array(forKey: storageKey) as? [Int] ?? []
    }

    /// Records one successful login's match percentage, trimming to the rolling window size.
    func recordSuccessfulMatch(_ percentage: Int) {
        let clamped = min(100, max(0, percentage))
        var scores = recentMatchScores
        scores.append(clamped)
        if scores.count > maxScores {
            scores.removeFirst(scores.count - maxScores)
        }
        recentMatchScores = scores
        UserDefaults.standard.set(scores, forKey: storageKey)
    }

    /// Clears the history — call when the profile is deleted, retrained, or the master password changes.
    func reset() {
        recentMatchScores = []
        UserDefaults.standard.set([Int](), forKey: storageKey)
    }

    /// Suggests a higher threshold when recent genuine logins clear the current one comfortably.
    /// Returns nil when there isn't enough data or no meaningful increase is warranted.
    func suggestedThreshold(currentThreshold: Int) -> Int? {
        guard recentMatchScores.count >= minScoresForSuggestion else { return nil }

        // Use the 20th-percentile score so a couple of low outliers don't inflate the suggestion.
        let sorted = recentMatchScores.sorted()
        let index = Int((Double(sorted.count - 1) * 0.2).rounded(.down))
        let robustLow = sorted[index]

        // Keep headroom below that low score, then round down to the nearest 5%.
        let candidate = ((robustLow - suggestionBuffer) / 5) * 5
        let clamped = min(RhythmSettings.maximumThreshold, max(RhythmSettings.minimumThreshold, candidate))

        // Only suggest a meaningful bump above the current setting.
        guard clamped >= currentThreshold + 5 else { return nil }
        return clamped
    }
}
