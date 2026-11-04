// HomeDashboardModel.swift
// Derives security score, recent activity rows, and quick-action hints for the Home dashboard.
// Flow: audit events + app health flags → score ring, activity list, contextual shortcuts.

import Foundation

struct HomeActivityRow: Identifiable {
    let id: UUID
    let site: String
    let timestamp: Date
    let matchPercentage: Int?
    let succeeded: Bool
    var isDynamicShield: Bool = false
}

enum HomeDashboardModel {
    private static let activityTypes: Set<AuditEventType> = [
        .loginSuccess,
        .loginFailedPassword,
        .loginFailedRhythm,
        .loginFailedEmpty,
        .loginBlockedLockout,
        .extensionVerifySuccess,
        .extensionVerifyDenied,
        .extensionDynamicShieldTrusted,
        .extensionDynamicShieldWarning,
        .extensionDynamicShieldDismissed,
        .extensionDynamicShieldRemoved,
    ]

    static func securityScore(
        isExtensionAPIRunning: Bool,
        pairedExtensionCount: Int,
        protectedSiteCount: Int,
        showsReenrollmentReminder: Bool,
        lastRhythmMatchPercentage: Int,
        passThreshold: Int
    ) -> Int {
        var score = 45

        if isExtensionAPIRunning { score += 15 }
        if pairedExtensionCount > 0 { score += 15 }
        if protectedSiteCount > 0 { score += 10 }
        if !showsReenrollmentReminder { score += 10 }

        if lastRhythmMatchPercentage >= passThreshold {
            score += 5
        } else if lastRhythmMatchPercentage > 0 {
            score += 2
        }

        return min(100, score)
    }

    static func lastLoginDate(from events: [AuditEvent]) -> Date? {
        events
            .filter { $0.type == .loginSuccess || $0.type == .extensionVerifySuccess }
            .map(\.timestamp)
            .max()
    }

    static func recentActivity(from events: [AuditEvent], limit: Int = 5) -> [HomeActivityRow] {
        events
            .filter { activityTypes.contains($0.type) }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(limit)
            .map { event in
                if SecurityActivityCategory.dynamicShieldEventTypes.contains(event.type) {
                    return HomeActivityRow(
                        id: event.id,
                        site: dynamicShieldLabel(for: event),
                        timestamp: event.timestamp,
                        matchPercentage: nil,
                        succeeded: dynamicShieldSucceeded(for: event.type),
                        isDynamicShield: true
                    )
                }

                return HomeActivityRow(
                    id: event.id,
                    site: siteLabel(for: event),
                    timestamp: event.timestamp,
                    matchPercentage: matchPercentage(from: event.detail),
                    succeeded: event.type == .loginSuccess || event.type == .extensionVerifySuccess
                )
            }
    }

    static func siteLabel(for event: AuditEvent) -> String {
        if let detail = event.detail,
           let origin = detail.split(separator: "—").first?.trimmingCharacters(in: .whitespaces) {
            if origin.lowercased().hasPrefix("http") {
                return displayHost(from: origin)
            }
            if origin.lowercased().hasPrefix("match:") {
                return "Mac sign-in"
            }
        }

        switch event.type {
        case .loginSuccess, .loginFailedPassword, .loginFailedRhythm, .loginFailedEmpty, .loginBlockedLockout:
            return "Mac sign-in"
        case .extensionVerifySuccess, .extensionVerifyDenied:
            return "Browser extension"
        case .extensionDynamicShieldTrusted,
             .extensionDynamicShieldWarning,
             .extensionDynamicShieldDismissed,
             .extensionDynamicShieldRemoved:
            return dynamicShieldLabel(for: event)
        default:
            return "Security event"
        }
    }

    private static func dynamicShieldLabel(for event: AuditEvent) -> String {
        if let detail = event.detail, !detail.isEmpty {
            return "DynamicShield · \(detail)"
        }
        return event.displayTitle
    }

    private static func dynamicShieldSucceeded(for type: AuditEventType) -> Bool {
        switch type {
        case .extensionDynamicShieldTrusted:
            return true
        case .extensionDynamicShieldDismissed:
            return true
        case .extensionDynamicShieldWarning:
            return false
        case .extensionDynamicShieldRemoved:
            return false
        default:
            return false
        }
    }

    private static func displayHost(from origin: String) -> String {
        if let host = URL(string: origin)?.host, !host.isEmpty {
            return host
        }
        return origin
    }

    private static func matchPercentage(from detail: String?) -> Int? {
        guard let detail else { return nil }
        let pattern = /(\d{1,3})%/
        if let match = detail.firstMatch(of: pattern) {
            return Int(match.1)
        }
        return nil
    }
}
