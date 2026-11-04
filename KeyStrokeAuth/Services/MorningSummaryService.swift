// MorningSummaryService.swift
// Builds Daily Summary counts on first launch of the day, caches through midnight, optional Muse wording.
// Flow: Home appears → load cache or aggregate audit + LeakPeek → local or Muse headline → publish.

import Combine
import Foundation

@MainActor
final class MorningSummaryService: ObservableObject {
    static let shared = MorningSummaryService()

    @Published private(set) var presentation: DailySummaryPresentation?
    @Published private(set) var isGenerating = false
    /// Set only after “Test summary” on Home — confirms Local vs Muse path for debugging.
    @Published private(set) var testRegenerationStatus: String?
    @Published var isMinimized: Bool {
        didSet { UserDefaults.standard.set(isMinimized, forKey: Keys.minimized) }
    }

    private enum Keys {
        static let cachedPresentation = "dynamicKey.dailySummary.presentation"
        static let cachedDay = "dynamicKey.dailySummary.day"
        static let lastLeakCompromisedBaseline = "dynamicKey.dailySummary.leakBaseline"
        static let minimized = "dynamicKey.dailySummary.minimized"
    }
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        isMinimized = UserDefaults.standard.bool(forKey: Keys.minimized)
        loadCachedPresentationIfStillToday()
    }

    /// Call when Home appears — no-op if today’s summary is already cached.
    func prepareDailySummaryIfNeeded(
        auditEvents: [AuditEvent],
        passThreshold: Int,
        showsReenrollmentReminder: Bool,
        compromisedPasswordCount: Int,
        leakPeekLastScanDate: Date?,
        aiProvider: DailySummaryAIProvider
    ) async {
        let todayStart = Calendar.current.startOfDay(for: Date())
        if let presentation, Calendar.current.isDate(presentation.calendarDay, inSameDayAs: todayStart) {
            return
        }

        isGenerating = true
        defer { isGenerating = false }

        let result = await generatePresentation(
            auditEvents: auditEvents,
            passThreshold: passThreshold,
            showsReenrollmentReminder: showsReenrollmentReminder,
            compromisedPasswordCount: compromisedPasswordCount,
            leakPeekLastScanDate: leakPeekLastScanDate,
            aiProvider: aiProvider,
            includeTestStatus: false
        )
        presentation = result.presentation
        persist(result.presentation, compromisedBaseline: compromisedPasswordCount)
    }

    /// Forces a fresh headline for today using the selected AI provider (ignores cache). Testing only.
    func regenerateDailySummaryForTesting(
        auditEvents: [AuditEvent],
        passThreshold: Int,
        showsReenrollmentReminder: Bool,
        compromisedPasswordCount: Int,
        leakPeekLastScanDate: Date?,
        aiProvider: DailySummaryAIProvider
    ) async {
        isGenerating = true
        defer { isGenerating = false }

        let result = await generatePresentation(
            auditEvents: auditEvents,
            passThreshold: passThreshold,
            showsReenrollmentReminder: showsReenrollmentReminder,
            compromisedPasswordCount: compromisedPasswordCount,
            leakPeekLastScanDate: leakPeekLastScanDate,
            aiProvider: aiProvider,
            includeTestStatus: true
        )
        presentation = result.presentation
        persist(result.presentation, compromisedBaseline: compromisedPasswordCount)
        testRegenerationStatus = result.testStatus
    }

    func clearCacheForTesting() {
        presentation = nil
        UserDefaults.standard.removeObject(forKey: Keys.cachedPresentation)
        UserDefaults.standard.removeObject(forKey: Keys.cachedDay)
    }

    // MARK: - Generation

    private struct GenerationResult {
        var presentation: DailySummaryPresentation
        var testStatus: String?
    }

    private func generatePresentation(
        auditEvents: [AuditEvent],
        passThreshold: Int,
        showsReenrollmentReminder: Bool,
        compromisedPasswordCount: Int,
        leakPeekLastScanDate: Date?,
        aiProvider: DailySummaryAIProvider,
        includeTestStatus: Bool
    ) async -> GenerationResult {
        let todayStart = Calendar.current.startOfDay(for: Date())
        let counts = Self.buildCounts(
            auditEvents: auditEvents,
            passThreshold: passThreshold,
            showsReenrollmentReminder: showsReenrollmentReminder,
            compromisedPasswordCount: compromisedPasswordCount,
            leakPeekLastScanDate: leakPeekLastScanDate
        )

        let verdict = DailySummaryWording.verdictPrompt(from: counts)
        var headline = DailySummaryWording.localHeadline(from: counts)
        var usedMuse = false
        var testStatus: String?

        switch aiProvider {
        case .local:
            if includeTestStatus {
                testStatus = "Test run: Local AI template — compare wording after switching to Muse AI."
            }
        case .muse:
            if let apiKey = MetaAPIKeychainStore.loadAPIKey() {
                do {
                    headline = try await MetaExplanationService.fetchExplanation(
                        verdictPrompt: verdict,
                        apiKey: apiKey,
                        logRawResponseBody: includeTestStatus
                    )
                    usedMuse = true
                    if includeTestStatus {
                        testStatus = "Test run: Muse Spark API succeeded — headline above is from Muse."
                    }
                } catch {
                    headline = DailySummaryWording.localHeadline(from: counts)
                    if includeTestStatus {
                        testStatus =
                            "Test run: Muse API failed (\(Self.museErrorDescription(error))). Local template shown instead."
                    }
                }
            } else if includeTestStatus {
                testStatus = "Test run: No Meta API key in Settings — local template shown instead of Muse."
            }
        }

        let bundle = DailySummaryPresentation(
            calendarDay: todayStart,
            headline: headline,
            counts: counts,
            usedMuseAI: usedMuse
        )
        return GenerationResult(presentation: bundle, testStatus: testStatus)
    }

    private static func museErrorDescription(_ error: Error) -> String {
        if case MetaExplanationError.httpStatus(let code, let detail) = error {
            if let detail, !detail.isEmpty {
                return "HTTP \(code) — \(detail)"
            }
            return "HTTP \(code)"
        }
        if case MetaExplanationError.emptyResponse(let usage) = error {
            if let usage {
                return "empty response — \(usage.diagnosticSummary)"
            }
            return "empty response"
        }
        if case MetaExplanationError.unparseableBody = error {
            return "unparseable body"
        }
        return error.localizedDescription
    }

    // MARK: - Aggregation

    private static func buildCounts(
        auditEvents: [AuditEvent],
        passThreshold: Int,
        showsReenrollmentReminder: Bool,
        compromisedPasswordCount: Int,
        leakPeekLastScanDate: Date?
    ) -> DailySummaryCounts {
        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let overnightStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart

        let overnightEvents = auditEvents.filter { event in
            event.timestamp >= overnightStart && event.timestamp < todayStart
        }

        let signInTypes: Set<AuditEventType> = [
            .loginSuccess,
            .loginFailedPassword,
            .loginFailedRhythm,
            .loginFailedEmpty,
            .loginBlockedLockout,
            .loginFailedUntrustedKeyboard,
            .loginFailedUntrustedNetwork,
            .extensionVerifySuccess,
            .extensionVerifyDenied,
        ]

        let signIns = overnightEvents.filter { signInTypes.contains($0.type) }
        var successful = 0
        var failed = 0
        var lowRhythm = 0

        for event in signIns {
            switch event.type {
            case .loginSuccess, .extensionVerifySuccess:
                successful += 1
                if let match = Self.rhythmMatchPercentage(from: event.detail),
                   match < passThreshold {
                    lowRhythm += 1
                }
            case .loginFailedPassword, .loginFailedRhythm, .loginFailedEmpty,
                 .loginBlockedLockout, .loginFailedUntrustedKeyboard, .loginFailedUntrustedNetwork,
                 .extensionVerifyDenied:
                failed += 1
            default:
                break
            }
        }

        let unusual = failed + lowRhythm

        let scannedSinceOvernight: Bool = {
            guard let leakPeekLastScanDate else { return false }
            return leakPeekLastScanDate >= overnightStart
        }()

        let baseline = UserDefaults.standard.integer(forKey: Keys.lastLeakCompromisedBaseline)
        let newLeaks = scannedSinceOvernight ? max(0, compromisedPasswordCount - baseline) : 0

        var attention = compromisedPasswordCount
        if showsReenrollmentReminder { attention += 1 }

        let action = suggestedAction(
            failedSignIns: failed,
            compromisedCount: compromisedPasswordCount,
            showsReenrollment: showsReenrollmentReminder,
            scannedSinceOvernight: scannedSinceOvernight
        )

        return DailySummaryCounts(
            overnightSuccessfulSignIns: successful,
            overnightFailedSignIns: failed,
            overnightLowRhythmSignIns: lowRhythm,
            overnightUnusualSignIns: unusual,
            leakPeekNewLeaks: newLeaks,
            leakPeekCompromisedTotal: compromisedPasswordCount,
            leakPeekScannedSinceOvernight: scannedSinceOvernight,
            passwordsNeedingAttention: attention,
            suggestedAction: action
        )
    }

    private static func suggestedAction(
        failedSignIns: Int,
        compromisedCount: Int,
        showsReenrollment: Bool,
        scannedSinceOvernight: Bool
    ) -> DailySummaryAction {
        if compromisedCount > 0 { return .reviewCompromisedPasswords }
        if failedSignIns > 0 { return .reviewFailedSignIns }
        if showsReenrollment { return .retrainTypingProfile }
        if !scannedSinceOvernight { return .runLeakPeekScan }
        return .none
    }

    // MARK: - Cache

    private func loadCachedPresentationIfStillToday() {
        guard
            let day = UserDefaults.standard.object(forKey: Keys.cachedDay) as? Date,
            Calendar.current.isDateInToday(day),
            let data = UserDefaults.standard.data(forKey: Keys.cachedPresentation),
            let decoded = try? decoder.decode(DailySummaryPresentation.self, from: data)
        else {
            return
        }
        presentation = decoded
    }

    private func persist(_ bundle: DailySummaryPresentation, compromisedBaseline: Int) {
        if let data = try? encoder.encode(bundle) {
            UserDefaults.standard.set(data, forKey: Keys.cachedPresentation)
            UserDefaults.standard.set(bundle.calendarDay, forKey: Keys.cachedDay)
        }
        UserDefaults.standard.set(compromisedBaseline, forKey: Keys.lastLeakCompromisedBaseline)
    }

    private static func rhythmMatchPercentage(from detail: String?) -> Int? {
        guard let detail else { return nil }
        let pattern = /(\d{1,3})%/
        if let match = detail.firstMatch(of: pattern) {
            return Int(match.1)
        }
        return nil
    }
}
