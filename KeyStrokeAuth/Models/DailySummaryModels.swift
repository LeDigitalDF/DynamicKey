// DailySummaryModels.swift
// Privacy-safe count aggregates for the Home Daily Summary card (no emails, sites, or log text).
// Flow: MorningSummaryService builds counts → verdict string → Muse or local sentence → UI facts.

import Foundation

/// Suggested follow-up surfaced as the single “action for today”.
enum DailySummaryAction: String, Codable, Equatable {
    case reviewFailedSignIns
    case retrainTypingProfile
    case runLeakPeekScan
    case reviewCompromisedPasswords
    case none

    var buttonTitle: String {
        switch self {
        case .reviewFailedSignIns: return "Review sign-in activity"
        case .retrainTypingProfile: return "Retrain typing profile"
        case .runLeakPeekScan: return "Run LeakPeek scan"
        case .reviewCompromisedPasswords: return "Review compromised passwords"
        case .none: return "You're all set"
        }
    }
}

/// Count-only snapshot shown under the summary sentence.
struct DailySummaryCounts: Equatable, Codable {
    var overnightSuccessfulSignIns: Int
    var overnightFailedSignIns: Int
    var overnightLowRhythmSignIns: Int
    var overnightUnusualSignIns: Int
    var leakPeekNewLeaks: Int
    var leakPeekCompromisedTotal: Int
    var leakPeekScannedSinceOvernight: Bool
    var passwordsNeedingAttention: Int
    var suggestedAction: DailySummaryAction
}

/// Cached presentation for one calendar day.
struct DailySummaryPresentation: Equatable, Codable {
    var calendarDay: Date
    var headline: String
    var counts: DailySummaryCounts
    var usedMuseAI: Bool
}

/// Singular/plural copy for Daily Summary facts, local headlines, and Muse verdict text.
enum DailySummaryWording {
    static func formattedCount(_ n: Int, singular: String, plural: String) -> String {
        n == 1 ? "1 \(singular)" : "\(n) \(plural)"
    }

    static func overnightSignInsFactLine(_ counts: DailySummaryCounts) -> String {
        let ok = formattedCount(counts.overnightSuccessfulSignIns, singular: "successful sign-in", plural: "successful sign-ins")
        let failed = formattedCount(counts.overnightFailedSignIns, singular: "failed sign-in", plural: "failed sign-ins")
        let unusual = formattedCount(counts.overnightUnusualSignIns, singular: "unusual sign-in", plural: "unusual sign-ins")
        return "\(ok) · \(failed) · \(unusual)"
    }

    static func leakPeekFactLine(_ counts: DailySummaryCounts) -> String {
        if counts.leakPeekScannedSinceOvernight {
            let newLeaks = formattedCount(counts.leakPeekNewLeaks, singular: "new leak", plural: "new leaks")
            let compromised = formattedCount(
                counts.leakPeekCompromisedTotal,
                singular: "compromised password total",
                plural: "compromised passwords total"
            )
            return "\(newLeaks) · \(compromised)"
        }
        let saved = formattedCount(
            counts.leakPeekCompromisedTotal,
            singular: "compromised saved password",
            plural: "compromised saved passwords"
        )
        return "No scan overnight · \(saved)"
    }

    static func passwordsToReviewFactLine(_ count: Int) -> String {
        formattedCount(count, singular: "password-related item", plural: "password-related items")
    }

    static func suggestedActionSentence(_ action: DailySummaryAction) -> String {
        switch action {
        case .reviewFailedSignIns:
            return "Suggested action for today: review sign-in activity."
        case .retrainTypingProfile:
            return "Suggested action for today: retrain your typing profile."
        case .runLeakPeekScan:
            return "Suggested action for today: run a LeakPeek scan."
        case .reviewCompromisedPasswords:
            return "Suggested action for today: review compromised passwords."
        case .none:
            return "Suggested action for today: no urgent follow-up."
        }
    }

    static func verdictPrompt(from counts: DailySummaryCounts) -> String {
        let succeeded = formattedCount(counts.overnightSuccessfulSignIns, singular: "sign-in succeeded", plural: "sign-ins succeeded")
        let failed = formattedCount(counts.overnightFailedSignIns, singular: "sign-in failed", plural: "sign-ins failed")
        let lowRhythm = formattedCount(
            counts.overnightLowRhythmSignIns,
            singular: "low rhythm match",
            plural: "low rhythm matches"
        )
        let unusual = formattedCount(counts.overnightUnusualSignIns, singular: "unusual sign-in flagged", plural: "unusual sign-ins flagged")
        let newLeaks = formattedCount(counts.leakPeekNewLeaks, singular: "newly compromised password since last summary", plural: "newly compromised passwords since last summary")
        let compromisedTotal = formattedCount(
            counts.leakPeekCompromisedTotal,
            singular: "compromised saved password total",
            plural: "compromised saved passwords total"
        )
        let attention = passwordsToReviewFactLine(counts.passwordsNeedingAttention)
        let scanned = counts.leakPeekScannedSinceOvernight ? "yes" : "no"
        let action = suggestedActionSentence(counts.suggestedAction)

        return """
        DynamicKey daily security brief (counts only): \
        Overnight sign-ins: \(succeeded), \(failed), \(lowRhythm), \(unusual). \
        LeakPeek: \(newLeaks), \(compromisedTotal), scanned overnight: \(scanned). \
        Passwords needing attention: \(attention). \
        \(action)
        """
    }

    static func localHeadline(from counts: DailySummaryCounts) -> String {
        if counts.overnightUnusualSignIns > 0 {
            let events = formattedCount(
                counts.overnightUnusualSignIns,
                singular: "unusual sign-in event",
                plural: "unusual sign-in events"
            )
            let items = passwordsToReviewFactLine(counts.passwordsNeedingAttention)
            return "Overnight, DynamicKey logged \(events). Review Security Activity and take care of \(items) when you can."
        }
        if counts.leakPeekCompromisedTotal > 0 {
            let passwords = formattedCount(
                counts.leakPeekCompromisedTotal,
                singular: "compromised saved password",
                plural: "compromised saved passwords"
            )
            return "Your vault looks steady overnight. LeakPeek still shows \(passwords) — plan time to rotate them today."
        }
        if counts.passwordsNeedingAttention > 0 {
            let items = passwordsToReviewFactLine(counts.passwordsNeedingAttention)
            return "No unusual overnight sign-ins. You still have \(items) worth a look today."
        }
        return "Quiet night — no unusual sign-ins and no compromised passwords flagged. You're in good shape for today."
    }
}

enum DailySummaryAIProvider: String, CaseIterable, Codable, Identifiable {
    case local
    case muse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .local: return "Local AI"
        case .muse: return "Muse AI"
        }
    }

    var subtitle: String {
        switch self {
        case .local:
            return "Uses a template on this Mac. No network call."
        case .muse:
            return "Sends a short count summary to Muse Spark. Never sends passwords or site names."
        }
    }
}
