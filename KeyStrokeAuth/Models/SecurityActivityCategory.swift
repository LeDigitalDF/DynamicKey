// SecurityActivityCategory.swift
// Filters Security Activity timeline rows by sign-in vs DynamicShield email events.
// Flow: All → every event; Sign-in → auth/extension; Shield → trusted/warning/dismiss/remove.

import Foundation
import SwiftUI

enum SecurityActivityCategory: String, CaseIterable, Identifiable {
    case all
    case authentication
    case dynamicShield

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .authentication: return "Sign-in"
        case .dynamicShield: return "Shield"
        }
    }

    /// SF Symbol shown before the category label in the top segmented picker.
    var symbolName: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .authentication: return "key.fill"
        case .dynamicShield: return "shield.fill"
        }
    }

    /// Accent for the category tab thumb and filtered timeline copy.
    var timelineTextColor: Color {
        switch self {
        case .all:
            return Color.primary
        case .authentication:
            return Color(red: 0.34, green: 0.58, blue: 0.98)
        case .dynamicShield:
            return Color(red: 0.22, green: 0.78, blue: 0.86)
        }
    }

    static let dynamicShieldEventTypes: Set<AuditEventType> = [
        .extensionDynamicShieldTrusted,
        .extensionDynamicShieldWarning,
        .extensionDynamicShieldDismissed,
        .extensionDynamicShieldRemoved,
    ]

    /// Whether an audit event belongs in this category filter.
    func matches(_ event: AuditEvent) -> Bool {
        switch self {
        case .all:
            return true
        case .authentication:
            return !Self.dynamicShieldEventTypes.contains(event.type)
        case .dynamicShield:
            return Self.dynamicShieldEventTypes.contains(event.type)
        }
    }

    /// Empty-state copy when a period has no rows for this category.
    func emptyMessage(for period: SecurityActivityPeriod) -> String {
        switch self {
        case .all:
            return period.emptyMessage
        case .authentication:
            switch period {
            case .today: return "No sign-in activity today."
            case .yesterday: return "No sign-in activity yesterday."
            case .last7Days: return "No sign-in activity in the last 7 days."
            }
        case .dynamicShield:
            switch period {
            case .today: return "No DynamicShield activity today."
            case .yesterday: return "No DynamicShield activity yesterday."
            case .last7Days: return "No DynamicShield activity in the last 7 days."
            }
        }
    }
}
