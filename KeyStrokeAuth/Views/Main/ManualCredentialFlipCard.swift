// ManualCredentialFlipCard.swift
// Flip card for adding a site credential — generate a strong password or enter a custom one for testing.
// Flow: + watermark front (Trusted Keyboards pattern) → origin + username → generate/save sparkle buttons.

import SwiftUI

private enum ManualCredentialPasswordMode: String, CaseIterable, Identifiable {
    case generate
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .generate: return "Generate"
        case .custom: return "Custom"
        }
    }

    var accentColor: Color {
        switch self {
        case .generate:
            return Color(red: 0.22, green: 0.48, blue: 0.95)
        case .custom:
            return Color(red: 0.95, green: 0.52, blue: 0.12)
        }
    }
}

struct ManualCredentialFlipCard: View {
    @Environment(\.glassPalette) private var palette
    @Binding var origin: String
    @Binding var username: String
    let onSave: (String, String, String) -> Void
    let onFlipChanged: (Bool) -> Void

    @FocusState private var isOriginFieldFocused: Bool
    @FocusState private var isUsernameFieldFocused: Bool
    @FocusState private var isCustomPasswordFieldFocused: Bool
    @State private var isFlipped = false
    @State private var passwordMode: ManualCredentialPasswordMode = .generate
    @State private var generatedPassword = ""
    @State private var customPassword = ""
    @State private var hasGeneratedPassword = false
    @State private var isPlusWatermarkHovered = false

    private let originPlaceholder = "e.g. spotify.com"

    /// Matches saved credential card height in the grid.
    private let cardHeight: CGFloat = 220

    /// Tighter than GlassTheme.padding so fields are not clipped inside the card.
    private let backContentPadding = EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)

    init(
        origin: Binding<String>,
        username: Binding<String>,
        onSave: @escaping (String, String, String) -> Void,
        onFlipChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        _origin = origin
        _username = username
        self.onSave = onSave
        self.onFlipChanged = onFlipChanged
    }

    private var canGeneratePassword: Bool {
        !origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSaveCustomPassword: Bool {
        canGeneratePassword && !customPassword.isEmpty
    }

    private var resolvedPassword: String? {
        switch passwordMode {
        case .generate:
            return hasGeneratedPassword ? generatedPassword : nil
        case .custom:
            return canSaveCustomPassword ? customPassword : nil
        }
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

    // Front — + watermark centered; hover/tap on the icon zone (not a bottom strip).
    private var cardFront: some View {
        ZStack {
            SettingsPlusActionWatermark(isHovered: isPlusWatermarkHovered)

            Text("Add Manual Credential")
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
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
                    .accessibilityLabel("Add manual credential")
                    .accessibilityAddTraits(.isButton)
            }
        }
    }

    // Back — round glass back control, then scrollable form inside fixed card height.
    private var cardBack: some View {
        VStack(alignment: .leading, spacing: 0) {
            GlassCircleIconButton(
                systemImage: "chevron.left",
                accessibilityLabel: "Back",
                size: 30,
                iconColor: Color(red: 0.22, green: 0.48, blue: 0.95),
                action: cancelBack
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Add Manual Credential")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .center)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("LeakPeek scans passwords saved here on your Mac — not what you type in the browser.")
                        .font(.caption)
                        .foregroundStyle(palette.onGlassSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Website")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.onGlassSecondary)

                        ManualCredentialInputField(
                            text: $origin,
                            placeholder: originPlaceholder,
                            isFocused: $isOriginFieldFocused
                        )
                        .disabled(hasGeneratedPassword && passwordMode == .generate)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Username")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.onGlassSecondary)

                        ManualCredentialInputField(
                            text: $username,
                            placeholder: "Email or username",
                            isFocused: $isUsernameFieldFocused
                        )
                        .disabled(hasGeneratedPassword && passwordMode == .generate)
                    }

                    HStack(alignment: .center, spacing: 8) {
                        Text("Password mode")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.onGlassSecondary)

                        Spacer(minLength: 0)

                        ManualCredentialPasswordModeToggle(
                            selection: $passwordMode,
                            isEnabled: !(hasGeneratedPassword && passwordMode == .generate)
                        )
                    }

                    passwordSection

                    HStack {
                        Spacer(minLength: 0)

                        if resolvedPassword != nil {
                            LiquidGlassSparkleButton(
                                title: "Save",
                                sparklePalette: .green,
                                action: saveCredential
                            )
                        } else if passwordMode == .generate, canGeneratePassword {
                            LiquidGlassSparkleButton(
                                title: "Generate Password",
                                sparklePalette: .blue,
                                action: generatePassword
                            )
                        }

                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(backContentPadding)
        .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight, alignment: .topLeading)
        .background { manualCardBackground }
        .clipShape(RoundedRectangle(cornerRadius: GlassTheme.cornerRadius, style: .continuous))
        .onChange(of: passwordMode) { _, _ in
            hasGeneratedPassword = false
            generatedPassword = ""
        }
    }

    @ViewBuilder
    private var passwordSection: some View {
        switch passwordMode {
        case .generate:
            VStack(alignment: .leading, spacing: 4) {
                Text("Password")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.onGlassSecondary)

                if hasGeneratedPassword {
                    Text(String(repeating: "•", count: SitePasswordGenerator.defaultLength))
                        .font(.caption.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Filled after you generate a password")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

        case .custom:
            VStack(alignment: .leading, spacing: 6) {
                Text("Custom password")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.onGlassSecondary)

                SecureField("", text: $customPassword)
                    .manualCredentialInputStyle(isFocused: isCustomPasswordFieldFocused)
                    .focused($isCustomPasswordFieldFocused)
                    .overlay(alignment: .leading) {
                        if customPassword.isEmpty && !isCustomPasswordFieldFocused {
                            Text("Password for LeakPeek testing")
                                .font(.callout)
                                .foregroundStyle(palette.fieldPlaceholder)
                                .padding(.horizontal, 8)
                                .allowsHitTesting(false)
                        }
                    }

                Button("Use known leaked test password") {
                    customPassword = "password"
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
            }
        }
    }

    // Real Liquid Glass with a subtle green wash — only this card, to echo the + add action.
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

    private func generatePassword() {
        generatedPassword = SitePasswordGenerator.generate()
        hasGeneratedPassword = true
    }

    private func saveCredential() {
        guard let password = resolvedPassword else { return }

        let trimmedOrigin = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOrigin.isEmpty, !trimmedUsername.isEmpty else { return }

        onSave(trimmedOrigin, trimmedUsername, password)
        resetBackForm()
        flipToFront()
    }

    private func flipToBack() {
        isFlipped = true
    }

    private func flipToFront() {
        isFlipped = false
        clearFieldFocus()
    }

    private func cancelBack() {
        resetBackForm()
        flipToFront()
    }

    private func resetBackForm() {
        origin = ""
        username = ""
        generatedPassword = ""
        customPassword = ""
        hasGeneratedPassword = false
        passwordMode = .generate
        clearFieldFocus()
    }

    private func clearFieldFocus() {
        isOriginFieldFocused = false
        isUsernameFieldFocused = false
        isCustomPasswordFieldFocused = false
    }
}

// Generate / Custom morph glass tab bar — compact inline control on the credential flip-card back.
private struct ManualCredentialPasswordModeToggle: View {
    @Binding var selection: ManualCredentialPasswordMode
    var isEnabled: Bool = true

    @State private var dragThumbOffset: CGFloat?
    @State private var isDragging = false

    private enum Layout {
        static let trackHeight: CGFloat = 26
        static let segmentWidth: CGFloat = 66
        static let thumbInset: CGFloat = 3
        static let morphVerticalOvershoot: CGFloat = 12
        static let tapMovementThreshold: CGFloat = 4
        static let shellPadding: CGFloat = 4

        static var morphLayout: GlassMorphSegmentLayout {
            GlassMorphSegmentLayout(
                trackHeight: trackHeight,
                segmentWidth: segmentWidth,
                segmentCount: ManualCredentialPasswordMode.allCases.count,
                thumbInset: thumbInset,
                morphVerticalOvershoot: morphVerticalOvershoot
            )
        }

        static var shellCornerRadius: CGFloat { trackHeight / 2 + 2 }
        static var overflowFrameHeight: CGFloat { trackHeight + morphVerticalOvershoot + shellPadding }
    }

    private var layout: GlassMorphSegmentLayout {
        Layout.morphLayout
    }

    private var resolvedThumbOffset: CGFloat {
        if let dragThumbOffset {
            return dragThumbOffset
        }
        return selection == .generate ? 0 : Layout.segmentWidth
    }

    private var thumbMorphProgress: CGFloat {
        layout.thumbMorphProgress(for: resolvedThumbOffset)
    }

    private var isThumbSettled: Bool {
        thumbMorphProgress < 0.04 && !isDragging
    }

    private var highlightedMode: ManualCredentialPasswordMode {
        if isThumbSettled {
            return selection
        }

        let thumbCenterX = resolvedThumbOffset + layout.thumbDisplayWidth(for: resolvedThumbOffset) * 0.5
        let index = min(
            ManualCredentialPasswordMode.allCases.count - 1,
            max(0, Int(thumbCenterX / Layout.segmentWidth))
        )
        return ManualCredentialPasswordMode.allCases[index]
    }

    var body: some View {
        ZStack {
            modeTrackShell

            MorphGlassSegmentThumbLayer(
                layout: layout,
                resolvedThumbOffset: resolvedThumbOffset,
                isDragging: isDragging
            ) {
                MorphGlassLiquidThumb(
                    width: layout.thumbWidth,
                    height: layout.thumbHeight,
                    accentColor: selection.accentColor,
                    isMorphing: false
                )
            }
            .frame(width: layout.trackWidth, height: layout.trackHeight)

            segmentLabelsOverlay
                .zIndex(2)
        }
        .frame(
            width: layout.trackWidth + Layout.shellPadding,
            height: Layout.overflowFrameHeight
        )
        .fixedSize(horizontal: true, vertical: true)
        .contentShape(Capsule(style: .continuous))
        .highPriorityGesture(isEnabled ? selectionGesture : nil)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Password mode")
        .accessibilityValue(selection.label)
    }

    private var modeTrackShell: some View {
        MorphGlassTabBarShell(cornerRadius: Layout.shellCornerRadius) {
            GlassMorphTrackCapsule()
                .opacity(0.55)
                .transaction { transaction in
                    transaction.animation = nil
                }
                .frame(width: layout.trackWidth, height: layout.trackHeight)
        }
    }

    private var segmentLabelsOverlay: some View {
        HStack(spacing: 0) {
            ForEach(ManualCredentialPasswordMode.allCases) { mode in
                let isHighlighted = mode == highlightedMode

                Text(mode.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(
                        isHighlighted
                            ? .white
                            : mode.accentColor.opacity(0.55)
                    )
                    .shadow(
                        color: isHighlighted && !isThumbSettled ? .black.opacity(0.45) : .clear,
                        radius: 1.5,
                        y: 0.5
                    )
                    .frame(width: Layout.segmentWidth, height: layout.trackHeight)
                    .animation(.easeInOut(duration: 0.18), value: highlightedMode)
                    .animation(.easeInOut(duration: 0.18), value: isThumbSettled)
            }
        }
        .allowsHitTesting(false)
    }

    private var selectionGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let movedDistance = hypot(value.translation.width, value.translation.height)
                guard movedDistance > Layout.tapMovementThreshold else { return }

                isDragging = true
                let rawOffset = value.location.x
                    - (layout.thumbDisplayWidth(for: resolvedThumbOffset) * 0.5)
                    - Layout.thumbInset
                dragThumbOffset = min(max(0, rawOffset), Layout.segmentWidth)

                let nextSelection = mode(at: value.location.x)
                if selection != nextSelection {
                    selection = nextSelection
                }
            }
            .onEnded { value in
                isDragging = false
                withAnimation(.bouncy(duration: 0.42, extraBounce: 0.03)) {
                    dragThumbOffset = nil
                    selection = mode(at: value.location.x)
                }
            }
    }

    private func mode(at x: CGFloat) -> ManualCredentialPasswordMode {
        x < Layout.segmentWidth ? .generate : .custom
    }
}

// Compact text field with a thin custom border — avoids the large system focus ring clipping inside the card.
private struct ManualCredentialInputField: View {
    @Environment(\.glassPalette) private var palette

    @Binding var text: String
    let placeholder: String
    @FocusState.Binding var isFocused: Bool

    var body: some View {
        TextField("", text: $text)
            .manualCredentialInputStyle(isFocused: isFocused)
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
    func manualCredentialInputStyle(isFocused: Bool) -> some View {
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
