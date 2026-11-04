// SecurityActivityPeriod.swift
// Time ranges for the Security Activity timeline tab bar.
// Flow: Today → Yesterday → Last 7 days (left to right).

import Foundation
import SwiftUI

enum SecurityActivityPeriod: String, CaseIterable, Identifiable {
    case today
    case yesterday
    case last7Days

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .last7Days: return "Last 7 days"
        }
    }

    /// Filters audit events for this period; newest-first ordering is applied by the caller.
    func filter(_ events: [AuditEvent], calendar: Calendar = .current) -> [AuditEvent] {
        let now = Date()

        switch self {
        case .today:
            return events.filter { calendar.isDateInToday($0.timestamp) }

        case .yesterday:
            return events.filter { calendar.isDateInYesterday($0.timestamp) }

        case .last7Days:
            guard let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) else {
                return events
            }
            return events.filter { $0.timestamp >= start }
        }
    }

    var emptyMessage: String {
        switch self {
        case .today: return "No security activity today."
        case .yesterday: return "No security activity yesterday."
        case .last7Days: return "No security activity in the last 7 days."
        }
    }

    /// Distinct accent for timeline copy — separate from per-event dot colors.
    var timelineTextColor: Color {
        switch self {
        case .today:
            return Color(red: 0.88, green: 0.36, blue: 0.62)
        case .yesterday:
            return Color(red: 0.58, green: 0.44, blue: 0.92)
        case .last7Days:
            return Color(red: 0.30, green: 0.68, blue: 0.88)
        }
    }

    /// True when this event falls inside the period window.
    func includes(event: AuditEvent, calendar: Calendar = .current) -> Bool {
        !filter([event], calendar: calendar).isEmpty
    }

    var clearAccessibilityLabel: String {
        switch self {
        case .today: return "Clear today's security activity"
        case .yesterday: return "Clear yesterday's security activity"
        case .last7Days: return "Clear security activity from the last 7 days"
        }
    }
}
