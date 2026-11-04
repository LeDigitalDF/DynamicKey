// PairingCodeExpiryCountdown.swift
// Live pairing-code expiry label — updates every second until the code expires.
// Flow: TimelineView tick → mm:ss remaining → optional callback when time runs out.

import SwiftUI

struct PairingCodeExpiryCountdown: View {
    let expiresAt: Date
    var onExpired: (() -> Void)? = nil

    @State private var didReportExpiry = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
            let remaining = max(0, expiresAt.timeIntervalSince(timeline.date))
            Text(formattedRemaining(remaining))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(remaining <= 60 ? Color.orange : Color.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .onAppear {
                    reportExpiryIfNeeded(for: remaining)
                }
                .onChange(of: Int(remaining.rounded(.down))) { _, _ in
                    reportExpiryIfNeeded(for: remaining)
                }
        }
        .onChange(of: expiresAt) { _, _ in
            didReportExpiry = false
        }
    }

    private func formattedRemaining(_ remaining: TimeInterval) -> String {
        if remaining <= 0 {
            return "Expired"
        }

        let totalSeconds = Int(remaining.rounded(.down))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "Expires in %d:%02d", minutes, seconds)
    }

    private func reportExpiryIfNeeded(for remaining: TimeInterval) {
        guard remaining <= 0, !didReportExpiry else { return }
        didReportExpiry = true
        onExpired?()
    }
}
