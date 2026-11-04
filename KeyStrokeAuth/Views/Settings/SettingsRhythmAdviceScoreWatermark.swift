// SettingsRhythmAdviceScoreWatermark.swift
// Large suggested threshold % centered behind the Learn my typing rhythm advice row.
// Flow: parent flip card supplies tint + overlay → score sits in the background like trust-card watermarks.

import AppKit
import SwiftUI

enum SettingsRhythmAdviceStyle {
    static let cardTint = NSColor(calibratedRed: 0.10, green: 0.52, blue: 0.30, alpha: 0.30)
    static let adviceLabelColor = Color(red: 0.32, green: 0.88, blue: 0.58)
    static let watermarkSize: CGFloat = 176
}

struct SettingsRhythmAdviceScoreWatermark: View {
    let score: Int

    var body: some View {
        Text("\(score)%")
            .font(.system(size: SettingsRhythmAdviceStyle.watermarkSize, weight: .light))
            .monospacedDigit()
            .foregroundStyle(SettingsRhythmThresholdStyle.color(for: score).opacity(0.38))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .allowsHitTesting(false)
    }
}
