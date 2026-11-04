// NSGlassEffectContainerRepresentable.swift
// AppKit bridge that hosts SwiftUI content inside NSGlassEffectContainerView.

import AppKit
import SwiftUI

/// Hosts SwiftUI content on Liquid Glass using NSGlassEffectContainerView.
struct NSGlassEffectContainerRepresentable<Content: View>: NSViewRepresentable {
    var cornerRadius: CGFloat
    let content: Content

    init(cornerRadius: CGFloat = GlassTheme.cornerRadius, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> GlassHostingContainerView {
        let container = GlassHostingContainerView(cornerRadius: cornerRadius)
        container.setContent(content)
        context.coordinator.containerView = container
        return container
    }

    func updateNSView(_ container: GlassHostingContainerView, context: Context) {
        container.cornerRadius = cornerRadius
        container.setContent(content)
    }

    final class Coordinator {
        weak var containerView: GlassHostingContainerView?
    }
}

/// NSView that wraps NSGlassEffectContainerView pattern with a SwiftUI hosting view.
final class GlassHostingContainerView: NSGlassEffectContainerView {
    private var hostingView: NSHostingView<AnyView>?
    var cornerRadius: CGFloat {
        didSet { needsLayout = true }
    }

    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func setContent<Content: View>(_ content: Content) {
        let wrapped = AnyView(content)
        if let hostingView {
            hostingView.rootView = wrapped
            hostingView.invalidateIntrinsicContentSize()
            invalidateIntrinsicContentSize()
            needsLayout = true
            superview?.needsLayout = true
            return
        }

        let hosting = NSHostingView(rootView: wrapped)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        hostingView = hosting
    }

    override var fittingSize: NSSize {
        guard let hostingView else { return super.fittingSize }
        hostingView.layoutSubtreeIfNeeded()
        return hostingView.fittingSize
    }

    override var intrinsicContentSize: NSSize {
        fittingSize
    }
}
