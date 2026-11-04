// LettertypeTitleView.swift
// Renders a phrase from Lettertype PNG assets in Assets.xcassets/Lettertype/.
// Uppercase letters use the letter name (e.g. "T"); lowercase use "S_" + letter (e.g. "S_e" → asset "S_E").
// Flow: split phrase (preserve case) → resolve asset per character → optional wiggle → text fallback.

import SwiftUI
import AppKit

struct LettertypeTitleView: View {
    @Environment(\.colorScheme) private var colorScheme

    var phrase: String
    var letterHeight: CGFloat = 40
    var letterSpacing: CGFloat = 0
    var wordSpacing: CGFloat = 12
    var lineSpacing: CGFloat = 6
    var animate: Bool = false
    /// Drop shadow on each PNG letter — used for the animated Welcome title in Light Mode.
    var showsLetterDropShadow: Bool = false

    var body: some View {
        Group {
            if animate {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    titleContent(at: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                titleContent(at: 0)
            }
        }
        .accessibilityLabel(phrase.replacingOccurrences(of: "\n", with: " "))
    }

    private var lines: [[LetterToken]] {
        phrase
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { Self.tokens(from: String($0)) }
    }

    private func titleContent(at time: Double) -> some View {
        VStack(spacing: lineSpacing) {
            ForEach(Array(lines.enumerated()), id: \.offset) { lineIndex, lineTokens in
                titleRow(tokens: lineTokens, lineIndex: lineIndex, at: time)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func titleRow(tokens: [LetterToken], lineIndex: Int, at time: Double) -> some View {
        HStack(spacing: letterSpacing) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                let globalIndex = lineIndex * 100 + index
                switch token {
                case .space:
                    Spacer().frame(width: wordSpacing)
                case .letter(let character):
                    letterView(character: character, index: globalIndex, at: time)
                }
            }
        }
    }

    @ViewBuilder
    private func letterView(character: Character, index: Int, at time: Double) -> some View {
        if let assetName = Self.assetName(for: character) {
            let image = Image(assetName)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(height: letterHeight)

            if animate {
                letterImage(image, character: character, index: index, at: time)
            } else {
                letterImage(image, character: character, index: index, at: time, appliesWiggle: false)
            }
        } else {
            Text(String(character))
                .font(.system(size: letterHeight * 0.72, weight: .bold, design: .rounded))
                .frame(height: letterHeight)
        }
    }

    @ViewBuilder
    private func letterImage(
        _ image: some View,
        character: Character,
        index: Int,
        at time: Double,
        appliesWiggle: Bool = true
    ) -> some View {
        let rendered = Group {
            if appliesWiggle {
                image
                    .offset(
                        x: wiggleX(for: index, at: time),
                        y: wiggleY(for: index, at: time)
                    )
                    .rotationEffect(.degrees(wiggleRotation(for: index, at: time)), anchor: .bottom)
            } else {
                image
            }
        }

        if showsLetterDropShadow && colorScheme == .light {
            rendered
                .shadow(color: Color.black.opacity(0.20), radius: 4, x: 0, y: 3)
                .shadow(color: Color.black.opacity(0.10), radius: 1.5, x: 0, y: 1)
        } else {
            rendered
        }
    }

    private func wiggleX(for index: Int, at time: Double) -> CGFloat {
        let phase = Double(index) * 0.91
        return sin(time * (1.35 + Double(index) * 0.07) + phase) * (2.0 + CGFloat(index % 3))
    }

    private func wiggleY(for index: Int, at time: Double) -> CGFloat {
        let phase = Double(index) * 0.91
        return cos(time * (1.55 + Double(index) * 0.05) + phase * 1.2) * (2.5 + CGFloat((index + 1) % 4))
    }

    private func wiggleRotation(for index: Int, at time: Double) -> Double {
        let phase = Double(index) * 0.91
        return sin(time * (1.25 + Double(index) * 0.06) + phase * 0.85) * (3.0 + Double(index % 5) * 0.4)
    }

    private enum LetterToken {
        case letter(Character)
        case space
    }

    private static func tokens(from phrase: String) -> [LetterToken] {
        phrase.compactMap { character in
            if character.isWhitespace {
                return .space
            }
            if character.isLetter {
                return .letter(character)
            }
            return nil
        }
    }

    /// Uppercase → "A"; lowercase → "S_A" (imageset name). Falls back to uppercase asset when small caps are missing.
    static func assetName(for character: Character) -> String? {
        guard character.isLetter else { return nil }

        if character.isUppercase {
            let name = String(character)
            return hasAsset(named: name) ? name : nil
        }

        let smallCapsName = "S_\(String(character).uppercased())"
        if hasAsset(named: smallCapsName) {
            return smallCapsName
        }

        let uppercaseName = String(character).uppercased()
        if hasAsset(named: uppercaseName) {
            return uppercaseName
        }

        return nil
    }

    static func hasAsset(named name: String) -> Bool {
        NSImage(named: name) != nil
    }
}
