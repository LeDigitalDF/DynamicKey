// RhythmVerifier.swift
// Statistical rhythm verification using per-position z-scores.

import Foundation

struct RhythmVerificationScore: Equatable {
    let matchPercentage: Int
    let averageZScore: Double
    let comparedKeystrokes: Int
}

enum RhythmVerifier {
    static var passThreshold: Int {
        RhythmSettings.passThreshold
    }

    static func score(
        loginData: [KeystrokeData],
        password: String,
        profile: RhythmProfile
    ) -> RhythmVerificationScore {
        guard !loginData.isEmpty else {
            return RhythmVerificationScore(matchPercentage: 0, averageZScore: .infinity, comparedKeystrokes: 0)
        }

        if profile.isLegacyProfile {
            return legacyScore(loginData: loginData, profile: profile)
        }

        let compareCount = min(loginData.count, profile.positionStats.count, password.count)
        guard compareCount > 0 else {
            return RhythmVerificationScore(matchPercentage: 0, averageZScore: .infinity, comparedKeystrokes: 0)
        }

        var zScores: [Double] = []

        for index in 0..<compareCount {
            let stats = profile.positionStats[index]
            let keystroke = loginData[index]
            let dwellZ = zScore(value: keystroke.dwellTime, mean: stats.meanDwell, std: stats.stdDwell)
            let flightZ = zScore(value: keystroke.flightTime, mean: stats.meanFlight, std: stats.stdFlight)
            zScores.append(dwellZ)
            zScores.append(flightZ)
        }

        let averageZ = zScores.reduce(0, +) / Double(zScores.count)
        let matchPercentage = percentage(fromAverageZ: averageZ)

        return RhythmVerificationScore(
            matchPercentage: matchPercentage,
            averageZScore: averageZ,
            comparedKeystrokes: compareCount
        )
    }

    static func matchPercentage(
        loginData: [KeystrokeData],
        password: String,
        profile: RhythmProfile
    ) -> Int {
        score(loginData: loginData, password: password, profile: profile).matchPercentage
    }

    static func passes(
        loginData: [KeystrokeData],
        password: String,
        profile: RhythmProfile
    ) -> Bool {
        matchPercentage(loginData: loginData, password: password, profile: profile) >= passThreshold
    }

    private static func zScore(value: TimeInterval, mean: TimeInterval, std: TimeInterval) -> Double {
        abs(value - mean) / max(std, TimingStatistics.minimumStd)
    }

    private static func percentage(fromAverageZ averageZ: Double) -> Int {
        let raw = 100 - (averageZ * 25)
        return max(0, min(100, Int(raw.rounded())))
    }

    private static func legacyScore(
        loginData: [KeystrokeData],
        profile: RhythmProfile
    ) -> RhythmVerificationScore {
        guard let baselineDwell = profile.baselineDwell,
              let baselineFlight = profile.baselineFlight else {
            return RhythmVerificationScore(matchPercentage: 0, averageZScore: .infinity, comparedKeystrokes: 0)
        }

        let count = Double(loginData.count)
        let avgDwell = loginData.reduce(0) { $0 + $1.dwellTime } / count
        let avgFlight = loginData.reduce(0) { $0 + $1.flightTime } / count

        let dwellDiff = relativeDifference(actual: avgDwell, baseline: baselineDwell)
        let flightDiff = relativeDifference(actual: avgFlight, baseline: baselineFlight)
        let totalError = (dwellDiff + flightDiff) / 2
        let matchPercentage = max(0, Int(100 - (totalError * 100)))

        return RhythmVerificationScore(
            matchPercentage: matchPercentage,
            averageZScore: Double(100 - matchPercentage) / 25,
            comparedKeystrokes: loginData.count
        )
    }

    private static func relativeDifference(actual: TimeInterval, baseline: TimeInterval) -> Double {
        guard baseline > 0 else { return 1 }
        return abs(actual - baseline) / baseline
    }
}
