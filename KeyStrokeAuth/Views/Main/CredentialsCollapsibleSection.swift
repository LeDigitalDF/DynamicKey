// CredentialsCollapsibleSection.swift
// Expandable glass section for website credentials — custom centered header + chevron.
// Flow: tap header (favicon/title) → chevron rotates → detail body appears below.

import SwiftUI

struct CredentialsCollapsibleSection<Header: View, Content: View>: View {
    @Binding var isExpanded: Bool
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                ZStack(alignment: .topTrailing) {
                    header()
                        .frame(maxWidth: .infinity)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)
                        .padding(.top, 2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

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
}
