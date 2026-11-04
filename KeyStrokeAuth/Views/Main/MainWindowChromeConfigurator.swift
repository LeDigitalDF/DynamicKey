// MainWindowChromeConfigurator.swift
// Seamless title bar for every screen: hidden title, no separator, full-size content — the app
// background paints under the title bar (including behind the traffic lights). The window color is
// clear, but SwiftUI backgrounds are opaque, so the rendered result is never transparent (App
// Store safe) while keeping the seamless, band-free top on landing, login, enrollment, and main hub.
// Flow: lives on ContentView → applies unified chrome once the window is ready (including cold launch).

import AppKit
import SwiftUI

struct MainWindowChromeConfigurator: NSViewRepresentable {
    /// Theme flag kept for callers; chrome itself is the same in Light and Dark.
    var isLightMode: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.scheduleApply(to: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.cancel()
    }

    // MARK: - Coordinator

    final class Coordinator {
        private var workItem: DispatchWorkItem?
        private var visibilityObserver: NSObjectProtocol?

        func scheduleApply(to nsView: NSView) {
            workItem?.cancel()

            let item = DispatchWorkItem { [weak self, weak nsView] in
                guard let self, let nsView, let window = nsView.window else { return }
                // Apply once before display, then again after AppKit finishes the title bar.
                // Skipping the early pass in Dark Mode left the cold-launch black separator.
                self.applySeamlessChrome(to: window)
                self.applyChromeAfterWindowBecomesVisible(window)
            }
            workItem = item
            DispatchQueue.main.async(execute: item)
        }

        func cancel() {
            workItem?.cancel()
            workItem = nil
            removeVisibilityObserver()
        }

        // Reapplies chrome after the window is on screen so cold launch never keeps the separator.
        private func applyChromeAfterWindowBecomesVisible(_ window: NSWindow) {
            removeVisibilityObserver()

            let reapply = { [weak self, weak window] in
                guard let self, let window else { return }
                self.applySeamlessChrome(to: window)
            }

            // Next run loop — after AppKit lays out the title bar.
            DispatchQueue.main.async(execute: reapply)
            // Short follow-up catches late separator painting on first launch (Light and Dark).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: reapply)

            guard !window.isVisible else { return }

            visibilityObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                reapply()
                self.removeVisibilityObserver()
            }
        }

        // Removes the one-shot cold-launch visibility observer.
        private func removeVisibilityObserver() {
            guard let visibilityObserver else { return }
            NotificationCenter.default.removeObserver(visibilityObserver)
            self.visibilityObserver = nil
        }

        // Apply seamless chrome on every screen. Every mutation is idempotent so AppKit never
        // rebuilds the window frame unless a value actually changed.
        private func applySeamlessChrome(to window: NSWindow) {
            if !window.title.isEmpty { window.title = "" }
            if window.titleVisibility != .hidden { window.titleVisibility = .hidden }
            if !window.titlebarAppearsTransparent { window.titlebarAppearsTransparent = true }
            if window.titlebarSeparatorStyle != .none { window.titlebarSeparatorStyle = .none }
            if !window.styleMask.contains(.fullSizeContentView) {
                window.styleMask.insert(.fullSizeContentView)
            }
            if !window.isMovableByWindowBackground { window.isMovableByWindowBackground = true }
            // Clear window color keeps the title bar seamless (content paints under the traffic
            // lights, no top band). The SwiftUI dashboard background is opaque, so the rendered
            // window is never see-through — App Store safe without a visible safe-area strip.
            if window.backgroundColor != .clear { window.backgroundColor = .clear }
        }
    }
}

enum MainChromeLayout {
    /// Top inset that clears the traffic-light / title-bar zone on seamless windows.
    static let rowHeight: CGFloat = 36
    /// Room for the morph glass theme toggle (matches Security Activity tab bar overflow).
    static let themeControlHeight: CGFloat = 54
}

struct MainTopChromeRow: View {
    let sidebarWidth: CGFloat
    let showsDetailBack: Bool
    let onToggleSidebar: () -> Void
    let onDetailBack: () -> Void
    let isSidebarCollapsed: Bool

    var body: some View {
        HStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                GlassCircleIconButton(
                    systemImage: "sidebar.leading",
                    accessibilityLabel: isSidebarCollapsed ? "Expand sidebar" : "Collapse sidebar",
                    action: onToggleSidebar
                )
                .help(isSidebarCollapsed ? "Expand sidebar" : "Collapse sidebar")
            }
            .frame(width: sidebarWidth)
            .padding(.horizontal, 12)

            HStack(spacing: 8) {
                if showsDetailBack {
                    GlassBackButton(title: "Back to Home", action: onDetailBack)
                }

                Spacer(minLength: 0)

                AppearanceToolbarThemeControl()
            }
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity)
        }
        .frame(height: MainChromeLayout.themeControlHeight)
    }
}
