// RhythmProfile.swift
// Per-position typing rhythm profile built from password enrollment samples.

import Foundation

struct RhythmProfile: Codable, Equatable {
    static let currentVersion = 2

    let version: Int
    let positionStats: [PositionTimingStats]
    let enrolledAt: Date

    let baselineDwell: TimeInterval?
    let baselineFlight: TimeInterval?

    var isLegacyProfile: Bool {
        version < Self.currentVersion || positionStats.isEmpty
    }

    init(
        positionStats: [PositionTimingStats],
        enrolledAt: Date = Date()
    ) {
        self.version = Self.currentVersion
        self.positionStats = positionStats
        self.enrolledAt = enrolledAt
        self.baselineDwell = nil
        self.baselineFlight = nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let version = try container.decodeIfPresent(Int.self, forKey: .version),
           version >= Self.currentVersion,
           let positionStats = try container.decodeIfPresent([PositionTimingStats].self, forKey: .positionStats),
           !positionStats.isEmpty {
            self.version = version
            self.positionStats = positionStats
            self.enrolledAt = try container.decodeIfPresent(Date.self, forKey: .enrolledAt) ?? Date()
            self.baselineDwell = nil
            self.baselineFlight = nil
            return
        }

        self.version = 1
        self.positionStats = try container.decodeIfPresent([PositionTimingStats].self, forKey: .positionStats) ?? []
        self.enrolledAt = try container.decodeIfPresent(Date.self, forKey: .enrolledAt) ?? Date()
        self.baselineDwell = try container.decode(TimeInterval.self, forKey: .baselineDwell)
        self.baselineFlight = try container.decode(TimeInterval.self, forKey: .baselineFlight)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(positionStats, forKey: .positionStats)
        try container.encode(enrolledAt, forKey: .enrolledAt)
    }

    static func from(passwordSamples: [[KeystrokeData]], password: String) -> RhythmProfile? {
        guard passwordSamples.count >= EnrollmentConfig.requiredSamples else { return nil }
        guard !password.isEmpty else { return nil }

        let passwordCharacters = Array(password)
        guard passwordSamples.allSatisfy({ $0.count == passwordCharacters.count }) else { return nil }

        var positionStats: [PositionTimingStats] = []

        for index in passwordCharacters.indices {
            let dwellSamples = passwordSamples.map { $0[index].dwellTime }
            let flightSamples = passwordSamples.map { $0[index].flightTime }
            let dwell = TimingStatistics.meanStd(dwellSamples)
            let flight = TimingStatistics.meanStd(flightSamples)

            positionStats.append(
                PositionTimingStats(
                    position: index,
                    character: String(passwordCharacters[index]),
                    meanDwell: dwell.mean,
                    stdDwell: dwell.std,
                    meanFlight: flight.mean,
                    stdFlight: flight.std,
                    sampleCount: passwordSamples.count
                )
            )
        }

        guard !positionStats.isEmpty else { return nil }
        return RhythmProfile(positionStats: positionStats)
    }

    func daysSinceEnrollment(referenceDate: Date = Date()) -> Int {
        Calendar.current.dateComponents([.day], from: enrolledAt, to: referenceDate).day ?? 0
    }

    /// Adaptive learning: folds one genuine login's keystrokes into every position's timing stats.
    /// Returns nil (no change) for legacy profiles or when the sample length doesn't line up exactly
    /// with the stored positions, so only clean, full-length entries refine the model. The original
    /// enrollment date is preserved so the re-enrollment reminder keeps working.
    func learning(from loginData: [KeystrokeData]) -> RhythmProfile? {
        guard !isLegacyProfile else { return nil }
        guard loginData.count == positionStats.count else { return nil }

        let refinedStats = positionStats.map { stats -> PositionTimingStats in
            let keystroke = loginData[stats.position]
            return stats.folding(dwell: keystroke.dwellTime, flight: keystroke.flightTime)
        }

        return RhythmProfile(positionStats: refinedStats, enrolledAt: enrolledAt)
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case positionStats
        case enrolledAt
        case baselineDwell
        case baselineFlight
    }
}
