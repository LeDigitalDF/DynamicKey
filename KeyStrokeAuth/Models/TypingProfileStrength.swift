// TypingProfileStrength.swift
// Human-readable rhythm profile quality label for Settings.

import Foundation

enum TypingProfileStrength: String {
    case high
    case medium
    case low

    var label: String {
        rawValue.capitalized
    }
}

extension RhythmProfile {
    /// Mean dwell time across all enrolled key positions, in milliseconds.
    var averageDwellMilliseconds: Int {
        guard !positionStats.isEmpty else { return 0 }
        let total = positionStats.reduce(0.0) { $0 + $1.meanDwell }
        return Int((total / Double(positionStats.count) * 1000).rounded())
    }

    /// Mean flight time across all enrolled key positions, in milliseconds.
    var averageFlightMilliseconds: Int {
        guard !positionStats.isEmpty else { return 0 }
        let total = positionStats.reduce(0.0) { $0 + $1.meanFlight }
        return Int((total / Double(positionStats.count) * 1000).rounded())
    }

    /// How distinct and recognizable the enrolled rhythm is (derived from samples and consistency).
    var profileStrength: TypingProfileStrength {
        guard !positionStats.isEmpty else { return .low }

        let positionFactor = min(1.0, Double(positionStats.count) / 12.0)
        let sampleFactor = min(1.0, Double(positionStats.map(\.sampleCount).max() ?? 0) / 3.0)

        let variationScores = positionStats.flatMap { stat -> [Double] in
            var scores: [Double] = []
            if stat.meanDwell > 0 {
                scores.append(min(1.0, stat.stdDwell / stat.meanDwell))
            }
            if stat.meanFlight > 0 {
                scores.append(min(1.0, stat.stdFlight / stat.meanFlight))
            }
            return scores
        }

        let averageVariation = variationScores.isEmpty
            ? 1.0
            : variationScores.reduce(0, +) / Double(variationScores.count)

        // Moderate, stable timing variation reads as a stronger recognizable profile.
        let consistencyFactor = 1.0 - abs(averageVariation - 0.35)
        let score = (positionFactor * 0.35) + (sampleFactor * 0.30) + (consistencyFactor * 0.35)

        if score >= 0.62 { return .high }
        if score >= 0.38 { return .medium }
        return .low
    }
}
