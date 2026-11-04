// LeakPeekRoundActionButton.swift
// Circular LeakPeek actions — liquid glass + gradient sparkle, icon, and labels beneath or inside.
// Flow: idle → spinning progress ring while loading → brief activated state when finished.

import SwiftUI

enum LeakPeekRoundActionButtonLayout {
  /// Icon + title/subtitle beneath the circle (LeakPeek detail).
  case standard
  /// Icon + title inside the circle only (Home donut center).
  case compact
}

struct LeakPeekRoundActionButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var layout: LeakPeekRoundActionButtonLayout = .standard
    var sparklePalette: LiquidGlassSparklePalette = .indigo
    var tint: Color = MainSidebarSection.leakPeek.accentColor
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var ringRotation: Double = 0
    @State private var isActivated = false
    @State private var isHovered = false
    @State private var activatedResetTask: Task<Void, Never>?

    private var circleSize: CGFloat {
        layout == .compact ? 76 : 72
    }

    private var progressRingSize: CGFloat {
        layout == .compact ? 58 : 54
    }

    var body: some View {
        Button(action: action) {
            if layout == .compact {
                circleContent
            } else {
                VStack(spacing: 8) {
                    circleContent
                    labelBlock
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { isHovered = $0 }
        .onChange(of: isLoading) { wasLoading, loading in
            if loading {
                activatedResetTask?.cancel()
                isActivated = false
                startProgressRingSpin()
            } else if wasLoading {
                stopProgressRingSpin()
                showActivatedState()
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if isLoading { return "\(title) saved passwords in progress" }
        if isActivated { return "\(title) completed" }
        if layout == .compact { return "\(title) saved passwords" }
        return title
    }

    // Round liquid-glass target with sparkle animation; progress ring while loading; success ring when done.
    private var circleContent: some View {
        ZStack {
            circleGlassBackground

            if isLoading {
                progressRing
            } else if isActivated {
                Circle()
                    .strokeBorder(Color.green.opacity(0.85), lineWidth: 3)
                    .frame(width: progressRingSize, height: progressRingSize)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }

            if layout == .compact {
                VStack(spacing: 2) {
                    Image(systemName: displayedSystemImage)
                        .font(.body.weight(.semibold))
                        .symbolEffect(.pulse, isActive: isLoading)
                        .symbolEffect(.bounce, value: isActivated)

                    if !isActivated {
                        Text(compactCircleTitle)
                            .font(.caption2.weight(.bold))
                    }
                }
                .foregroundStyle(GlassTheme.buttonLabelColor)
            } else {
                Image(systemName: displayedSystemImage)
                    .font(.title3.weight(.semibold))
                    .symbolEffect(.pulse, isActive: isLoading)
                    .symbolEffect(.bounce, value: isActivated)
                    .foregroundStyle(GlassTheme.buttonLabelColor)
            }
        }
        .frame(width: circleSize, height: circleSize)
        .scaleEffect(isHovered && isEnabled && !isLoading ? 1.04 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isHovered)
        .animation(.easeInOut(duration: 0.25), value: isActivated)
    }

    private var circleGlassBackground: some View {
        Circle()
            .fill(Color.clear)
            .glassEffect()
            .overlay {
                LiquidGlassButtonSparkleBackground(sparklePalette: sparklePalette)
                    .blendMode(.plusLighter)
            }
            .overlay {
                if isActivated {
                    Circle()
                        .fill(Color.green.opacity(0.20))
                } else if isHovered && isEnabled && !isLoading {
                    Circle()
                        .fill(tint.opacity(0.10))
                }
            }
            .clipShape(Circle())
            .allowsHitTesting(false)
    }

    private var progressRing: some View {
        Circle()
            .trim(from: 0.08, to: 0.92)
            .stroke(
                tint.opacity(0.9),
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
            .frame(width: progressRingSize, height: progressRingSize)
            .rotationEffect(.degrees(ringRotation))
    }

    private var labelBlock: some View {
        VStack(spacing: 4) {
            Text(displayedTitle)
                .font(.caption.weight(.bold))
                .foregroundStyle(isActivated ? Color.green : .primary)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Capsule(style: .continuous)
                .fill(tint.opacity(isHovered && isEnabled && !isLoading ? 0.75 : 0))
                .frame(width: isHovered && isEnabled && !isLoading ? 36 : 0, height: 3)
                .animation(.easeOut(duration: 0.18), value: isHovered)
        }
        .frame(maxWidth: 120)
    }

    private var displayedTitle: String {
        if isLoading { return layout == .compact ? title : "Working…" }
        if isActivated { return "Done" }
        return title
    }

    private var compactCircleTitle: String {
        if isLoading { return "Scanning" }
        return title
    }

    private var displayedSystemImage: String {
        isActivated ? "checkmark" : systemImage
    }

    private func startProgressRingSpin() {
        ringRotation = 0
        withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
            ringRotation = 360
        }
    }

    private func stopProgressRingSpin() {
        withAnimation(.easeOut(duration: 0.15)) {
            ringRotation = 0
        }
    }

    private func showActivatedState() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            isActivated = true
        }

        activatedResetTask?.cancel()
        activatedResetTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) {
                    isActivated = false
                }
            }
        }
    }
}
