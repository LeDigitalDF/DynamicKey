// DynamicKeyPreferencesView.swift
// Raycast-style Preferences — free-floating icon tabs, form rows with label | control spine.
//
// Flow: toolbar tabs (no capsule track) → General content → other tabs placeholder.

import SwiftUI

/// Tabs shown across the top of the Preferences window.
private enum PreferencesTab: String, CaseIterable, Identifiable, Hashable {
    case general
    case theme
    case advanced
    case updates
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .theme: return "Theme"
        case .advanced: return "Advanced"
        case .updates: return "Updates"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .theme: return "paintpalette"
        case .advanced: return "slider.horizontal.3"
        case .updates: return "arrow.triangle.2.circlepath"
        case .about: return "info.circle"
        }
    }
}

struct DynamicKeyPreferencesView: View {
    @EnvironmentObject private var preferences: AppPreferencesStore
    @EnvironmentObject private var appearance: AppAppearanceStore

    @ObservedObject private var launchAtLoginService = LaunchAtLoginService.shared

    @State private var selectedTab: PreferencesTab = .general

    private enum Layout {
        static let labelWidth: CGFloat = 150
        static let rowSpacing: CGFloat = 18
        static let columnGutter: CGFloat = 20
    }

    var body: some View {
        ZStack {
            // Soft frosted window — closer to Raycast vibrancy than the dashboard mesh alone.
            PreferencesWindowBackground()

            VStack(spacing: 0) {
                // Clear the traffic-light / title-bar zone (seamless full-size chrome).
                Color.clear
                    .frame(height: MainChromeLayout.rowHeight)
                    .accessibilityHidden(true)

                PreferencesIconTabBar(
                    selection: $selectedTab,
                    tabs: PreferencesTab.allCases,
                    title: { $0.title },
                    systemImage: { $0.icon }
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

                ScrollView {
                    tabContent
                        .padding(.horizontal, 36)
                        .padding(.bottom, 28)
                        .frame(maxWidth: 560)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
            }
        }
        .background {
            MainWindowChromeConfigurator(
                isLightMode: appearance.theme.resolvedColorScheme == .light
            )
        }
        .frame(minWidth: 580, minHeight: 440)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .general:
            generalPane
        case .theme, .advanced, .updates, .about:
            placeholderPane(for: selectedTab)
        }
    }

    // MARK: - General

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: Layout.rowSpacing) {
            preferencesRow(label: "Startup") {
                Toggle(isOn: $preferences.launchAtLoginEnabled) {
                    Text("Launch DynamicKey at Login")
                        .foregroundStyle(Color.primary)
                }
                .toggleStyle(.checkbox)
            }

            if let error = launchAtLoginService.lastErrorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.leading, Layout.labelWidth + Layout.columnGutter)
            }

            preferencesRow(label: "DynamicKey Hotkey") {
                PreferencesHotkeyRecorderButton(hotkey: $preferences.appHotkey)
            }

            Divider()
                .opacity(0.22)
                .padding(.vertical, 6)

            preferencesRow(label: "Appearance", alignment: .center) {
                appearanceChooser
            }
        }
    }

    /// Raycast appearance: one highlight wraps icon + label together when selected.
    private var appearanceChooser: some View {
        HStack(spacing: 10) {
            ForEach(AppTheme.allCases) { theme in
                appearanceOption(theme)
            }
            Spacer(minLength: 0)
        }
    }

    private func appearanceOption(_ theme: AppTheme) -> some View {
        let isSelected = appearance.theme == theme

        return Button {
            appearance.setTheme(theme)
        } label: {
            VStack(spacing: 7) {
                Image(systemName: theme.preferencesSystemImage)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color.primary)
                    .frame(width: 36, height: 36)
                    .background {
                        Circle()
                            .fill(Color.primary.opacity(0.06))
                    }
                    .overlay {
                        Circle()
                            .strokeBorder(
                                isSelected ? Color.primary.opacity(0.9) : Color.clear,
                                lineWidth: 1.5
                            )
                    }

                Text(theme.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.10))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Placeholders

    private func placeholderPane(for tab: PreferencesTab) -> some View {
        VStack(spacing: 8) {
            Text(tab.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.primary)

            Text("Options for \(tab.title.lowercased()) will be added next.")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 24)
    }

    // MARK: - Layout helpers

    /// Raycast form spine: right-aligned labels | left-aligned controls.
    private func preferencesRow<Content: View>(
        label: String,
        alignment: VerticalAlignment = .center,
        @ViewBuilder control: () -> Content
    ) -> some View {
        HStack(alignment: alignment, spacing: Layout.columnGutter) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Color.secondary)
                .frame(width: Layout.labelWidth, alignment: .trailing)

            control()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Window background

/// Frosted liquid-glass Preferences backdrop (Raycast-like vibrancy + soft color wash).
private struct PreferencesWindowBackground: View {
    var body: some View {
        ZStack {
            DynamicKeyDashboardBackground()

            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.35)
                .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
}
