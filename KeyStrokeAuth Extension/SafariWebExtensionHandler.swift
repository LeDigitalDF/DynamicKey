// SafariWebExtensionHandler.swift
// Native entry point for the embedded Safari Web Extension (W4.5).
//
// Flow: Safari loads the web extension bundle from the Mac app → JS talks to localhost Mac API.

import SafariServices
import os.log

/// Handles optional native messages from the Safari web extension bundle.
class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    /// Completes native bridge requests; web extension uses localhost HTTP to the Mac app instead.
    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem

        let profile: UUID? = request?.userInfo?[SFExtensionProfileKey] as? UUID
        let message: Any? = request?.userInfo?["message"]

        os_log(.default, "KeyStrokeAuth Safari extension native bridge: profile=%@ message=%@", String(describing: profile), String(describing: message))

        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: ["acknowledged": true]]

        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
