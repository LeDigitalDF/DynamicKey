// diagnostic-log.js
// Ring buffer of recent extension events for support diagnostic exports.

import { browserAPI } from "./browser.js";

const LOG_KEY = "keystrokeauth.diagnosticLog";
const MAX_LOG_ENTRIES = 40;

/**
 * Appends one diagnostic event to the rolling log stored in extension storage.
 * @param {"info" | "warn" | "error"} level
 * @param {string} message
 * @param {string | null} [detail]
 */
export async function appendDiagnosticLog(level, message, detail = null) {
  const entry = {
    at: new Date().toISOString(),
    level,
    message: String(message ?? "").trim(),
    detail: detail ? String(detail).trim().slice(0, 500) : null,
  };

  if (!entry.message) {
    return;
  }

  const result = await browserAPI.storage.local.get(LOG_KEY);
  const existing = Array.isArray(result[LOG_KEY]) ? result[LOG_KEY] : [];
  const next = [...existing, entry].slice(-MAX_LOG_ENTRIES);
  await browserAPI.storage.local.set({ [LOG_KEY]: next });
}

/**
 * Reads the saved diagnostic log entries (oldest first).
 * @returns {Promise<Array<{ at: string, level: string, message: string, detail: string | null }>>}
 */
export async function loadDiagnosticLogs() {
  const result = await browserAPI.storage.local.get(LOG_KEY);
  return Array.isArray(result[LOG_KEY]) ? result[LOG_KEY] : [];
}
