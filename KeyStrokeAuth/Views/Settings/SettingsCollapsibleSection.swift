// SettingsCollapsibleSection.swift
// Expandable settings group with chevron — uses SwiftUI glass (not AppKit panel) so height updates reliably.
// Flow: tap header → chevron rotates → body grows in place; header always stays visible above content.

import SwiftUI

struct SettingsCollapsibleSection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader

            if isExpanded {
                content()
                    .padding(.top, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(GlassTheme.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GlassRoundedGlassSurface(cornerRadius: GlassTheme.cornerRadius, tint: .none)
        }
    }

    // Header is always rendered first in the stack — never inside a dynamic AppKit glass host.
    private var sectionHeader: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 10) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.2), value: isExpanded)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}
