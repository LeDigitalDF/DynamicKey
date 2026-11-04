// MenuBarPairedBrowserRow.swift
// Interactive paired-browser row — hover float, click to open, swipe to reveal Unpair (no List chrome).
//
// Flow: swipe reveals a same-size Unpair capsule → release snaps closed unless Unpair is fully shown
// (then it stays open so you can click Unpair). Never auto-unpairs from swipe alone.

import AppKit
import SwiftUI

struct MenuBarPairedBrowserRow: View {
    let browserName: String
    let deviceName: String
    let systemImage: String
    let tint: Color
    let isConnected: Bool
    let onOpen: () -> Void
    let onUnpair: () -> Void

    @Environment(\.glassPalette) private var palette
    @State private var isHovered = false
    @State private var dragOffset: CGFloat = 0

    private let revealWidth: CGFloat = 72
    private let cornerRadius: CGFloat = 12

    var body: some View {
        ZStack {
            // Invisible row sets the exact height; Unpair capsules match that size 1:1.
            glassRow
                .hidden()
                .overlay {
                    HStack(spacing: 0) {
                        unpairSideCapsule
                            .frame(width: revealWidth)
                            .opacity(dragOffset > 6 ? 1 : 0)

                        Spacer(minLength: 0)

                        unpairSideCapsule
                            .frame(width: revealWidth)
                            .opacity(dragOffset < -6 ? 1 : 0)
                    }
                }

            glassRow
                .offset(x: dragOffset)
        }
        .overlay {
            MenuBarHorizontalSwipeCatcher(
                offset: $dragOffset,
                revealWidth: revealWidth,
                onTapRow: handleRowTap,
                onTapUnpair: commitUnpair,
                onSnapClosed: snapClosed,
                onParkOpen: parkOpen
            )
        }
        .scaleEffect(isHovered && abs(dragOffset) < 1 ? 1.045 : 1)
        .shadow(
            color: .black.opacity(isHovered && abs(dragOffset) < 1 ? 0.22 : 0),
            radius: isHovered && abs(dragOffset) < 1 ? 8 : 0,
            y: isHovered && abs(dragOffset) < 1 ? 3 : 0
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.68), value: isHovered)
        .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.86), value: dragOffset)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(browserName) on \(deviceName)")
        .accessibilityHint("Click to open. Swipe to reveal Unpair, then click Unpair.")
        .accessibilityAction(named: "Unpair", onUnpair)
    }

    /// Red Unpair capsule — forced to the glass bar’s height via the hidden sizing row overlay.
    private var unpairSideCapsule: some View {
        Label("Unpair", systemImage: "link.badge.minus")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .labelStyle(.titleAndIcon)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.red.opacity(0.88))
            }
            .allowsHitTesting(false)
    }

    private var glassRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isConnected ? Color.green : Color.orange.opacity(0.8))
                .frame(width: 7, height: 7)

            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 18)

            Text("\(browserName) — \(deviceName)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.onGlassPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.clear)
                .glassEffect()
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(palette.onGlassSecondary.opacity(0.08))
                }
        }
    }

    private func handleRowTap() {
        if abs(dragOffset) > 4 {
            snapClosed()
            return
        }
        onOpen()
    }

    private func snapClosed() {
        withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
            dragOffset = 0
        }
    }

    /// Keeps Unpair fully visible after release so the user can click it.
    private func parkOpen(at offset: CGFloat) {
        withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
            dragOffset = offset
        }
    }

    private func commitUnpair() {
        snapClosed()
        onUnpair()
    }
}

// MARK: - AppKit swipe catcher

/// Captures click-drag and horizontal trackpad scroll for MenuBar rows.
private struct MenuBarHorizontalSwipeCatcher: NSViewRepresentable {
    @Binding var offset: CGFloat
    var revealWidth: CGFloat
    var onTapRow: () -> Void
    var onTapUnpair: () -> Void
    var onSnapClosed: () -> Void
    var onParkOpen: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MenuBarSwipeCatcherView {
        let view = MenuBarSwipeCatcherView(frame: .zero)
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: MenuBarSwipeCatcherView, context: Context) {
        context.coordinator.revealWidth = revealWidth
        context.coordinator.onTapRow = onTapRow
        context.coordinator.onTapUnpair = onTapUnpair
        context.coordinator.onSnapClosed = onSnapClosed
        context.coordinator.onParkOpen = onParkOpen
        context.coordinator.offsetBinding = $offset
        nsView.coordinator = context.coordinator
    }

    final class Coordinator {
        var revealWidth: CGFloat = 72
        var onTapRow: () -> Void = {}
        var onTapUnpair: () -> Void = {}
        var onSnapClosed: () -> Void = {}
        var onParkOpen: (CGFloat) -> Void = { _ in }
        var offsetBinding: Binding<CGFloat>?

        var offset: CGFloat {
            get { offsetBinding?.wrappedValue ?? 0 }
            set { offsetBinding?.wrappedValue = newValue }
        }
    }
}

private final class MenuBarSwipeCatcherView: NSView {
    var coordinator: MenuBarHorizontalSwipeCatcher.Coordinator?

    private var isTracking = false
    private var totalDrag: CGFloat = 0
    private var liveOffset: CGFloat = 0
    private var releaseWorkItem: DispatchWorkItem?

    override var acceptsFirstResponder: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { self }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func mouseDown(with event: NSEvent) {
        cancelScheduledRelease()
        window?.makeFirstResponder(self)
        isTracking = true
        totalDrag = 0
        liveOffset = coordinator?.offset ?? 0
    }

    override func mouseDragged(with event: NSEvent) {
        guard isTracking else { return }
        liveOffset = clamped(liveOffset + event.deltaX)
        coordinator?.offset = liveOffset
        totalDrag = liveOffset
    }

    override func mouseUp(with event: NSEvent) {
        guard isTracking else { return }
        isTracking = false

        let point = convert(event.locationInWindow, from: nil)
        if isPointInUnpairArea(point), isUnpairFullyShown {
            coordinator?.onTapUnpair()
            liveOffset = 0
            totalDrag = 0
            return
        }

        if abs(totalDrag) < 4, abs(liveOffset) < 4 {
            coordinator?.onTapRow()
            liveOffset = 0
            totalDrag = 0
            return
        }

        finishRelease()
    }

    override func scrollWheel(with event: NSEvent) {
        let horizontal = event.scrollingDeltaX
        let vertical = event.scrollingDeltaY
        guard abs(horizontal) > abs(vertical), abs(horizontal) > 0.15 else {
            super.scrollWheel(with: event)
            return
        }

        cancelScheduledRelease()

        if event.phase == .began || event.phase == .mayBegin {
            // Continue from parked open if already revealing Unpair.
            liveOffset = coordinator?.offset ?? 0
            totalDrag = liveOffset
            isTracking = true
        }

        if !isTracking {
            liveOffset = coordinator?.offset ?? 0
            totalDrag = liveOffset
            isTracking = true
        }

        if event.phase == .began || event.phase == .changed || event.phase == .mayBegin || event.phase.isEmpty {
            liveOffset = clamped(liveOffset + horizontal)
            totalDrag = liveOffset
            coordinator?.offset = liveOffset
        }

        if event.phase == .ended || event.phase == .cancelled {
            isTracking = false
            finishRelease()
            return
        }

        scheduleRelease()

        if event.momentumPhase == .ended {
            isTracking = false
            cancelScheduledRelease()
            finishRelease()
        }
    }

    private var isUnpairFullyShown: Bool {
        let reveal = coordinator?.revealWidth ?? 72
        return abs(liveOffset) >= reveal - 1
    }

    /// Hard stop at the Unpair reveal width so the glass bar never slides fully off-screen.
    private func clamped(_ value: CGFloat) -> CGFloat {
        let reveal = coordinator?.revealWidth ?? 72
        return max(-reveal, min(reveal, value))
    }

    private func isPointInUnpairArea(_ point: NSPoint) -> Bool {
        let reveal = coordinator?.revealWidth ?? 72
        if liveOffset < -8 {
            return point.x >= bounds.width - reveal
        }
        if liveOffset > 8 {
            return point.x <= reveal
        }
        return false
    }

    /// Snap closed only when Unpair is not fully shown; otherwise park open for a click.
    private func finishRelease() {
        cancelScheduledRelease()
        let reveal = coordinator?.revealWidth ?? 72

        if isUnpairFullyShown {
            let parked = liveOffset < 0 ? -reveal : reveal
            liveOffset = parked
            totalDrag = parked
            DispatchQueue.main.async {
                self.coordinator?.onParkOpen(parked)
            }
            return
        }

        liveOffset = 0
        totalDrag = 0
        DispatchQueue.main.async {
            self.coordinator?.onSnapClosed()
        }
    }

    private func scheduleRelease() {
        cancelScheduledRelease()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isTracking = false
            self.finishRelease()
        }
        releaseWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
    }

    private func cancelScheduledRelease() {
        releaseWorkItem?.cancel()
        releaseWorkItem = nil
    }
}
