// SecurityActivityDetailView.swift
// Security audit timeline in the main detail pane with floating period tab bar.
// Flow: shield icon watermark → fixed title header → faded scroll timeline → floating tab bar.

import SwiftUI

struct SecurityActivityDetailView: View {
    let auditEvents: [AuditEvent]
    let onClearAuditLog: (SecurityActivityPeriod) -> Void

    @State private var selectedPeriod: SecurityActivityPeriod = .today
    @State private var selectedCategory: SecurityActivityCategory = .all

    private let topFadeHeight: CGFloat = ClearGlassSegmentedTabBarLayout.floatingOverlayHeight
    private let bottomFadeHeight: CGFloat = 40

    private var filteredEvents: [AuditEvent] {
        selectedPeriod
            .filter(auditEvents)
            .filter { selectedCategory.matches($0) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private var timelineTextColor: Color {
        selectedCategory == .all ? selectedPeriod.timelineTextColor : selectedCategory.timelineTextColor
    }

    var body: some View {
        ZStack {
            DetailPaneSectionIconWatermarkBackground(section: .securityActivity)

            VStack(spacing: 0) {
                topHeaderChrome

                ZStack(alignment: .top) {
                    timelineScrollArea

                    floatingCategoryTabBar
                }

                bottomTabBarChrome
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // Scrollable timeline between header and tab bar — fades at both edges, no backdrop chrome.
    private var timelineScrollArea: some View {
        ScrollView {
            SecurityActivityTimelineView(
                events: filteredEvents,
                emptyMessage: selectedCategory.emptyMessage(for: selectedPeriod),
                period: selectedPeriod,
                textColor: timelineTextColor
            )
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.top, ClearGlassSegmentedTabBarLayout.floatingOverlayHeight)
            .padding(.bottom, 12)
            .animation(.easeInOut(duration: 0.22), value: selectedPeriod)
            .animation(.easeInOut(duration: 0.22), value: selectedCategory)
        }
        .scrollContentBackground(.hidden)
        .mask(timelineEdgeFadeMask)
    }

    // Soft fade at top and bottom so content disappears before the header and tab bar.
    private var timelineEdgeFadeMask: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: topFadeHeight)

            Rectangle()
                .fill(Color.black)

            LinearGradient(
                colors: [.black, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: bottomFadeHeight)
        }
    }

    // Fixed header — title and subtitle only; category tabs float over the timeline.
    private var topHeaderChrome: some View {
        MainDetailSectionHeader(
            section: .securityActivity,
            subtitle: "Review sign-in, extension, and DynamicShield activity on this Mac.",
            showsSectionIcon: false,
            indentsForBackButton: true
        )
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
    }

    // Floating morph glass category bar — timeline scrolls beneath for live refraction.
    private var floatingCategoryTabBar: some View {
        HStack {
            Spacer(minLength: 0)
            SecurityActivityCategoryTabBar(selection: $selectedCategory)
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    // Floating bottom tab bar — capsule only, no backdrop.
    private var bottomTabBarChrome: some View {
        HStack {
            Spacer(minLength: 0)
            SecurityActivityPeriodTabBar(
                selection: $selectedPeriod,
                onClearPeriod: onClearAuditLog
            )
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .padding(.bottom, 20)
    }
}
