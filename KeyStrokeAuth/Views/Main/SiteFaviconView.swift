// SiteFaviconView.swift
// Displays a website favicon with graceful fallback when offline or unavailable.
// Flow: muted globe while loading → fetched image → colored globe if all sources fail.

import AppKit
import SwiftUI

struct SiteFaviconView: View {
  let origin: String
  var size: CGFloat = 44

  @State private var faviconImage: NSImage?
  @State private var didFail = false

  private var host: String? {
    SiteFaviconFetcher.host(from: origin)
  }

  var body: some View {
    Group {
      if let faviconImage {
        Image(nsImage: faviconImage)
          .resizable()
          .interpolation(.high)
          .scaledToFill()
          .frame(width: size, height: size)
          .clipShape(Circle())
      } else {
        fallbackIcon
          .opacity(didFail ? 1 : 0.55)
          .frame(width: size, height: size)
          .background {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
              .fill(Color.primary.opacity(0.06))
          }
          .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
              .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
          }
      }
    }
    .accessibilityLabel(host.map { "Favicon for \($0)" } ?? "Website icon")
    .task(id: origin) {
      await loadFavicon()
    }
  }

  private var fallbackIcon: some View {
    ZStack {
      Image(systemName: "globe.americas.fill")
        .font(.system(size: size * 0.44, weight: .semibold))
        .foregroundStyle(MainSidebarSection.credentials.accentColor)

      if let host, didFail {
        Text(String(host.prefix(1)).uppercased())
          .font(.system(size: size * 0.34, weight: .bold))
          .foregroundStyle(.white)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @MainActor
  private func loadFavicon() async {
    faviconImage = nil
    didFail = false

    let image = await SiteFaviconFetcher.fetch(for: origin)
    if let image {
      faviconImage = image
      didFail = false
    } else {
      faviconImage = nil
      didFail = true
    }
  }
}
