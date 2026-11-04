// AuditLogService.swift
// Persists a rolling local log of security-related events (M3.6).

import Foundation

final class AuditLogService {
    static let shared = AuditLogService()

    private let storageKey = "LeDigital.KeyStrokeAuth.auditLog"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    func events() -> [AuditEvent] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? decoder.decode([AuditEvent].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.timestamp > $1.timestamp }
    }

    func append(_ event: AuditEvent) {
        var current = events()
        current.insert(event, at: 0)
        if current.count > SecurityConfig.auditLogMaxEntries {
            current = Array(current.prefix(SecurityConfig.auditLogMaxEntries))
        }
        if let data = try? encoder.encode(current) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    /// Removes audit events whose timestamps fall inside the given period window.
    func clearEvents(for period: SecurityActivityPeriod, calendar: Calendar = .current) {
        let remaining = events().filter { !period.includes(event: $0, calendar: calendar) }
        if let data = try? encoder.encode(remaining) {
            UserDefaults.standard.set(data, forKey: storageKey)
        } else if remaining.isEmpty {
            clear()
        }
    }
}
