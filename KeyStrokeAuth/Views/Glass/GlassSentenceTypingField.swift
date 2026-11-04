// GlassRoundedGlassSurface.swift
// Rounded liquid glass surface for multiline sentence typing fields.

import SwiftUI

struct GlassRoundedGlassSurface: View {
    @Environment(\.glassPalette) private var palette

    var cornerRadius: CGFloat = GlassTheme.cornerRadius
    var tint: GlassCapsuleTint = .none

    var body: some View {
        ZStack {
            baseGlassFill
            tintOverlay
        }
        .overlay { innerTopHighlight }
        .overlay { GlassGradientBorder(cornerRadius: cornerRadius) }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: palette.shadowStrong, radius: 8, x: 0, y: 4)
        .shadow(color: palette.shadowSoft, radius: 2, x: 0, y: 1)
    }

    private var baseGlassFill: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [palette.surfaceTop, palette.surfaceMid, palette.surfaceBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(palette.materialOpacity)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [palette.specularTop, palette.specularMid, palette.specularBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }

    @ViewBuilder
    private var tintOverlay: some View {
        switch tint {
        case .none:
            EmptyView()
        case .verify:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(GlassTheme.verifyGradient)
                .opacity(0.52)
        case .blue:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.58),
                            Color(red: 0.12, green: 0.28, blue: 0.72).opacity(0.48),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        case .enroll:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.purple.opacity(0.58),
                            Color(red: 0.42, green: 0.16, blue: 0.72).opacity(0.50),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        case .orange:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.orange.opacity(0.62),
                            Color(red: 0.72, green: 0.36, blue: 0.08).opacity(0.52),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        case .green:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.green.opacity(0.58),
                            Color(red: 0.10, green: 0.52, blue: 0.28).opacity(0.50),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        case .neutral:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(palette.onGlassPrimary.opacity(0.08))
        case .destructive:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.red.opacity(0.58),
                            Color(red: 0.55, green: 0.10, blue: 0.14).opacity(0.50),
                        ],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    )
                )
        }
    }

    private var innerTopHighlight: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [palette.borderHighlightStrong.opacity(0.22), Color.clear],
                    startPoint: .top,
                    endPoint: .center
                ),
                lineWidth: 0.75
            )
            .padding(1.5)
            .blendMode(.overlay)
    }
}

struct GlassSentenceTypingField: View {
    @Environment(\.glassPalette) private var palette

    let typedText: String
    let placeholder: String
    let onKeystroke: (KeystrokeData) -> Void

    @State private var isCursorVisible = true

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .leading) {
                GlassRoundedGlassSurface(tint: .none)

                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    if typedText.isEmpty {
                        Rectangle()
                            .frame(width: 2, height: 18)
                            .foregroundStyle(palette.fieldCaret)
                            .opacity(isCursorVisible ? 1 : 0)

                        Text(placeholder)
                            .foregroundStyle(palette.fieldPlaceholder)
                    } else {
                        Text(typedText)
                            .foregroundStyle(palette.onGlassPrimary)

                        Rectangle()
                            .frame(width: 2, height: 18)
                            .foregroundStyle(palette.fieldCaret)
                            .opacity(isCursorVisible ? 1 : 0)
                    }
                }
                .font(.body)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)

                KeystrokeMonitorViewRepresentable(onKeystroke: onKeystroke)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .opacity(0.01)
            }
            .frame(maxWidth: .infinity, minHeight: 52)

            Text("Click the field and type at your normal pace.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .onAppear(perform: startCursorBlink)
        .accessibilityLabel("Sentence typing field")
    }

    private func startCursorBlink() {
        withAnimation(.easeInOut(duration: 0.53).repeatForever(autoreverses: true)) {
            isCursorVisible = false
        }
    }
}
