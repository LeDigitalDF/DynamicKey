// PreferencesIconTabBar.swift
// Raycast-style Preferences toolbar tabs — free-floating icon + label, no capsule track.
//
// Flow: horizontal row of tabs → selected item gets a light rounded highlight only.

import SwiftUI

struct PreferencesIconTabBar<Tab: Identifiable & Hashable>: View {
    @Binding var selection: Tab
    let tabs: [Tab]
    let title: (Tab) -> String
    let systemImage: (Tab) -> String

    @Environment(\.glassPalette) private var palette

    var body: some View {
        HStack(spacing: 2) {
            Spacer(minLength: 0)
            ForEach(tabs) { tab in
                tabButton(tab)
            }
            Spacer(minLength: 0)
        }
    }

    private func tabButton(_ tab: Tab) -> some View {
        let isSelected = selection.id == tab.id

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selection = tab
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: systemImage(tab))
                    .font(.system(size: 20, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .frame(height: 22)

                Text(title(tab))
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? palette.onGlassPrimary : palette.onGlassSecondary)
            .frame(width: 72)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.10))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title(tab))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
