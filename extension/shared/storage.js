// storage.js
// Persists pairing tokens and connection state in extension storage (W1 / W4.5 Safari).

import { browserAPI } from "./browser.js";

/** @typedef {'not_paired' | 'connected' | 'disconnected' | 'mac_app_stopped' | 'no_profile'} ConnectionState */

/**
 * @typedef {Object} PairedSession
 * @property {string} accessToken
 * @property {string} clientId
 * @property {string | null} clientName
 * @property {string} pairedAt
 */

const STORAGE_KEYS = Object.freeze({
  session: "keystrokeauth.session",
  connectionState: "keystrokeauth.connectionState",
  lastStatus: "keystrokeauth.lastStatus",
  lastCheckedAt: "keystrokeauth.lastCheckedAt",
  lastVerifiedAt: "keystrokeauth.lastVerifiedAt",
  lastError: "keystrokeauth.lastError",
  debugMode: "keystrokeauth.debugMode",
  mailShieldEnabled: "keystrokeauth.mailShieldEnabled",
  mailShieldTrustedDomains: "keystrokeauth.mailShieldTrustedDomains",
  dynamicShieldRevision: "keystrokeauth.dynamicShieldRevision",
});

/** Storage key for DynamicShield trusted sender domains (shared with mail-shield.js). */
export const MAIL_SHIELD_TRUSTED_DOMAINS_KEY = STORAGE_KEYS.mailShieldTrustedDomains;

/**
 * Reads the saved paired session from extension storage.
 * @returns {Promise<PairedSession | null>}
 */
export async function loadSession() {
  const result = await browserAPI.storage.local.get(STORAGE_KEYS.session);
  return result[STORAGE_KEYS.session] ?? null;
}

/**
 * Saves a paired session after successful pairing with the Mac app.
 * @param {PairedSession} session
 */
export async function saveSession(session) {
  await browserAPI.storage.local.set({
    [STORAGE_KEYS.session]: session,
    [STORAGE_KEYS.connectionState]: "connected",
    [STORAGE_KEYS.lastError]: null,
  });
}

/**
 * Clears pairing data and resets connection state.
 */
export async function clearSession() {
  await browserAPI.storage.local.remove([
    STORAGE_KEYS.session,
    STORAGE_KEYS.lastStatus,
    STORAGE_KEYS.lastCheckedAt,
    STORAGE_KEYS.lastVerifiedAt,
    STORAGE_KEYS.lastError,
  ]);
  await browserAPI.storage.local.set({
    [STORAGE_KEYS.connectionState]: "not_paired",
  });
}

/**
 * @returns {Promise<ConnectionState>}
 */
export async function loadConnectionState() {
  const result = await browserAPI.storage.local.get(STORAGE_KEYS.connectionState);
  return result[STORAGE_KEYS.connectionState] ?? "not_paired";
}

/**
 * @param {ConnectionState} state
 * @param {{ message?: string, status?: object }} [meta]
 */
export async function saveConnectionState(state, meta = {}) {
  const payload = { [STORAGE_KEYS.connectionState]: state };
  if (meta.message !== undefined) {
    payload[STORAGE_KEYS.lastError] = meta.message;
  }
  if (meta.status !== undefined) {
    payload[STORAGE_KEYS.lastStatus] = meta.status;
    payload[STORAGE_KEYS.lastCheckedAt] = new Date().toISOString();
  }
  await browserAPI.storage.local.set(payload);
}

/**
 * Records the last successful rhythm verification on a website.
 */
export async function saveLastVerifiedAt(isoTimestamp = new Date().toISOString()) {
  await browserAPI.storage.local.set({
    [STORAGE_KEYS.lastVerifiedAt]: isoTimestamp,
  });
}

/**
 * @returns {Promise<{ state: ConnectionState, lastStatus: object | null, lastCheckedAt: string | null, lastVerifiedAt: string | null, lastError: string | null, session: PairedSession | null }>}
 */
export async function loadConnectionSnapshot() {
  const result = await browserAPI.storage.local.get([
    STORAGE_KEYS.connectionState,
    STORAGE_KEYS.lastStatus,
    STORAGE_KEYS.lastCheckedAt,
    STORAGE_KEYS.lastVerifiedAt,
    STORAGE_KEYS.lastError,
    STORAGE_KEYS.session,
  ]);

  return {
    state: result[STORAGE_KEYS.connectionState] ?? "not_paired",
    lastStatus: result[STORAGE_KEYS.lastStatus] ?? null,
    lastCheckedAt: result[STORAGE_KEYS.lastCheckedAt] ?? null,
    lastVerifiedAt: result[STORAGE_KEYS.lastVerifiedAt] ?? null,
    lastError: result[STORAGE_KEYS.lastError] ?? null,
    session: result[STORAGE_KEYS.session] ?? null,
  };
}

/**
 * @returns {Promise<boolean>}
 */
export async function loadDebugMode() {
  const result = await browserAPI.storage.local.get(STORAGE_KEYS.debugMode);
  return Boolean(result[STORAGE_KEYS.debugMode]);
}

/**
 * @param {boolean} enabled
 */
export async function saveDebugMode(enabled) {
  await browserAPI.storage.local.set({
    [STORAGE_KEYS.debugMode]: enabled,
  });
}

/**
 * Mail Shield is ON by default when the user has never changed the setting.
 * @returns {Promise<boolean>}
 */
export async function loadMailShieldEnabled() {
  const result = await browserAPI.storage.local.get(STORAGE_KEYS.mailShieldEnabled);
  if (result[STORAGE_KEYS.mailShieldEnabled] === undefined) {
    return true;
  }
  return Boolean(result[STORAGE_KEYS.mailShieldEnabled]);
}

/**
 * @param {boolean} enabled
 */
export async function saveMailShieldEnabled(enabled) {
  await browserAPI.storage.local.set({
    [STORAGE_KEYS.mailShieldEnabled]: enabled,
  });
}

/**
 * Trusted sender domains for DynamicShield (future Allowed List sync).
 * @returns {Promise<string[]>}
 */
export async function loadMailShieldTrustedDomains() {
  const result = await browserAPI.storage.local.get(STORAGE_KEYS.mailShieldTrustedDomains);
  const list = result[STORAGE_KEYS.mailShieldTrustedDomains];
  return Array.isArray(list) ? list : [];
}

/**
 * @param {string} domain
 * @returns {Promise<string[]>}
 */
export async function addMailShieldTrustedDomain(domain) {
  const normalized = String(domain ?? "").trim().toLowerCase().replace(/^@/, "");
  if (!normalized) {
    return loadMailShieldTrustedDomains();
  }

  const current = await loadMailShieldTrustedDomains();
  if (current.includes(normalized)) {
    return current;
  }

  const next = [...current, normalized].sort();
  await browserAPI.storage.local.set({
    [STORAGE_KEYS.mailShieldTrustedDomains]: next,
  });
  return next;
}

/**
 * Replaces the extension trusted-sender list (Mac app is source of truth when paired).
 * @param {string[]} domains
 */
export async function saveMailShieldTrustedDomains(domains) {
  const normalized = Array.isArray(domains)
    ? [...new Set(domains.map((domain) => String(domain ?? "").trim().toLowerCase().replace(/^@/, "")).filter(Boolean))].sort()
    : [];
  await browserAPI.storage.local.set({
    [STORAGE_KEYS.mailShieldTrustedDomains]: normalized,
  });
  return normalized;
}

/**
 * Reads the last DynamicShield trusted-list revision synced from the Mac app.
 * @returns {Promise<number>}
 */
export async function loadDynamicShieldRevision() {
  const result = await browserAPI.storage.local.get(STORAGE_KEYS.dynamicShieldRevision);
  return Number(result[STORAGE_KEYS.dynamicShieldRevision] ?? 0);
}

/**
 * Persists the Mac app DynamicShield trusted-list revision after a successful sync.
 * @param {number} revision
 */
export async function saveDynamicShieldRevision(revision) {
  await browserAPI.storage.local.set({
    [STORAGE_KEYS.dynamicShieldRevision]: Number(revision) || 0,
  });
}
