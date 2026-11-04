// LeakPeekRingSummary.swift
// Aggregated safe / compromised / pending counts for the Home donut ring.

import Foundation

struct LeakPeekRingSummary: Equatable {
    let safe: Int
    let compromised: Int
    let pending: Int

    var total: Int {
        safe + compromised + pending
    }

    var isEmpty: Bool {
        total == 0
    }

    /// Builds ring segments from saved credentials and persisted scan statuses.
    static func from(
        credentials: [SiteCredential],
        statusFor: (UUID) -> LeakPeekSiteStatus
    ) -> LeakPeekRingSummary {
        var safe = 0
        var compromised = 0
        var pending = 0

        for credential in credentials {
            switch statusFor(credential.id) {
            case .safe:
                safe += 1
            case .compromised:
                compromised += 1
            case .unknown:
                pending += 1
            }
        }

        return LeakPeekRingSummary(safe: safe, compromised: compromised, pending: pending)
    }
}
