// ManualAllowlistFlipCard.swift
// Flip card for adding a website to the allowlist — + watermark front; back collects origin then saves.
// Flow: + watermark front → enter origin → Add to Allowlist sparkle button → flip back.

import SwiftUI

private let manualAddCardTrueBlack = Color(red: 0, green: 0, blue: 0)

struct ManualAllowlistFlipCard: View {
    let onAdd: (String) -> Void
    let onFlipChanged: (Bool) -> Void

    @Environment(\.glassPalette) private var palette
    @FocusState private var isOriginFieldFocused: Bool
    @State private var origin = ""
    @State private var isFlipped = false
    @State private var isPlusWatermarkHovered = false

    private let originPlaceholder = "e.g. spotify.com"
    private let accentColor: Color = .green

    /// Matches saved list card height in the twin-column grid.
    private let cardHeight: CGFloat = 220

    private let backContentPadding = EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)

    init(
        onAdd: @escaping (String) -> Void,
        onFlipChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.onAdd = onAdd
        self.onFlipChanged = onFlipChanged
    }

    private var canAdd: Bool {
        !origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            cardFront
                .opacity(isFlipped ? 0 : 1)
                .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                .allowsHitTesting(!isFlipped)

            cardBack
                .opacity(isFlipped ? 1 : 0)
                .rotation3DEffect(.degrees(isFlipped ? 0 : -180), axis: (x: 0, y: 1, z: 0))
                .allowsHitTesting(isFlipped)
        }
        .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: isFlipped)
        .onChange(of: isFlipped) { _, flipped in
            onFlipChanged(flipped)
        }
    }

    // Front — + watermark centered; hover/tap on the icon zone.
    private var cardFront: some View {
        ZStack {
            SettingsPlusActionWatermark(isHovered: isPlusWatermarkHovered)

            Text("Add Website to Allowlist")
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .foregroundStyle(.primary)
                .padding(.horizontal, GlassTheme.padding)
                .zIndex(1)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight)
        .background { manualCardBackground }
        .clipShape(RoundedRectangle(cornerRadius: GlassTheme.cornerRadius, style: .continuous))
        .overlay {
            GeometryReader { geometry in
                let interactionSide = min(geometry.size.width, geometry.size.height) * 0.78

                Color.clear
                    .frame(width: interactionSide, height: interactionSide)
                    .position(x: geometry.size.width * 0.5, y: geometry.size.height * 0.5)
                    .contentShape(Rectangle())
                    .onHover { isPlusWatermarkHovered = $0 }
                    .onTapGesture(perform: flipToBack)
                    .accessibilityElement()
                    .accessibilityLabel("Add website to allowlist")
                    .accessibilityAddTraits(.isButton)
            }
        }
    }

    // Back — round glass back control, then form content inset below the header row.
    private var cardBack: some View {
        VStack(alignment: .leading, spacing: 0) {
            GlassCircleIconButton(
                systemImage: "chevron.left",
                accessibilityLabel: "Back",
                size: 30,
                iconColor: accentColor,
                action: cancelBack
            )

            VStack(alignment: .leading, spacing: 10) {
                Text("Add Website to Allowlist")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .center)

                Text("Enter the website origin. Subdomains of the same site share one entry.")
                    .font(.caption)
                    .foregroundStyle(palette.onGlassSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Website")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.onGlassSecondary)

                    ManualAllowlistInputField(
                        text: $origin,
                        placeholder: originPlaceholder,
                        isFocused: $isOriginFieldFocused
                    )
                }

                if canAdd {
                    HStack {
                        Spacer(minLength: 0)

                        LiquidGlassSparkleButton(
                            title: "Add to Allowlist",
                            sparklePalette: .green,
                            titleColor: manualAddCardTrueBlack,
                            action: addOrigin
                        )

                        Spacer(minLength: 0)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.top, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(backContentPadding)
        .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight, alignment: .topLeading)
        .background { manualCardBackground }
        .clipShape(RoundedRectangle(cornerRadius: GlassTheme.cornerRadius, style: .continuous))
    }

    private var manualCardBackground: some View {
        LiquidGlassSurface(
            cornerRadius: GlassTheme.cornerRadius,
            tintColor: NSColor(
                calibratedRed: 0.18,
                green: 0.78,
                blue: 0.42,
                alpha: 0.22
            )
        )
    }

    private func addOrigin() {
        let trimmedOrigin = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOrigin.isEmpty else { return }

        onAdd(trimmedOrigin)
        resetBackForm()
        flipToFront()
    }

    private func flipToBack() {
        isFlipped = true
    }

    private func flipToFront() {
        isFlipped = false
        isOriginFieldFocused = false
    }

    private func cancelBack() {
        resetBackForm()
        flipToFront()
    }

    private func resetBackForm() {
        origin = ""
        isOriginFieldFocused = false
    }
}

// Compact text field with a thin custom border — matches the manual credential card back.
private struct ManualAllowlistInputField: View {
    @Environment(\.glassPalette) private var palette

    @Binding var text: String
    let placeholder: String
    @FocusState.Binding var isFocused: Bool

    var body: some View {
        TextField("", text: $text)
            .manualAllowlistInputStyle(isFocused: isFocused)
            .focused($isFocused)
            .overlay(alignment: .leading) {
                if text.isEmpty && !isFocused {
                    Text(placeholder)
                        .font(.callout)
                        .foregroundStyle(palette.fieldPlaceholder)
                        .padding(.horizontal, 8)
                        .allowsHitTesting(false)
                }
            }
    }
}

private extension View {
    func manualAllowlistInputStyle(isFocused: Bool) -> some View {
        textFieldStyle(.plain)
            .font(.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        isFocused ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.16),
                        lineWidth: isFocused ? 1 : 0.5
                    )
            }
            .focusEffectDisabled()
    }
}
