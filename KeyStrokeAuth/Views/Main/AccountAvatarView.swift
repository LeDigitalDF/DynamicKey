// AccountAvatarView.swift
// Round account avatar that reuses the profile picture the user uploads in Settings.
// Flow: read AppPreferencesStore.profileImageBookmark → resolve the security-scoped file → show it,
//       falling back to a neutral person glyph when no picture has been chosen yet.
// Storage note: the picture is stored locally (a security-scoped bookmark to the user's file), not in Supabase.

import AppKit
import SwiftUI

struct AccountAvatarView: View {
    @EnvironmentObject private var preferences: AppPreferencesStore

    var size: CGFloat = 30

    var body: some View {
        ZStack {
            // Neutral backing so transparent images still read as a circular avatar.
            Circle()
                .fill(Color(nsColor: .windowBackgroundColor))

            if let image = resolvedImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: size * 0.9))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    // Resolves the stored security-scoped bookmark to an image, if one was uploaded.
    private var resolvedImage: NSImage? {
        guard let bookmark = preferences.profileImageBookmark else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        guard url.startAccessingSecurityScopedResource() else { return nil }
        defer { url.stopAccessingSecurityScopedResource() }
        return NSImage(contentsOf: url)
    }
}
