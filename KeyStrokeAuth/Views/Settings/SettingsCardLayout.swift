// SettingsCardLayout.swift
// Shared height constants so every settings flip-card row renders at the same size.
// Flow: chrome (padding + header + spacing) + fixed front content height = card height.

import SwiftUI

enum SettingsCardLayout {
    /// Fixed height for the control area below each card title row.
    static let frontContentHeight: CGFloat = 96

    /// Padding, title row, and spacing above the front content area.
    private static let chromeHeight: CGFloat = (GlassTheme.padding * 2) + 32 + 12

    /// Standard widget cards — Match Threshold, Touch ID, Launch at Login, etc.
    static let standardCardHeight: CGFloat = chromeHeight + frontContentHeight

    /// Browser Extension + Extension Pairing row — taller so action flip backs show sparkle buttons without scrolling.
    static let extensionPairingFrontContentHeight: CGFloat = frontContentHeight + 42
    static let extensionPairingCardHeight: CGFloat = chromeHeight + extensionPairingFrontContentHeight

    /// Cards with rhythm learning toggle + optional threshold suggestion.
    static let rhythmLearningFrontContentHeightCompact: CGFloat = 52
    static let rhythmLearningFrontContentHeightExpanded: CGFloat = 108

    static func rhythmLearningCardHeight(showsSuggestion: Bool) -> CGFloat {
        chromeHeight + (showsSuggestion
            ? rhythmLearningFrontContentHeightExpanded
            : rhythmLearningFrontContentHeightCompact)
    }

    static func rhythmLearningFrontContentHeight(showsSuggestion: Bool) -> CGFloat {
        showsSuggestion
            ? rhythmLearningFrontContentHeightExpanded
            : rhythmLearningFrontContentHeightCompact
    }

    /// Cards with longer lists — trusted keyboards and trusted networks.
    static let expandedFrontContentHeight: CGFloat = 156
    static let expandedCardHeight: CGFloat = chromeHeight + expandedFrontContentHeight

    /// Security Actions — tall enough for pulse retrain scroll; key back uses a shorter content slot.
    static let securityActionsFrontContentHeight: CGFloat = 108
    static let securityActionsKeyBackContentHeight: CGFloat = 118
    static let securityActionsPulseBackContentHeight: CGFloat = 138
    /// Back button row + title above the flow content.
    private static let securityActionsBackChromeHeight: CGFloat = 54
    static let securityActionsCardHeight: CGFloat =
        chromeHeight + securityActionsPulseBackContentHeight + securityActionsBackChromeHeight

    /// Extra bottom inset inside dual-action flip-card scroll areas so buttons are fully reachable.
    static let scrollContentBottomInset: CGFloat = 24

    /// AI Daily Summary — full-width card; extra front height for segmented control + Muse key field.
    static let dailySummaryAIFrontContentHeight: CGFloat = 168
    static let dailySummaryAICardHeight: CGFloat = chromeHeight + dailySummaryAIFrontContentHeight

    /// Settings grid max width (Home dashboard uses 820; Settings is slightly wider for full-width AI card).
    static let settingsContentMaxWidth: CGFloat = 872
}
