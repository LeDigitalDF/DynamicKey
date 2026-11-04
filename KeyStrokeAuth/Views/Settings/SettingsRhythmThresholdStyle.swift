// SettingsRhythmThresholdStyle.swift
// Threshold percentage color — easier (50%) is greener, stricter (90%) is redder.

import AppKit
import SwiftUI

enum SettingsRhythmThresholdStyle {
    static func color(for threshold: Int) -> Color {
        let minimum = Double(RhythmSettings.minimumThreshold)
        let maximum = Double(RhythmSettings.maximumThreshold)
        let progress = (Double(threshold) - minimum) / (maximum - minimum)

        if progress < 0.5 {
            return blend(
                from: Color(red: 0.22, green: 0.78, blue: 0.42),
                to: Color(red: 0.95, green: 0.72, blue: 0.18),
                amount: progress * 2
            )
        }

        return blend(
            from: Color(red: 0.95, green: 0.72, blue: 0.18),
            to: Color(red: 0.92, green: 0.28, blue: 0.24),
            amount: (progress - 0.5) * 2
        )
    }

    private static func blend(from: Color, to: Color, amount: Double) -> Color {
        let clamped = min(1, max(0, amount))
        return Color(
            red: lerp(from: rgba(from).red, to: rgba(to).red, amount: clamped),
            green: lerp(from: rgba(from).green, to: rgba(to).green, amount: clamped),
            blue: lerp(from: rgba(from).blue, to: rgba(to).blue, amount: clamped)
        )
    }

    private static func lerp(from: Double, to: Double, amount: Double) -> Double {
        from + ((to - from) * amount)
    }

    private static func rgba(_ color: Color) -> (red: Double, green: Double, blue: Double) {
        let nsColor = NSColor(color)
        guard let converted = nsColor.usingColorSpace(.sRGB) else {
            return (0.5, 0.5, 0.5)
        }
        return (Double(converted.redComponent), Double(converted.greenComponent), Double(converted.blueComponent))
    }
}
