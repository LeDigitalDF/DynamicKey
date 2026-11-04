// config.js
// Shared constants for the KeyStrokeAuth browser extension (W1).
// Must stay in sync with ExtensionAuthConfig.swift on the Mac app.

/** @type {Readonly<{ protocolVersion: number, baseURL: string, routes: Record<string, string>, clientName: string, healthCheckMinutes: number }>} */
export const EXTENSION_CONFIG = Object.freeze({
  protocolVersion: 1,
  baseURL: "http://127.0.0.1:17487",
  routes: {
    status: "/v1/status",
    pair: "/v1/pair",
    verify: "/v1/verify",
    fillApprove: "/v1/fill-approve",
    resetLockout: "/v1/reset-lockout",
    allowlistCheck: "/v1/allowlist/check",
    allowlistAdd: "/v1/allowlist/add",
    allowlistIgnore: "/v1/allowlist/ignore",
    dynamicShieldTrust: "/v1/dynamic-shield/trust",
    dynamicShieldList: "/v1/dynamic-shield/list",
    dynamicShieldEvent: "/v1/dynamic-shield/event",
    credentialsCheck: "/v1/credentials/check",
    openApp: "/v1/app/open",
    safeModeActivate: "/v1/safe-mode/activate",
    safeModeDeactivate: "/v1/safe-mode/deactivate",
  },
  clientName: "DynamicKey Browser Extension",
  healthCheckMinutes: 1,
});

/**
 * True when the user agent is Apple Safari (not Chromium's Safari/537.36 token).
 * @param {string} userAgent
 * @returns {boolean}
 */
function isAppleSafariUserAgent(userAgent) {
  return /Version\/[\d.]+.*Safari/i.test(userAgent)
    && !/Chrome|Chromium|CriOS|Edg|Brave|Firefox|FxiOS/i.test(userAgent);
}

/**
 * True when this bundle is running as a Firefox Web Extension.
 * @returns {boolean}
 */
function isFirefoxWebExtension() {
  try {
    const runtime = globalThis.browser?.runtime ?? globalThis.chrome?.runtime;
    const manifest = runtime?.getManifest?.();
    if (manifest?.browser_specific_settings?.gecko) {
      return typeof globalThis.chrome === "undefined";
    }
  } catch {
    // Fall back to UA below.
  }

  const userAgent = globalThis.navigator?.userAgent ?? "";
  return /firefox|fxios/i.test(userAgent);
}

/**
 * True only when this bundle is running as a Safari Web Extension.
 * @returns {boolean}
 */
export function isSafariWebExtension() {
  if (isFirefoxWebExtension()) {
    return false;
  }
  if (typeof globalThis.safari !== "undefined") {
    return true;
  }

  const userAgent = globalThis.navigator?.userAgent ?? "";
  if (isAppleSafariUserAgent(userAgent)) {
    return true;
  }

  try {
    const runtime = globalThis.browser?.runtime ?? globalThis.chrome?.runtime;
    const manifest = runtime?.getManifest?.();
    // Safari Web Extensions use the `browser` namespace; Chromium builds use `chrome`.
    if (
      typeof globalThis.browser !== "undefined"
      && typeof globalThis.chrome === "undefined"
      && manifest?.browser_specific_settings?.safari
      && !manifest?.browser_specific_settings?.gecko
    ) {
      return true;
    }
  } catch {
    return false;
  }

  return false;
}

/**
 * Reads browser family from manifest — only when actually running in Safari.
 * @returns {string|null}
 */
function manifestBrowserFamily() {
  if (!isSafariWebExtension()) {
    return null;
  }

  return "safari";
}

/**
 * Reads Chromium brand hints when the UA string omits Brave/Chrome tokens.
 * @returns {string|null}
 */
function userAgentDataBrowserFamily() {
  const brands = globalThis.navigator?.userAgentData?.brands;
  if (!Array.isArray(brands)) {
    return null;
  }

  const joined = brands.map((entry) => String(entry?.brand ?? "")).join(" ");
  if (/brave/i.test(joined)) {
    return "brave";
  }
  if (/microsoft edge/i.test(joined)) {
    return "edge";
  }
  if (/chromium|chrome|google chrome/i.test(joined)) {
    return "chrome";
  }

  return null;
}

/**
 * Browser family slug stored on the Mac app for Chrome | Safari | Brave display.
 * Sync fallback — prefer detectBrowserFamily() when pairing.
 * @returns {string}
 */
export function pairingBrowserFamily() {
  if (isSafariWebExtension()) {
    return "safari";
  }

  if (isFirefoxWebExtension()) {
    return "firefox";
  }

  const fromBrands = userAgentDataBrowserFamily();
  if (fromBrands) {
    return fromBrands;
  }

  const userAgent = globalThis.navigator?.userAgent ?? "";

  if (/brave/i.test(userAgent)) {
    return "brave";
  }
  if (/firefox|fxios/i.test(userAgent)) {
    return "firefox";
  }
  if (/edg\//i.test(userAgent)) {
    return "edge";
  }
  if (/chrome|chromium|crios/i.test(userAgent)) {
    return "chrome";
  }

  if (isAppleSafariUserAgent(userAgent)) {
    return "safari";
  }

  // Chromium extension pages often ship a minimal UA ending in Safari/537.36 — default to Chrome, not Safari.
  return "chrome";
}

/**
 * Async browser detection — Brave exposes isBrave() even when the UA looks like Safari.
 * @returns {Promise<string>}
 */
export async function detectBrowserFamily() {
  if (isSafariWebExtension()) {
    return "safari";
  }

  if (isFirefoxWebExtension()) {
    return "firefox";
  }

  try {
    const brave = globalThis.navigator?.brave;
    if (brave?.isBrave) {
      const probe = brave.isBrave();
      const isBrave = probe && typeof probe.then === "function" ? await probe : probe;
      if (isBrave) {
        return "brave";
      }
    }
  } catch {
    // Fall back to UA heuristics below.
  }

  return pairingBrowserFamily();
}

/**
 * Display label for a resolved browser family slug.
 * @param {string} family
 * @returns {string}
 */
export function pairingClientNameForFamily(family) {
  switch (family) {
    case "firefox":
      return "Firefox Extension";
    case "edge":
      return "Edge Extension";
    case "safari":
      return "Safari Extension";
    case "brave":
      return "Brave Extension";
    case "chrome":
    default:
      return "Chrome Extension";
  }
}

/**
 * Browser-specific label sent when pairing so the Mac app can show Chrome | Safari | Firefox.
 * @returns {string}
 */
export function pairingClientName() {
  return pairingClientNameForFamily(pairingBrowserFamily());
}
