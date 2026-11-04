// diagnostic-report.js
// Builds a plain-text support report from extension state and recent activity.

import { browserAPI } from "./browser.js";
import { detectBrowserFamily, pairingClientNameForFamily } from "./config.js";
import {
  loadConnectionSnapshot,
  loadDebugMode,
  loadMailShieldEnabled,
} from "./storage.js";
import { appendDiagnosticLog, loadDiagnosticLogs } from "./diagnostic-log.js";

/**
 * Masks a paired client ID for safe sharing in support reports.
 * @param {string | null | undefined} clientId
 * @returns {string}
 */
function maskClientId(clientId) {
  const value = String(clientId ?? "").trim();
  if (!value) {
    return "—";
  }
  if (value.length <= 8) {
    return "****";
  }
  return `${value.slice(0, 4)}…${value.slice(-4)}`;
}

/**
 * Derives a readable OS label from the browser user agent.
 * @param {string} userAgent
 * @returns {string}
 */
function detectOsLabel(userAgent) {
  const ua = String(userAgent ?? "");
  if (/Mac OS X|Macintosh/i.test(ua)) {
    const match = ua.match(/Mac OS X ([0-9_]+)/i);
    return match ? `macOS ${match[1].replace(/_/g, ".")}` : "macOS";
  }
  if (/Windows NT/i.test(ua)) {
    return "Windows";
  }
  if (/Linux/i.test(ua)) {
    return "Linux";
  }
  if (/iPhone|iPad|iOS/i.test(ua)) {
    return "iOS";
  }
  return "Unknown";
}

/**
 * Formats cached Mac status fields without secrets.
 * @param {object | null | undefined} status
 * @returns {string[]}
 */
function formatMacStatusLines(status) {
  if (!status || typeof status !== "object") {
    return ["  (no cached Mac app status)"];
  }

  /** @type {string[]} */
  const lines = [];
  const fields = [
    ["pairedClientCount", status.pairedClientCount],
    ["profileEnrolled", status.profileEnrolled],
    ["safeModeActive", status.safeModeActive],
    ["dynamicShieldTrustedRevision", status.dynamicShieldTrustedRevision],
    ["lastVerifiedAt", status.lastVerifiedAt],
  ];

  for (const [label, value] of fields) {
    if (value !== undefined && value !== null) {
      lines.push(`  ${label}: ${value}`);
    }
  }

  return lines.length > 0 ? lines : ["  (no cached Mac app status)"];
}

/**
 * Builds the diagnostic report payload for download in the options page.
 * @returns {Promise<{ text: string, filename: string }>}
 */
export async function buildDiagnosticReport() {
  await appendDiagnosticLog("info", "Diagnostic report exported");

  const [
    snapshot,
    debugMode,
    mailShieldEnabled,
    logs,
    browserFamily,
  ] = await Promise.all([
    loadConnectionSnapshot(),
    loadDebugMode(),
    loadMailShieldEnabled(),
    loadDiagnosticLogs(),
    detectBrowserFamily(),
  ]);

  const manifest = browserAPI.runtime.getManifest?.() ?? {};
  const version = manifest.version ?? "dev";
  const browserLabel = snapshot.session?.clientName ?? pairingClientNameForFamily(browserFamily);
  const userAgent = globalThis.navigator?.userAgent ?? "Unknown";
  const platform = globalThis.navigator?.platform ?? "Unknown";
  const osLabel = detectOsLabel(userAgent);
  const generatedAt = new Date().toISOString();
  const stamp = generatedAt.replace(/[:.]/g, "-").slice(0, 19);

  /** @type {string[]} */
  const lines = [
    "DynamicKey Extension Diagnostic Report",
    "======================================",
    "",
    `Generated: ${generatedAt}`,
    "",
    "Environment",
    "-----------",
    `Extension Version: ${version}`,
    `Browser: ${browserLabel} (${browserFamily})`,
    `Operating System: ${osLabel}`,
    `Platform: ${platform}`,
    `User Agent: ${userAgent}`,
    "",
    "Connection",
    "----------",
    `Connection State: ${snapshot.state ?? "unknown"}`,
    `Paired: ${snapshot.session ? "yes" : "no"}`,
    `Client ID: ${maskClientId(snapshot.session?.clientId)}`,
    `Client Name: ${snapshot.session?.clientName ?? "—"}`,
    `Paired At: ${snapshot.session?.pairedAt ?? "—"}`,
    `Last Checked: ${snapshot.lastCheckedAt ?? "—"}`,
    `Last Verified: ${snapshot.lastVerifiedAt ?? "—"}`,
    `Last Error: ${snapshot.lastError ?? "none"}`,
    `Mail Shield: ${mailShieldEnabled ? "enabled" : "disabled"}`,
    `Debug Mode: ${debugMode ? "enabled" : "disabled"}`,
    "",
    "Mac App Status (cached)",
    "-----------------------",
    ...formatMacStatusLines(snapshot.lastStatus),
    "",
    "Recent Activity",
    "---------------",
  ];

  if (logs.length === 0) {
    lines.push("  (no recent activity recorded yet)");
  } else {
    for (const entry of logs) {
      const detailSuffix = entry.detail ? ` — ${entry.detail}` : "";
      lines.push(`[${entry.at}] ${entry.level.toUpperCase()} ${entry.message}${detailSuffix}`);
    }
  }

  lines.push("");
  lines.push("Notes");
  lines.push("-----");
  lines.push("This report excludes access tokens and passwords.");
  lines.push("Attach this file when contacting DynamicKey support.");

  return {
    text: `${lines.join("\n")}\n`,
    filename: `dynamickey-diagnostic-${stamp}.txt`,
  };
}
