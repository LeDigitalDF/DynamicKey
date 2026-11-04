// PreferencesHotkeyRecorderButton.swift
// Records a DynamicKey hotkey chord when pressed — Raycast-style dark rounded control.
//
// Flow: tap → listening → next keyDown with modifiers → save preference → idle.

import AppKit
import SwiftUI

struct PreferencesHotkeyRecorderButton: View {
    @Binding var hotkey: AppHotkeyPreference

    @State private var isListening = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            beginListening()
        } label: {
            Text(isListening ? "Type a shortcut…" : hotkey.displayString)
                .font(.system(size: 13, weight: .medium).monospaced())
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(isListening ? 0.14 : 0.08))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                        }
                }
        }
        .buttonStyle(.plain)
        .frame(width: 200)
        .accessibilityLabel("DynamicKey Hotkey")
        .accessibilityValue(hotkey.displayString)
        .onDisappear {
            stopListening()
        }
    }

    private func beginListening() {
        stopListening()
        isListening = true

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !flags.isEmpty || event.keyCode == 53 else {
                return event
            }

            if event.keyCode == 53 {
                DispatchQueue.main.async {
                    stopListening()
                }
                return nil
            }

            let recorded = AppHotkeyPreference(
                keyCode: event.keyCode,
                modifierFlags: flags.rawValue
            )
            DispatchQueue.main.async {
                hotkey = recorded
                stopListening()
            }
            return nil
        }
    }

    private func stopListening() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isListening = false
    }
}
