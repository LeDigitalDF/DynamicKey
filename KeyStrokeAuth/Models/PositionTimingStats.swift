// PositionTimingStats.swift
// Per-character-position timing statistics from enrollment samples.
// Flow: enrollment builds mean/std/sampleCount per position → adaptive learning folds each new
//       genuine login into those stats with Welford's online update (no raw samples are stored).

import Foundation

struct PositionTimingStats: Codable, Equatable, Identifiable {
    let position: Int
    let character: String
    let meanDwell: TimeInterval
    let stdDwell: TimeInterval
    let meanFlight: TimeInterval
    let stdFlight: TimeInterval
    let sampleCount: Int

    var id: Int { position }

    /// Effective sample weight is capped so a long history can't ossify the model and a single
    /// odd (but passing) session can't shift it too much — updates stay gentle and bounded.
    static let maxLearnedSampleCount = 40

    /// Returns a copy with one additional observation folded into the dwell and flight statistics.
    /// Uses population-variance Welford updates, reconstructing the running sum of squares from the
    /// stored std (`M2 = std² × n`). Std is floored at `TimingStatistics.minimumStd`.
    func folding(dwell: TimeInterval, flight: TimeInterval) -> PositionTimingStats {
        let (newMeanDwell, newStdDwell, newCount) = Self.updated(
            mean: meanDwell,
            std: stdDwell,
            count: sampleCount,
            newValue: dwell
        )
        let (newMeanFlight, newStdFlight, _) = Self.updated(
            mean: meanFlight,
            std: stdFlight,
            count: sampleCount,
            newValue: flight
        )

        return PositionTimingStats(
            position: position,
            character: character,
            meanDwell: newMeanDwell,
            stdDwell: newStdDwell,
            meanFlight: newMeanFlight,
            stdFlight: newStdFlight,
            sampleCount: newCount
        )
    }

    /// Single-observation online update of a (mean, std, count) triple with a capped effective count.
    private static func updated(
        mean: TimeInterval,
        std: TimeInterval,
        count: Int,
        newValue: TimeInterval
    ) -> (mean: TimeInterval, std: TimeInterval, count: Int) {
        // Cap the weighting count so the estimate keeps tracking recent behavior instead of freezing.
        let effectiveCount = min(max(count, 1), maxLearnedSampleCount)
        let nextCount = min(count + 1, maxLearnedSampleCount)
        let weightN = Double(min(effectiveCount + 1, maxLearnedSampleCount))

        // Reconstruct the population sum of squares, apply Welford, then recompute std.
        let priorVariance = std * std
        var sumSquares = priorVariance * Double(effectiveCount)

        let deltaBefore = newValue - mean
        let updatedMean = mean + deltaBefore / weightN
        let deltaAfter = newValue - updatedMean
        sumSquares += deltaBefore * deltaAfter

        let updatedVariance = max(0, sumSquares / weightN)
        let updatedStd = max(TimingStatistics.minimumStd, updatedVariance.squareRoot())

        return (updatedMean, updatedStd, nextCount)
    }
}
