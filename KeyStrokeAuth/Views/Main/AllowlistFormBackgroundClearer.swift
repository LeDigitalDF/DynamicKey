// AllowlistFormBackgroundClearer.swift
// Clears NSTableView / NSScrollView / row backgrounds so glass shows through — including during swipe.

import AppKit
import SwiftUI

struct AllowlistFormBackgroundClearer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let tableView = findTableView(from: nsView) else { return }
            applyClearChrome(to: tableView)
        }
    }

    private func findTableView(from view: NSView) -> NSTableView? {
        var current: NSView? = view.superview
        while let node = current {
            if let table = node as? NSTableView {
                return table
            }
            if let table = findTableView(in: node) {
                return table
            }
            current = node.superview
        }
        return findTableView(in: view)
    }

    private func findTableView(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView {
            return table
        }
        for subview in view.subviews {
            if let table = findTableView(in: subview) {
                return table
            }
        }
        return nil
    }

    private func applyClearChrome(to tableView: NSTableView) {
        tableView.backgroundColor = .clear
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.selectionHighlightStyle = .none
        tableView.wantsLayer = true
        tableView.layer?.backgroundColor = NSColor.clear.cgColor

        if let scrollView = tableView.enclosingScrollView {
            scrollView.backgroundColor = .clear
            scrollView.drawsBackground = false
            scrollView.contentView.drawsBackground = false
            scrollView.wantsLayer = true
            scrollView.layer?.backgroundColor = NSColor.clear.cgColor
            scrollView.contentView.wantsLayer = true
            scrollView.contentView.layer?.backgroundColor = NSColor.clear.cgColor
        }

        clearOpaqueBackgrounds(in: tableView)

        for row in 0..<tableView.numberOfRows {
            if let rowView = tableView.rowView(atRow: row, makeIfNecessary: true) {
                rowView.backgroundColor = .clear
                rowView.wantsLayer = true
                rowView.layer?.backgroundColor = NSColor.clear.cgColor
                clearOpaqueBackgrounds(in: rowView)
            }
        }
    }

    /// Clears AppKit fill layers that otherwise show as a black square during swipe reveal.
    private func clearOpaqueBackgrounds(in root: NSView) {
        root.wantsLayer = true
        if root.layer?.backgroundColor != nil {
            root.layer?.backgroundColor = NSColor.clear.cgColor
        }

        for subview in root.subviews {
            if let rowView = subview as? NSTableRowView {
                rowView.backgroundColor = .clear
            }
            if let clipView = subview as? NSClipView {
                clipView.drawsBackground = false
                clipView.backgroundColor = .clear
            }
            clearOpaqueBackgrounds(in: subview)
        }
    }
}
