// SettingsProfileHeaderView.swift
// Profile cover + round avatar at the top of Settings (uploadable cover and photo only).
// Flow: background image → centered avatar overlapping the cover bottom edge.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsProfileHeaderView: View {
    @EnvironmentObject private var preferences: AppPreferencesStore

    @State private var showsAvatarImporter = false
    @State private var showsBackgroundImporter = false

    private let coverHeight: CGFloat = 120
    private let avatarSize: CGFloat = 76

    var body: some View {
        GlassPanel {
            ZStack(alignment: .bottom) {
                coverBackground
                    .frame(height: coverHeight)
                    .frame(maxWidth: .infinity)
                    .clipped()

                avatarButton
                    .offset(y: avatarSize / 2)
            }
            .padding(.bottom, avatarSize / 2)
            .frame(maxWidth: .infinity)
        }
        .fileImporter(
            isPresented: $showsAvatarImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            importImage(from: result, isBackground: false)
        }
        .fileImporter(
            isPresented: $showsBackgroundImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            importImage(from: result, isBackground: true)
        }
    }

    private var coverBackground: some View {
        ZStack(alignment: .topTrailing) {
            if let image = bookmarkImage(preferences.profileBackgroundBookmark) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.45), Color.purple.opacity(0.35)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            Button("Change Background") {
                showsBackgroundImporter = true
            }
            .buttonStyle(.borderless)
            .font(.caption.weight(.medium))
            .padding(10)
            .foregroundStyle(GlassTheme.buttonLabelColor)
            .shadow(radius: 2)
        }
    }

    private var avatarButton: some View {
        Button {
            showsAvatarImporter = true
        } label: {
            ZStack {
                Circle()
                    .fill(Color(nsColor: .windowBackgroundColor))

                if let image = bookmarkImage(preferences.profileImageBookmark) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: avatarSize * 0.62))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: avatarSize, height: avatarSize)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .help("Choose profile picture")
    }

    private func bookmarkImage(_ bookmark: Data?) -> NSImage? {
        guard let bookmark else { return nil }
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

    private func importImage(from result: Result<[URL], Error>, isBackground: Bool) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }

        if isBackground {
            preferences.profileBackgroundBookmark = bookmark
        } else {
            preferences.profileImageBookmark = bookmark
        }
    }
}
