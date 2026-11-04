// MenuBarPanelWindowConfigurator.swift
// Resizes the MenuBarExtra window so the full panel is visible (no top/bottom clipping).
//
// Flow: SwiftUI reports ideal size → AppKit window content size updates on appear/change.

import AppKit
import SwiftUI

enum MenuBarPanelLayout {
    static let width: CGFloat = 374
    static let outerPadding: CGFloat = 10
    static let innerPadding: CGFloat = 14
    static let sectionSpacing: CGFloat = 12

    // Fixed chrome: header, quick actions, footer, dividers, and inner padding.
    static let fixedCoreHeight: CGFloat = 287
    static let pairingCodeBlockHeight: CGFloat = 126
    static let browserListHeaderHeight: CGFloat = 24
    static let browserRowHeight: CGFloat = 34
    static let browserRowSpacing: CGFloat = 6
    static let emptyBrowsersHeight: CGFloat = 24
    static let windowHeightBuffer: CGFloat = 12

    /// Estimates the SwiftUI content height without forcing extra empty space at the bottom.
    static func contentHeight(browserRowCount: Int, showsPairingCode: Bool) -> CGFloat {
        var height = fixedCoreHeight + browserListHeaderHeight

        if browserRowCount == 0 {
            height += emptyBrowsersHeight
        } else {
            height += CGFloat(browserRowCount) * browserRowHeight
            height += CGFloat(max(browserRowCount - 1, 0)) * browserRowSpacing
        }

        if showsPairingCode {
            height += sectionSpacing + pairingCodeBlockHeight
        }

        return height
    }
}

struct MenuBarPanelWindowConfigurator: NSViewRepresentable {
    let minWidth: CGFloat
    let minHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.scheduleResize(for: view, minWidth: minWidth, minHeight: minHeight)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.scheduleResize(for: nsView, minWidth: minWidth, minHeight: minHeight)
    }

    final class Coordinator {
        private var workItem: DispatchWorkItem?

        func scheduleResize(for view: NSView, minWidth: CGFloat, minHeight: CGFloat) {
            workItem?.cancel()
            let item = DispatchWorkItem { [weak view] in
                guard let view else { return }
                Self.applyWindowSize(for: view, minWidth: minWidth, minHeight: minHeight)
            }
            workItem = item
            DispatchQueue.main.async(execute: item)
        }

        private static func applyWindowSize(for view: NSView, minWidth: CGFloat, minHeight: CGFloat) {
            guard let window = view.window else { return }

            window.contentView?.layoutSubtreeIfNeeded()

            let measuredContentHeight = measureContentHeight(in: window)
            let measuredWindowHeight = measuredContentHeight > 0
                ? measuredContentHeight + (MenuBarPanelLayout.outerPadding * 2) + MenuBarPanelLayout.windowHeightBuffer
                : 0
            let targetHeight = max(minHeight, measuredWindowHeight)
            let nextSize = NSSize(width: ceil(minWidth), height: ceil(targetHeight))

            window.setContentSize(nextSize)
            window.contentMinSize = nextSize
            window.contentMaxSize = nextSize
        }

        /// Walks the MenuBar window hierarchy to read the true SwiftUI hosting height.
        private static func measureContentHeight(in window: NSWindow) -> CGFloat {
            guard let contentView = window.contentView else { return 0 }

            if let glassContainer = findFirstSubview(in: contentView, ofType: GlassHostingContainerView.self) {
                glassContainer.layoutSubtreeIfNeeded()
                let glassHeight = glassContainer.fittingSize.height
                if glassHeight > 20 {
                    return glassHeight
                }
            }

            if let hostingView = findHostingView(in: contentView) {
                hostingView.layoutSubtreeIfNeeded()
                let hostingHeight = hostingView.fittingSize.height
                if hostingHeight > 20 {
                    return hostingHeight
                }
            }

            let fittingHeight = contentView.fittingSize.height
            return fittingHeight > 20 ? fittingHeight : 0
        }

        private static func findHostingView(in view: NSView) -> NSView? {
            let typeName = String(describing: type(of: view))
            if typeName.contains("Hosting") {
                return view
            }

            for subview in view.subviews {
                if let match = findHostingView(in: subview) {
                    return match
                }
            }

            return nil
        }

        private static func findFirstSubview<T: NSView>(in view: NSView, ofType: T.Type) -> T? {
            if let match = view as? T {
                return match
            }

            for subview in view.subviews {
                if let match = findFirstSubview(in: subview, ofType: ofType) {
                    return match
                }
            }

            return nil
        }
    }
}
