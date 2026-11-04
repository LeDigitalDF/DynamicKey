// LiquidGlassSurface.swift
// True Liquid Glass surface backed by AppKit's NSGlassEffectView (macOS 26+).
// Flow: SwiftUI card places this as its `.background` → NSGlassEffectView samples the animated
//       dashboard behind it and renders the real transparent, blurred Liquid Glass material.
//
// Note: a single card uses one NSGlassEffectView. When we roll Liquid Glass out to ALL dashboard
// cards, the group should be wrapped in an NSGlassEffectContainerView (see
// NSGlassEffectContainerRepresentable) so nearby glass elements render as a unified surface.

import AppKit
import SwiftUI

struct LiquidGlassSurface: NSViewRepresentable {
    // Corner radius for the glass shape (project standard is 20).
    var cornerRadius: CGFloat = 20
    // Optional tint applied to the glass (nil = neutral clear glass).
    var tintColor: NSColor? = nil

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.cornerRadius = cornerRadius
        view.tintColor = tintColor
        return view
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        // Keep AppKit state in sync with SwiftUI values (idempotent-friendly assignments).
        if view.cornerRadius != cornerRadius { view.cornerRadius = cornerRadius }
        if view.tintColor != tintColor { view.tintColor = tintColor }
    }
}
