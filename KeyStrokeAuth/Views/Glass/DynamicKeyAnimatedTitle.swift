// DynamicKeyAnimatedTitle.swift
// “DynamicKey” landing title using Lettertype assets with wiggle animation.

import SwiftUI

struct DynamicKeyAnimatedTitle: View {
    @Environment(\.colorScheme) private var colorScheme

    var letterHeight: CGFloat = 48

    var body: some View {
        LettertypeTitleView(
            phrase: "DynamicKey",
            letterHeight: letterHeight,
            letterSpacing: 0,
            wordSpacing: 0,
            animate: true,
            showsLetterDropShadow: colorScheme == .light
        )
        .frame(maxWidth: .infinity)
    }
}
