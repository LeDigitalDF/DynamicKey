// TrainingSentenceProvider.swift
// Supplies a randomized subset of sentences for each training session.

import Foundation

enum TrainingSentenceProvider {
    static let trainingCount = 4

    private static let pool = [
        "The quick brown fox jumps over the lazy dog.",
        "Security is not a product, but a process.",
        "Typing dynamics provide a unique digital fingerprint.",
        "Protecting your data requires constant vigilance.",
        "Every keystroke reveals a pattern only you can repeat.",
        "Strong authentication combines something you know and how you type.",
        "Your rhythm is as personal as your handwriting.",
        "Digital trust begins with verifying who is at the keyboard.",
        "Consistent timing helps the app recognize you reliably.",
        "Careful typing during training builds a more accurate profile.",
        "Authentication should be seamless yet difficult to impersonate.",
        "A password alone is never enough for modern security.",
    ]

    static func randomSentences() -> [String] {
        Array(pool.shuffled().prefix(trainingCount))
    }
}
