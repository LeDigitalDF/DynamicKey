// LeakPeekDetailView.swift
// Breach monitoring for saved site passwords via Have I Been Pwned k-anonymity checks.
// Flow: LeakPeek icon watermark → dynamic title header → Scan Now → grouped site list → auto-scan toggle.

import AppKit
import SwiftUI

struct LeakPeekDetailView: View {
  @Environment(\.glassPalette) private var palette

  let credentials: [SiteCredential]

  @ObservedObject private var leakPeek = LeakPeekStore.shared
  @ObservedObject private var identityStore = LeakPeekIdentityStore.shared

  private var monitorableEmails: [String] {
    LeakPeekEmailValidator.uniqueEmails(from: credentials)
  }

  private var sortedCredentials: [SiteCredential] {
    credentials.sorted { displayOrigin($0.origin) < displayOrigin($1.origin) }
  }

  var body: some View {
    ZStack {
      DetailPaneSectionIconWatermarkBackground(section: .leakPeek)

      detailScrollContent
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .clipped()
    .onAppear {
      leakPeek.syncCredentialList(credentials)
    }
    .onChange(of: credentials.map(\.id)) { _, _ in
      leakPeek.syncCredentialList(credentials)
    }
  }

  private var detailScrollContent: some View {
    ScrollView(.vertical, showsIndicators: true) {
      VStack(spacing: GlassTheme.sectionSpacing) {
        detailHeader

        scanActionsRow

        if let lastScanError = leakPeek.lastScanError {
          Text(lastScanError)
            .font(.caption)
            .foregroundStyle(.orange)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }

        testingHintBanner

        savedSitesSection

        autoScanSettingsCard

        lastScannedFooter
      }
      .padding(.horizontal, 24)
      .padding(.top, 10)
      .padding(.bottom, 24)
      .frame(maxWidth: 820, alignment: .center)
      .frame(maxWidth: .infinity, alignment: .center)
    }
    .scrollContentBackground(.hidden)
  }

  // Title + dynamic status copy — no hero icon; pane watermark carries the brand visual.
  private var detailHeader: some View {
    let hasPasswordScan = leakPeek.lastScanDate != nil
    let hasIdentityScan = identityStore.lastIdentityCheckDate != nil
    let hasScan = hasPasswordScan || hasIdentityScan
    let needsAction = leakPeek.hasCompromisedPasswords || identityStore.hasCompromisedIdentities
    let isSafe = hasScan && !needsAction

    return VStack(spacing: 4) {
      Text(headerTitle(isSafe: isSafe, needsAction: needsAction, hasScan: hasScan))
        .font(.largeTitle.weight(.bold))
        .multilineTextAlignment(.center)
        .accessibilityAddTraits(.isHeader)

      Text(headerSubtitle(isSafe: isSafe, needsAction: needsAction, hasScan: hasScan))
        .font(.subheadline)
        .foregroundStyle(palette.onGlassSecondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity)
  }

  // Side-by-side round actions — password hash scan and email breach lookup.
  private var scanActionsRow: some View {
    HStack(spacing: 28) {
      LeakPeekRoundActionButton(
        title: "Scan Now",
        subtitle: "Saved passwords",
        systemImage: "key.horizontal.fill",
        sparklePalette: .indigo,
        isLoading: leakPeek.isScanning,
        isEnabled: !credentials.isEmpty && !identityStore.isChecking
      ) {
        Task {
          await leakPeek.scan(credentials: credentials)
        }
      }

      LeakPeekRoundActionButton(
        title: "Check Breaches",
        subtitle: monitorableEmails.isEmpty ? "No emails saved" : "\(monitorableEmails.count) email\(monitorableEmails.count == 1 ? "" : "s")",
        systemImage: "envelope.badge.shield.half.filled",
        sparklePalette: .blue,
        tint: Color(red: 0.2, green: 0.58, blue: 0.92),
        isLoading: identityStore.isChecking,
        isEnabled: !monitorableEmails.isEmpty && !leakPeek.isScanning
      ) {
        Task {
          await identityStore.checkBreaches(credentials: credentials)
        }
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 4)
  }

  // Testing note — LeakPeek reads Mac vault passwords, not browser typing.
  private var testingHintBanner: some View {
    HomeWidgetCard(title: "Testing LeakPeek", usesLiquidGlass: true) {
      VStack(alignment: .leading, spacing: 8) {
        Label("How scans work", systemImage: "flask")
          .font(.caption.weight(.semibold))
          .foregroundStyle(palette.onGlassSecondary)

        Text(
          "Scan Now checks saved passwords with k-anonymity (HIBP). Check Breaches looks up saved email usernames in public breach records — "
          + "results stay inside DynamicKey with a progress overlay. Neither scan reads what you type in the browser."
        )
        .font(.caption)
        .foregroundStyle(palette.onGlassSecondary)
        .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  // Saved websites list — real Liquid Glass panel matching Allowed List.
  private var savedSitesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Saved websites")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(palette.onGlassSecondary)

      leakPeekForm
        .background {
          LiquidGlassSurface(cornerRadius: GlassTheme.cornerRadius)
        }
        .clipShape(RoundedRectangle(cornerRadius: GlassTheme.cornerRadius, style: .continuous))
    }
  }

  private var leakPeekForm: some View {
    Form {
      Section {
        if sortedCredentials.isEmpty {
          Text("No saved website passwords yet. Add credentials to scan them for known breaches.")
            .font(.subheadline)
            .foregroundStyle(palette.onGlassSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        } else {
          ForEach(sortedCredentials) { credential in
            leakPeekRow(credential: credential)
              .listRowBackground(Color.clear)
          }
        }
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
    .backgroundStyle(.clear)
    .scrollDisabled(true)
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: .infinity)
    .background { AllowlistFormBackgroundClearer() }
  }

  private func leakPeekRow(credential: SiteCredential) -> some View {
    let status = leakPeek.siteStatus(for: credential.id)

    return HStack(alignment: .center, spacing: 12) {
      SiteFaviconView(origin: credential.origin, size: 36)

      VStack(alignment: .leading, spacing: 3) {
        Text(displayOrigin(credential.origin))
          .font(.subheadline)
          .foregroundStyle(.primary)
          .lineLimit(2)
          .multilineTextAlignment(.leading)

        Text(credential.username.isEmpty ? "No username" : credential.username)
          .font(.caption)
          .foregroundStyle(palette.onGlassSecondary)
          .lineLimit(1)
      }

      Spacer(minLength: 8)

      VStack(alignment: .trailing, spacing: 6) {
        LeakPeekStatusBadge(status: status)

        if LeakPeekEmailValidator.isEmail(credential.username) {
          let identityStatus = identityStore.identityStatus(for: credential.username)
          if identityStatus != .unknown {
            LeakPeekIdentityBadge(
              status: identityStatus,
              breachCount: identityStore.activeBreachNames(forEmail: credential.username).count
            )
          }
        }

        if status == .compromised {
          GlassTextButton(title: "Fix It", systemImage: "arrow.up.right.square") {
            openSiteForPasswordReset(credential)
          }
        }
      }
    }
    .padding(.vertical, 2)
  }

  private var autoScanSettingsCard: some View {
    HomeWidgetCard(title: "Background scanning", usesLiquidGlass: true) {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Scan automatically every week")
            .font(.subheadline.weight(.medium))

          Text("LeakPeek checks your saved passwords in the background using k-anonymity — only a hash prefix leaves your Mac.")
            .font(.caption)
            .foregroundStyle(palette.onGlassSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 0)

        GlassCapsuleBinaryToggle(
          isOn: $leakPeek.weeklyAutoScanEnabled,
          offSystemImage: "pause.fill",
          onSystemImage: "clock.arrow.circlepath",
          onTint: .green,
          accessibilityLabel: "Weekly automatic LeakPeek scan"
        )
      }
    }
  }

  private var lastScannedFooter: some View {
    VStack(spacing: 4) {
      Text(lastScannedLabel)
      if let identityDate = identityStore.lastIdentityCheckDate {
        Text("Last email check \(Self.lastScanFormatter.string(from: identityDate))")
      }
    }
    .font(.caption)
    .foregroundStyle(.tertiary)
    .frame(maxWidth: .infinity, alignment: .center)
    .padding(.top, 4)
  }

  private var lastScannedLabel: String {
    guard let date = leakPeek.lastScanDate else {
      return "Not scanned yet"
    }
    return "Last scanned \(Self.lastScanFormatter.string(from: date))"
  }

  private func headerTitle(isSafe: Bool, needsAction: Bool, hasScan: Bool) -> String {
    if needsAction { return "Action Required" }
    if isSafe { return "You're Safe" }
    return "LeakPeek"
  }

  private func headerSubtitle(isSafe: Bool, needsAction: Bool, hasScan: Bool) -> String {
    if needsAction {
      return "One or more saved passwords or email addresses appeared in known data breaches. Use Fix It for passwords, or review email results from Check Breaches."
    }
    if isSafe {
      return "None of your saved website passwords matched known breach databases."
    }
    if credentials.isEmpty {
      return "Add website credentials, then scan them against Have I Been Pwned."
    }
    return "Tap Scan Now to check your saved passwords privately."
  }

  private func displayOrigin(_ origin: String) -> String {
    let normalized = SiteCredential.normalizeOrigin(origin)
    guard !normalized.isEmpty else { return origin }

    if let host = URL(string: normalized)?.host {
      return host
    }
    return normalized
  }

  /// Opens the best account/security URL and signals the extension via ?dynamickey-fix=1.
  private func openSiteForPasswordReset(_ credential: SiteCredential) {
    guard let url = SitePasswordChangeURLResolver.preferredFixURL(for: credential.origin) else { return }
    NSWorkspace.shared.open(url)
  }

  private static let lastScanFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    formatter.doesRelativeDateFormatting = true
    return formatter
  }()
}
