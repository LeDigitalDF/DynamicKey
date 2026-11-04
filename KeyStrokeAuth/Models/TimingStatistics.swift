// TimingStatistics.swift
// Mean and standard deviation helpers for keystroke timing samples.

import Foundation

enum TimingStatistics {
    static let minimumStd: TimeInterval = 0.015

    static func meanStd(_ values: [TimeInterval]) -> (mean: TimeInterval, std: TimeInterval) {
        guard !values.isEmpty else { return (0, minimumStd) }
        let mean = values.reduce(0, +) / Double(values.count)
        guard values.count > 1 else { return (mean, minimumStd) }

        let variance = values.reduce(0) { partial, value in
            partial + pow(value - mean, 2)
        } / Double(values.count)

        return (mean, max(sqrt(variance), minimumStd))
    }
}
