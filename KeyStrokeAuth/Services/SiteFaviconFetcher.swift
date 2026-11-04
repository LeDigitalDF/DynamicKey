// SiteFaviconFetcher.swift
// Fetches a website favicon with short timeouts and multiple URL fallbacks.
// Flow: parse host → try direct /favicon.ico → DuckDuckGo → Google s2 → nil on failure.

import AppKit
import Foundation

enum SiteFaviconFetcher {
  private static let timeout: TimeInterval = 4

  static func host(from origin: String) -> String? {
    if let url = URL(string: origin), let host = url.host, !host.isEmpty {
      return host
    }

    let trimmed = origin
      .replacingOccurrences(of: "https://", with: "")
      .replacingOccurrences(of: "http://", with: "")
      .split(separator: "/")
      .first

    return trimmed.map(String.init)
  }

  static func fetch(for origin: String) async -> NSImage? {
    guard let host = host(from: origin) else { return nil }

    let candidates = [
      "https://\(host)/favicon.ico",
      "https://icons.duckduckgo.com/ip3/\(host).ico",
      "https://www.google.com/s2/favicons?domain=\(host)&sz=64",
    ]

    for candidate in candidates {
      if let image = await loadImage(from: candidate) {
        return image
      }
    }

    return nil
  }

  private static func loadImage(from urlString: String) async -> NSImage? {
    guard let url = URL(string: urlString) else { return nil }

    var request = URLRequest(url: url)
    request.timeoutInterval = timeout
    request.cachePolicy = .returnCacheDataElseLoad

    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse,
            (200 ... 299).contains(http.statusCode),
            !data.isEmpty,
            let image = NSImage(data: data),
            image.size.width > 0,
            image.size.height > 0
      else {
        return nil
      }
      return image
    } catch {
      return nil
    }
  }
}
