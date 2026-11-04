// EnterKeyMonitor.swift
// Listens for Return via a local event monitor without stealing TextField focus.

import AppKit
import SwiftUI

struct EnterKeyMonitor: View {
    let onEnter: () -> Void
    var consumesEnter: Bool = true

    var body: some View {
        EnterKeyLocalMonitor(onEnter: onEnter, consumesEnter: consumesEnter)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}

struct EnterKeyLocalMonitor: NSViewRepresentable {
    let onEnter: () -> Void
    var consumesEnter: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.startMonitoring()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onEnter = onEnter
        context.coordinator.consumesEnter = consumesEnter
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    final class Coordinator {
        var onEnter: (() -> Void)?
        var consumesEnter: Bool = true
        private var monitor: Any?

        func startMonitoring() {
            stopMonitoring()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                guard event.keyCode == 36 || event.keyCode == 76 || event.characters == "\r" else { return event }
                self.onEnter?()
                return self.consumesEnter ? nil : event
            }
        }

        func stopMonitoring() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
