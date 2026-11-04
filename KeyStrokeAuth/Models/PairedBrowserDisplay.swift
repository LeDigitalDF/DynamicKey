// PairedBrowserDisplay.swift
// Maps paired extension clients to colored browser labels for Settings.

import AppKit
import SwiftUI

enum PairedBrowserDisplay {
    struct BrowserLabel: Hashable {
        let name: String
        let color: Color
    }

    /// Unique connected browsers for display — e.g. Brave | Safari (never duplicates).
    static func uniqueLabels(from clients: [PairedExtensionClient]) -> [BrowserLabel] {
        var seen = Set<String>()
        var labels: [BrowserLabel] = []

        for client in clients {
            let label = browserLabel(for: client)
            guard seen.insert(label.name).inserted else { continue }
            labels.append(label)
        }

        return labels
    }

    /// Normalized browser family slug used for storage and deduplication.
    static func resolvedFamily(browserFamily: String?, clientName: String?) -> String? {
        let nameFamily = inferredFamily(fromClientName: clientName)
        let trimmedFamily = browserFamily?
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let storedFamily = (trimmedFamily?.isEmpty == false) ? trimmedFamily : nil

        // Brave/Edge often mis-detect as Safari or Chrome when the extension UA omits Chromium tokens.
        if let nameFamily, let storedFamily, nameFamily != storedFamily {
            switch (storedFamily, nameFamily) {
            case ("safari", "brave"), ("safari", "edge"), ("safari", "chrome"), ("safari", "firefox"):
                return nameFamily
            case ("chrome", "brave"), ("chrome", "edge"), ("chrome", "safari"), ("chrome", "firefox"):
                return nameFamily
            default:
                break
            }
        }

        if let storedFamily {
            return storedFamily
        }
        return nameFamily
    }

    /// Display name stored on the paired client record.
    static func resolvedClientName(clientName: String?, browserFamily: String?) -> String {
        if let clientName,
           !clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !isGenericExtensionName(clientName) {
            return clientName
        }

        if let family = browserFamily {
            return displayName(forFamily: family) + " Extension"
        }

        return "Browser Extension"
    }

    static func browserLabel(for client: PairedExtensionClient) -> BrowserLabel {
        if let family = resolvedFamily(browserFamily: client.browserFamily, clientName: client.clientName) {
            return browserLabel(forFamily: family)
        }
        return browserLabel(forClientName: client.clientName)
    }

    static func browserLabel(forFamily family: String) -> BrowserLabel {
        BrowserLabel(name: displayName(forFamily: family), color: color(forFamily: family))
    }

    static func displayName(forFamily family: String) -> String {
        switch family.lowercased() {
        case "firefox": return "Firefox"
        case "safari": return "Safari"
        case "brave": return "Brave"
        case "edge": return "Edge"
        case "chrome": return "Chrome"
        default: return family.capitalized
        }
    }

    static func color(forFamily family: String) -> Color {
        switch family.lowercased() {
        case "firefox":
            return Color(red: 1.0, green: 0.45, blue: 0.0)
        case "safari":
            return Color(red: 0.0, green: 0.48, blue: 1.0)
        case "brave":
            return Color(red: 0.98, green: 0.33, blue: 0.0)
        case "edge":
            return Color(red: 0.0, green: 0.47, blue: 0.84)
        case "chrome":
            return Color(red: 0.26, green: 0.52, blue: 0.96)
        default:
            return .purple
        }
    }

    /// Watermark icon for a paired browser family on Home Quick Actions.
    struct BrowserIconDescriptor: Hashable, Identifiable {
        var id: String { family }
        let family: String
        let displayName: String
        let systemImage: String
        let tint: Color
    }

    /// Unique connected browsers with icon metadata — one entry per browser family.
    static func connectedBrowserIcons(from clients: [PairedExtensionClient]) -> [BrowserIconDescriptor] {
        var seen = Set<String>()
        var icons: [BrowserIconDescriptor] = []

        for client in normalizedClients(clients) {
            guard let family = resolvedFamily(
                browserFamily: client.browserFamily,
                clientName: client.clientName
            ) else { continue }
            guard seen.insert(family).inserted else { continue }
            icons.append(iconDescriptor(forFamily: family))
        }

        return icons
    }

    static func iconDescriptor(forFamily family: String) -> BrowserIconDescriptor {
        BrowserIconDescriptor(
            family: family,
            displayName: displayName(forFamily: family),
            systemImage: watermarkSystemImage(forFamily: family),
            tint: color(forFamily: family)
        )
    }

    /// Bundle identifier used to launch the paired browser from the MenuBar.
    static func bundleIdentifier(forFamily family: String) -> String? {
        switch family.lowercased() {
        case "safari":
            return "com.apple.Safari"
        case "brave":
            return "com.brave.Browser"
        case "chrome":
            return "com.google.Chrome"
        case "edge":
            return "com.microsoft.Edge"
        case "firefox":
            return "org.mozilla.firefox"
        default:
            return nil
        }
    }

    /// Opens the installed browser app for a paired family, if available.
    @discardableResult
    static func openBrowser(forFamily family: String) -> Bool {
        guard let bundleID = bundleIdentifier(forFamily: family),
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        return true
    }

    /// SF Symbol per browser — Safari uses the compass glyph; others use letter badges (no official Brave/Chrome logos in SF Symbols).
    static func watermarkSystemImage(forFamily family: String) -> String {
        switch family.lowercased() {
        case "safari":
            return "safari.fill"
        case "firefox":
            return "f.circle.fill"
        case "brave":
            return "b.circle.fill"
        case "edge":
            return "e.circle.fill"
        case "chrome":
            return "c.circle.fill"
        default:
            return "puzzlepiece.extension.fill"
        }
    }

    /// Icon point size for the Home watermark row based on how many browsers are connected.
    static func homeWatermarkIconSize(browserCount: Int) -> CGFloat {
        switch browserCount {
        case 1:
            return 76
        case 2:
            return 48
        case 3:
            return 38
        case 4:
            return 32
        default:
            return 28
        }
    }

    /// Keeps the newest pairing per browser family and upgrades legacy records missing `browserFamily`.
    static func normalizedClients(_ clients: [PairedExtensionClient]) -> [PairedExtensionClient] {
        let upgraded = clients.map { upgradedClient($0) }
        var newestByFamily: [String: PairedExtensionClient] = [:]
        var unclassified: [PairedExtensionClient] = []

        for client in upgraded.sorted(by: { $0.pairedAt > $1.pairedAt }) {
            guard let family = resolvedFamily(
                browserFamily: client.browserFamily,
                clientName: client.clientName
            ) else {
                if unclassified.isEmpty {
                    unclassified.append(client)
                }
                continue
            }

            if newestByFamily[family] == nil {
                newestByFamily[family] = client
            }
        }

        return newestByFamily.values.sorted { $0.pairedAt > $1.pairedAt }
            + unclassified.sorted { $0.pairedAt > $1.pairedAt }
    }

    private static func upgradedClient(_ client: PairedExtensionClient) -> PairedExtensionClient {
        let family = resolvedFamily(browserFamily: client.browserFamily, clientName: client.clientName)
        let name = resolvedClientName(clientName: client.clientName, browserFamily: family)

        return PairedExtensionClient(
            id: client.id,
            accessToken: client.accessToken,
            clientName: name,
            browserFamily: family,
            pairedAt: client.pairedAt
        )
    }

    private static func browserLabel(forClientName clientName: String?) -> BrowserLabel {
        if let family = inferredFamily(fromClientName: clientName) {
            return browserLabel(forFamily: family)
        }

        return BrowserLabel(name: "Browser", color: .secondary)
    }

    private static func inferredFamily(fromClientName clientName: String?) -> String? {
        let lowered = (clientName ?? "").lowercased()

        if lowered.contains("firefox") { return "firefox" }
        if lowered.contains("safari") { return "safari" }
        if lowered.contains("brave") { return "brave" }
        if lowered.contains("edge") { return "edge" }
        if lowered.contains("chrome") || lowered.contains("chromium") { return "chrome" }
        if isGenericExtensionName(clientName) { return nil }

        return nil
    }

    private static func isGenericExtensionName(_ clientName: String?) -> Bool {
        let lowered = (clientName ?? "").lowercased()
        return lowered.contains("keystrokeauth") || lowered == "browser extension"
    }
}
