// WindowDragLockHosting.swift
// Wraps SwiftUI controls so drags are not stolen by isMovableByWindowBackground on the title bar.
// Flow: NSHostingView subclass → mouseDownCanMoveWindow false → child gestures receive drag events.

import AppKit
import SwiftUI

struct WindowDragLock<Content: View>: NSViewRepresentable {
    @ViewBuilder var content: () -> Content

    func makeNSView(context: Context) -> DragLockHostingView<Content> {
        DragLockHostingView(rootView: content())
    }

    func updateNSView(_ nsView: DragLockHostingView<Content>, context: Context) {
        nsView.rootView = content()
    }
}

final class DragLockHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { false }
}
