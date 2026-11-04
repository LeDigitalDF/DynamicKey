// BackButton.swift
// Navigation control for returning to the previous enrollment step.

import SwiftUI

struct BackButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        HStack {
            Button(action: action) {
                Label(title, systemImage: "chevron.left")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)

            Spacer()
        }
    }
}
