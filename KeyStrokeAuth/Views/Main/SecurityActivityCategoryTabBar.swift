// SecurityActivityCategoryTabBar.swift
// Top category filter for Security Activity — All, Sign-in, Shield.
// Uses ClearGlassSegmentedTabBar (content-sized sliding pill + icon labels).

import SwiftUI

struct SecurityActivityCategoryTabBar: View {
    @Binding var selection: SecurityActivityCategory

    var body: some View {
        ClearGlassSegmentedTabBar(
            selection: $selection,
            segments: SecurityActivityCategory.allCases,
            segmentTitle: { $0.title },
            segmentIcon: { $0.symbolName },
            segmentAccent: { $0.timelineTextColor },
            accessibilityLabel: "Security activity category"
        )
    }
}
