// KeystrokeMonitorView.swift
// AppKit view that captures key-down/key-up timing and bridges into SwiftUI.

import AppKit
import SwiftUI

final class KeystrokeMonitorView: NSView {
    var onKeystroke: ((KeystrokeData) -> Void)?

    private var keyDownTimes: [UInt16: TimeInterval] = [:]
    private var keyFlightTimes: [UInt16: TimeInterval] = [:]
    private var lastKeyUpTime: TimeInterval = 0

    override var acceptsFirstResponder: Bool { true }

    func reclaimFirstResponder() {
        window?.makeFirstResponder(self)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async {
            self.window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        let currentTime = Date().timeIntervalSince1970
        let keyCode = event.keyCode
        let flightTime = lastKeyUpTime > 0 ? currentTime - lastKeyUpTime : 0
        keyDownTimes[keyCode] = currentTime
        keyFlightTimes[keyCode] = flightTime
    }

    override func keyUp(with event: NSEvent) {
        let currentTime = Date().timeIntervalSince1970
        let keyCode = event.keyCode
        if let downTime = keyDownTimes[keyCode], let flightTime = keyFlightTimes[keyCode] {
            let dwellTime = currentTime - downTime
            let character = event.charactersIgnoringModifiers ?? "?"
            onKeystroke?(KeystrokeData(character: character, dwellTime: dwellTime, flightTime: flightTime))
            keyDownTimes.removeValue(forKey: keyCode)
            keyFlightTimes.removeValue(forKey: keyCode)
        }
        lastKeyUpTime = currentTime
    }
}

struct KeystrokeMonitorViewRepresentable: NSViewRepresentable {
    var onKeystroke: (KeystrokeData) -> Void

    func makeNSView(context: Context) -> KeystrokeMonitorView {
        let view = KeystrokeMonitorView()
        view.onKeystroke = onKeystroke
        return view
    }

    func updateNSView(_ nsView: KeystrokeMonitorView, context: Context) {
        nsView.onKeystroke = onKeystroke
    }
}
