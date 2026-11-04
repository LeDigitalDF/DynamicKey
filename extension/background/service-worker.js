// service-worker.js
// Background worker: pairing, health checks, and connection state (W1.4).
//
// Flow: popup messages → pair or check status → persist state → alarm keeps health fresh.

import { detectBrowserFamily, pairingClientNameForFamily, EXTENSION_CONFIG } from "../shared/config.js";
import { browserAPI } from "../shared/browser.js";
import { withTimeout } from "../shared/async.js";
import { fetchStatus, pairWithCode, connectionStateFromStatus, verifyLogin, resetLockout, requestFillApprove, checkAllowlist, addToAllowlist, ignoreOnAllowlist, trustDynamicShieldSender, fetchDynamicShieldTrustedDomains, logDynamicShieldEvent, checkCredentialForOrigin, openMacApp, activateSafeMode, deactivateSafeMode } from "../shared/api.js";
import { scanProtonIframeDocument } from "../shared/proton-iframe-scan.js";
import { buildDiagnosticReport } from "../shared/diagnostic-report.js";
import { appendDiagnosticLog } from "../shared/diagnostic-log.js";
import {
  clearSession,
  loadSession,
  saveSession,
  saveConnectionState,
  loadConnectionSnapshot,
  saveLastVerifiedAt,
  MAIL_SHIELD_TRUSTED_DOMAINS_KEY,
  loadMailShieldTrustedDomains,
  saveMailShieldTrustedDomains,
  loadDynamicShieldRevision,
  saveDynamicShieldRevision,
} from "../shared/storage.js";

/**
 * Scans Proton HTML mail inside sandboxed iframes where content scripts cannot run (Brave/Chromium).
 * @param {number} tabId
 * @returns {Promise<Array<{ id: string, detail?: string }>>}
 */
async function scanProtonIframeViaScripting(tabId) {
  if (!browserAPI.scripting?.executeScript || !browserAPI.webNavigation?.getAllFrames) {
    return [];
  }

  let frames = [];
  try {
    frames = await browserAPI.webNavigation.getAllFrames({ tabId });
  } catch {
    return [];
  }

  const preferredFrames = frames
    .filter((frame) => frame.frameId !== 0)
    .filter((frame) => {
      const url = String(frame.url ?? "");
      return url === "about:blank" || url === "about:srcdoc" || url === "";
    })
    .sort((left, right) => right.frameId - left.frameId);
  const tryFrames = preferredFrames.length > 0
    ? preferredFrames
    : frames.filter((frame) => frame.frameId !== 0).sort((left, right) => right.frameId - left.frameId);

  let bestFlags = [];

  for (const frame of tryFrames) {
    try {
      const [injection] = await browserAPI.scripting.executeScript({
        target: { tabId, frameIds: [frame.frameId] },
        func: scanProtonIframeDocument,
      });
      if (Array.isArray(injection?.result) && injection.result.length > bestFlags.length) {
        bestFlags = injection.result;
      }
    } catch {
      // Try the next sandboxed frame.
    }
  }

  return bestFlags;
}

const HEALTH_ALARM = "keystrokeauth-health-check";
/** Shown in popup, options, and page overlay when the Mac app rejects a saved token. */
const PAIRING_EXPIRED_MESSAGE =
  "Pairing expired on your Mac. Open DynamicKey → Settings → Browser Extension, generate a new code, then enter it in the extension popup or Options page.";
/** Shown when the user revoked all pairings in the Mac app. */
const PAIRING_REVOKED_MESSAGE =
  "Pairing was removed in DynamicKey. Generate a new code in Settings → Browser Extension, then enter it below.";
let applyingMacTrustedList = false;

/**
 * Clears local session when the Mac app reports zero paired extensions.
 * @param {object | null | undefined} status
 * @param {{ accessToken: string } | null} session
 * @returns {Promise<typeof session>}
 */
async function clearSessionIfMacRevokedAll(status, session) {
  if (!session) {
    return null;
  }

  const pairedCount = Number(status?.pairedClientCount ?? 0);
  if (pairedCount > 0) {
    return session;
  }

  await clearSession();
  await saveConnectionState("not_paired", { message: PAIRING_REVOKED_MESSAGE });
  await appendDiagnosticLog("warn", "Mac app revoked all pairings");
  return null;
}

/**
 * Clears stale local pairing when the Mac app rejects this extension token.
 * @param {unknown} error
 * @returns {Promise<boolean>}
 */
async function invalidateSessionIfUnauthorized(error) {
  if (error?.status !== 401) {
    return false;
  }

  await clearSession();
  await saveConnectionState("not_paired", { message: PAIRING_EXPIRED_MESSAGE });
  await appendDiagnosticLog("warn", "Pairing token rejected by Mac app", "401 unauthorized");
  return true;
}

/**
 * Runs an authenticated Mac API call and clears local pairing on 401.
 * @template T
 * @param {() => Promise<T>} apiCall
 * @returns {Promise<T>}
 */
async function withAuthenticatedCall(apiCall) {
  try {
    return await apiCall();
  } catch (error) {
    if (await invalidateSessionIfUnauthorized(error)) {
      throw new Error(PAIRING_EXPIRED_MESSAGE);
    }
    throw error;
  }
}

/**
 * @param {string | undefined} url
 * @returns {boolean}
 */
function isWebmailURL(url) {
  if (!url || (!url.startsWith("http://") && !url.startsWith("https://"))) {
    return false;
  }

  try {
    const host = new URL(url).hostname.toLowerCase();
    return (
      host === "mail.google.com"
      || host.includes("outlook.live.com")
      || host.includes("outlook.office.com")
      || host.includes("outlook.office365.com")
      || host === "mail.yahoo.com"
      || host.includes("mail.yahoo.")
    );
  } catch {
    return false;
  }
}

/**
 * Pulls the Mac app trusted-sender list into extension storage (source of truth when paired).
 */
async function syncDynamicShieldTrustedFromMac() {
  const session = await loadSession();
  if (!session?.accessToken) {
    return;
  }

  try {
    const result = await fetchDynamicShieldTrustedDomains(session.accessToken);
    const macDomains = Array.isArray(result?.trustedSenderDomains)
      ? result.trustedSenderDomains
          .map((domain) => String(domain ?? "").trim().toLowerCase().replace(/^@/, ""))
          .filter(Boolean)
          .sort()
      : [];
    const storedDomains = [...(await loadMailShieldTrustedDomains())]
      .map((domain) => String(domain).trim().toLowerCase())
      .sort();

    if (JSON.stringify(macDomains) !== JSON.stringify(storedDomains)) {
      applyingMacTrustedList = true;
      try {
        await saveMailShieldTrustedDomains(macDomains);
      } finally {
        applyingMacTrustedList = false;
      }
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : "Trusted list sync failed.";
    console.warn("[DynamicShield] Mac trusted-list sync failed:", message);
    throw error;
  }
}

/**
 * Pulls trusted senders when the Mac app revision changes.
 * @param {object | null | undefined} status
 */
async function syncDynamicShieldIfRevisionChanged(status) {
  const revision = Number(status?.dynamicShieldTrustedRevision ?? 0);
  const lastRevision = await loadDynamicShieldRevision();
  if (revision === lastRevision) {
    return false;
  }

  try {
    await syncDynamicShieldTrustedFromMac();
    await saveDynamicShieldRevision(revision);
    return true;
  } catch (error) {
    const message = error instanceof Error ? error.message : "Trusted list sync failed.";
    console.warn("[DynamicShield] Revision sync failed:", message);
    return false;
  }
}

/**
 * Clears stale local pairing when the Mac app revoked this extension token.
 * @param {{ accessToken: string }} session
 * @returns {Promise<boolean>} True when the session is still valid.
 */
async function validatePairedSession(session) {
  try {
    await withTimeout(
      fetchDynamicShieldTrustedDomains(session.accessToken),
      4000,
      "Pairing validation"
    );
    return true;
  } catch (error) {
    if (error?.status === 401) {
      await clearSession();
      await saveConnectionState("not_paired", { message: PAIRING_EXPIRED_MESSAGE });
      return false;
    }
    return true;
  }
}

/**
 * Checks Mac app status and updates stored connection state.
 * @returns {Promise<object>}
 */
async function refreshConnectionHealth() {
  let session = await loadSession();

  try {
    const status = await withTimeout(fetchStatus(), 4000, "Mac status");
    session = await clearSessionIfMacRevokedAll(status, session);
    let state = connectionStateFromStatus(status);

    if (!session) {
      state = "not_paired";
    } else if (state === "connected") {
      const stillPaired = await validatePairedSession(session);
      if (!stillPaired) {
        session = null;
        state = "not_paired";
      } else {
        state = "connected";
      }
    }

    await saveConnectionState(state, { status });
    await appendDiagnosticLog("info", "Health check completed", `state=${state}`);

    if (session && state === "connected") {
      void syncDynamicShieldIfRevisionChanged(status);
    }

    return { ok: true, state, status };
  } catch (error) {
    const message = error instanceof Error ? error.message : "Could not reach Mac app.";
    const state = session ? "disconnected" : "not_paired";
    await saveConnectionState(state, { message });
    await appendDiagnosticLog("error", "Health check failed", message);
    return { ok: false, state, message };
  }
}

/**
 * Pairs this extension with the Mac app using a one-time code.
 * @param {string} pairingCode
 * @param {{ clientName?: string, browserFamily?: string }} [pairingHints]
 */
async function pairExtension(pairingCode, pairingHints = {}) {
  const normalized = pairingCode.trim();
  if (!normalized) {
    throw new Error("Enter the pairing code from DynamicKey Settings.");
  }

  const browserFamily = pairingHints.browserFamily || (await detectBrowserFamily());
  const clientName = pairingHints.clientName || pairingClientNameForFamily(browserFamily);
  try {
    const pairResponse = await pairWithCode(normalized, { browserFamily, clientName });
    await saveSession({
      accessToken: pairResponse.accessToken,
      clientId: pairResponse.clientId,
      clientName: pairResponse.clientName ?? EXTENSION_CONFIG.clientName,
      pairedAt: new Date().toISOString(),
    });
    await appendDiagnosticLog("info", "Pairing succeeded", `${browserFamily} / ${clientName}`);
    return refreshConnectionHealth();
  } catch (error) {
    const message = error instanceof Error ? error.message : "Pairing failed.";
    await appendDiagnosticLog("error", "Pairing failed", message);
    throw error;
  }
}

/**
 * Removes local pairing and marks extension as not paired.
 */
async function disconnectExtension() {
  await clearSession();
  await appendDiagnosticLog("info", "Browser disconnected locally");
  return refreshConnectionHealth();
}

/**
 * Sends password + rhythm timing to the Mac app for allow/deny (W2.3).
 * @param {object} message
 */
async function verifyLoginFromPage(message) {
  const session = await loadSession();
  if (!session) {
    throw new Error("Extension is not paired with the Mac app.");
  }

  if (!message.origin || !message.password || !Array.isArray(message.keystrokes)) {
    throw new Error("Missing verify payload from page.");
  }

  return withAuthenticatedCall(() =>
    verifyLogin(session.accessToken, {
      requestId: crypto.randomUUID(),
      origin: message.origin,
      password: message.password,
      keystrokes: message.keystrokes,
      username: message.username ?? null,
      formIntent: message.formIntent ?? "login",
    })
  ).then(async (result) => {
    if (result?.granted) {
      await saveLastVerifiedAt();
    }
    return result;
  });
}

/**
 * Clears Mac app lockout for extension testing (W2).
 */
async function resetLockoutFromClient() {
  const session = await loadSession();
  if (!session) {
    throw new Error("Extension is not paired with the Mac app.");
  }

  return withAuthenticatedCall(() => resetLockout(session.accessToken));
}

/**
 * Requests fill approval and optional site credentials from the Mac app (W3.2).
 * @param {object} message
 */
async function fillApproveFromPage(message) {
  const session = await loadSession();
  if (!session) {
    throw new Error("Extension is not paired with the Mac app.");
  }

  if (!message.origin || !message.verificationRequestId) {
    throw new Error("Missing fill-approve payload from page.");
  }

  return withAuthenticatedCall(() =>
    requestFillApprove(session.accessToken, {
      requestId: crypto.randomUUID(),
      origin: message.origin,
      verificationRequestId: message.verificationRequestId,
      username: message.username ?? null,
      formIntent: message.formIntent ?? "login",
      rotateSitePassword: message.rotateSitePassword === true,
    })
  );
}

/**
 * Checks whether the Mac app already has a site credential for an origin.
 * @param {object} message
 */
async function checkCredentialFromPage(message) {
  const session = await loadSession();
  if (!session) {
    return { hasCredential: false, connected: false };
  }

  if (!message.origin) {
    throw new Error("Missing origin for credential check.");
  }

  const result = await withAuthenticatedCall(() =>
    checkCredentialForOrigin(session.accessToken, message.origin)
  );
  return { ...result, connected: true };
}

async function safeModeActivateFromClient() {
  const session = await loadSession();
  if (!session) {
    throw new Error("Extension is not paired with the Mac app.");
  }

  const result = await withAuthenticatedCall(() => activateSafeMode(session.accessToken));
  await refreshConnectionHealth();
  return result;
}

async function safeModeDeactivateFromClient() {
  const session = await loadSession();
  if (!session) {
    throw new Error("Extension is not paired with the Mac app.");
  }

  const result = await withAuthenticatedCall(() => deactivateSafeMode(session.accessToken));
  await refreshConnectionHealth();
  return result;
}

/**
 * Checks allowlist status for the current page origin (W4.2).
 * @param {object} message
 */
async function allowlistCheckFromPage(message) {
  const session = await loadSession();
  if (!session) {
    throw new Error("Extension is not paired with the Mac app.");
  }

  if (!message.origin) {
    throw new Error("Missing origin for allowlist check.");
  }

  return withAuthenticatedCall(() => checkAllowlist(session.accessToken, message.origin));
}

/**
 * Adds the current page origin to the Mac app allowlist (W4.2).
 * @param {object} message
 */
async function allowlistAddFromPage(message) {
  const session = await loadSession();
  if (!session) {
    throw new Error("Extension is not paired with the Mac app.");
  }

  if (!message.origin) {
    throw new Error("Missing origin for allowlist add.");
  }

  return withAuthenticatedCall(() => addToAllowlist(session.accessToken, message.origin));
}

/**
 * Marks the current page origin as not allowed on the Mac app allowlist.
 * @param {object} message
 */
async function allowlistIgnoreFromPage(message) {
  const session = await loadSession();
  if (!session) {
    throw new Error("Extension is not paired with the Mac app.");
  }

  if (!message.origin) {
    throw new Error("Missing origin for allowlist ignore.");
  }

  return withAuthenticatedCall(() => ignoreOnAllowlist(session.accessToken, message.origin));
}

/**
 * Syncs a trusted email sender domain to the Mac app DynamicShield list.
 * @param {object} message
 */
async function dynamicShieldTrustFromPage(message) {
  const session = await loadSession();
  if (!session) {
    throw new Error("Extension is not paired with the Mac app.");
  }

  if (!message.senderDomain) {
    throw new Error("Missing sender domain for DynamicShield trust.");
  }

  const normalized = String(message.senderDomain).trim().toLowerCase().replace(/^@/, "");
  const result = await withAuthenticatedCall(() =>
    trustDynamicShieldSender(session.accessToken, normalized)
  );

  try {
    const status = await withTimeout(fetchStatus(), 4000, "Mac status");
    await syncDynamicShieldIfRevisionChanged(status);
  } catch {
    await syncDynamicShieldTrustedFromMac();
  }

  return result;
}

/**
 * Logs a DynamicShield warning or dismiss event to Mac Security Activity.
 * @param {object} message
 */
async function dynamicShieldEventFromPage(message) {
  await refreshConnectionHealth();

  const session = await loadSession();
  if (!session) {
    return { logged: false };
  }

  if (!message.event) {
    throw new Error("Missing event for DynamicShield activity log.");
  }

  return withAuthenticatedCall(() =>
    logDynamicShieldEvent(session.accessToken, {
      event: message.event,
      senderDomain: message.senderDomain ?? null,
      flagSummary: message.flagSummary ?? null,
    })
  );
}

/**
 * Pushes a newly trusted sender domain to the Mac app (storage-driven sync).
 * @param {string} senderDomain
 */
async function pushTrustedDomainToMac(senderDomain) {
  const normalized = String(senderDomain ?? "").trim().toLowerCase().replace(/^@/, "");
  if (!normalized) {
    return;
  }

  const session = await loadSession();
  if (!session?.accessToken) {
    console.warn("[DynamicShield] Mac trust sync skipped — extension is not paired.");
    return;
  }

  try {
    await withAuthenticatedCall(() => trustDynamicShieldSender(session.accessToken, normalized));
    try {
      const status = await withTimeout(fetchStatus(), 4000, "Mac status");
      await syncDynamicShieldIfRevisionChanged(status);
    } catch {
      await syncDynamicShieldTrustedFromMac();
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : "Mac trust sync failed.";
    console.warn("[DynamicShield] Mac trust sync failed:", message);
  }
}

/**
 * Opens the DynamicKey Mac app (optionally with a specific intent).
 * @param {string} [intent]
 */
async function openMacAppFromClient(intent = "open") {
  const session = await loadSession();
  if (!session) {
    throw new Error("Pair the extension first to open DynamicKey.");
  }

  try {
    const result = await withAuthenticatedCall(() => openMacApp(session.accessToken, intent));
    await appendDiagnosticLog("info", "Opened DynamicKey Mac app", intent);
    return result;
  } catch (error) {
    const message = error instanceof Error ? error.message : "Could not open DynamicKey.";
    await appendDiagnosticLog("error", "Open Mac app failed", message);
    throw error;
  }
}

/**
 * Opens retrain typing profile in the Mac app.
 */
async function openRetrainOnMac() {
  return openMacAppFromClient("retrain");
}

/**
 * Routes runtime messages from the popup UI.
 * @param {object} message
 */
async function handleMessage(message) {
  switch (message?.type) {
    case "GET_SNAPSHOT":
      return loadConnectionSnapshot();
    case "GET_POPUP_DASHBOARD": {
      let snapshot = await loadConnectionSnapshot();

      if (snapshot.session) {
        const stillPaired = await validatePairedSession(snapshot.session);
        if (!stillPaired) {
          snapshot = await loadConnectionSnapshot();
        }
      }

      let macLastVerifiedAt = snapshot.lastVerifiedAt ?? snapshot.lastStatus?.lastVerifiedAt ?? null;
      let lastStatus = snapshot.lastStatus;

      try {
        const status = await withTimeout(fetchStatus(), 4000, "Mac status");
        if (status) {
          await clearSessionIfMacRevokedAll(status, snapshot.session);
          snapshot = await loadConnectionSnapshot();
          macLastVerifiedAt = status.lastVerifiedAt ?? macLastVerifiedAt;
          await saveConnectionState(snapshot.state ?? "connected", { status });
          lastStatus = status;
        }
      } catch {
        // Keep cached values when the Mac app is unreachable.
      }

      const refreshed = await loadConnectionSnapshot();
      return {
        ...refreshed,
        lastStatus: refreshed.lastStatus ?? lastStatus,
        macLastVerifiedAt,
      };
    }
    case "CHECK_STATUS":
      return refreshConnectionHealth();
    case "PAIR":
      return pairExtension(message.pairingCode, {
        browserFamily: message.browserFamily,
        clientName: message.clientName,
      });
    case "DISCONNECT":
      return disconnectExtension();
    case "OPEN_RETRAIN":
      return openRetrainOnMac();
    case "OPEN_MAC_APP":
      return openMacAppFromClient(message.intent ?? "open");
    case "GET_DIAGNOSTIC_REPORT":
      return buildDiagnosticReport();
    case "VERIFY_LOGIN":
      return verifyLoginFromPage(message);
    case "RESET_LOCKOUT":
      return resetLockoutFromClient();
    case "FILL_APPROVE":
      return fillApproveFromPage(message);
    case "ALLOWLIST_CHECK":
      return allowlistCheckFromPage(message);
    case "ALLOWLIST_ADD":
      return allowlistAddFromPage(message);
    case "ALLOWLIST_IGNORE":
      return allowlistIgnoreFromPage(message);
    case "CHECK_CREDENTIAL":
      return checkCredentialFromPage(message);
    case "SAFE_MODE_ACTIVATE":
      return safeModeActivateFromClient();
    case "SAFE_MODE_DEACTIVATE":
      return safeModeDeactivateFromClient();
    case "DYNAMIC_SHIELD_TRUST":
      return dynamicShieldTrustFromPage(message);
    case "DYNAMIC_SHIELD_EVENT":
      return dynamicShieldEventFromPage(message);
    case "SYNC_DYNAMIC_SHIELD_TRUSTED": {
      try {
        const status = await withTimeout(fetchStatus(), 4000, "Mac status");
        await syncDynamicShieldIfRevisionChanged(status);
        if (status?.dynamicShieldTrustedRevision != null) {
          await saveDynamicShieldRevision(Number(status.dynamicShieldTrustedRevision));
        }
      } catch {
        // Still attempt a direct list pull when status is unavailable.
      }
      await syncDynamicShieldTrustedFromMac();
      const domains = await loadMailShieldTrustedDomains();
      return { synced: true, trustedSenderDomains: domains };
    }
    default:
      throw new Error(`Unknown message type: ${message?.type}`);
  }
}

browserAPI.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message?.type === "SCAN_PROTON_IFRAME" && sender.tab?.id) {
    void scanProtonIframeViaScripting(sender.tab.id)
      .then((flags) => {
        sendResponse({ ok: true, result: { flags } });
      })
      .catch(() => {
        sendResponse({ ok: true, result: { flags: [] } });
      });
    return true;
  }

  if (message?.type === "PROTON_IFRAME_SCAN" && sender.tab?.id) {
    void browserAPI.tabs.sendMessage(sender.tab.id, {
      type: "PROTON_IFRAME_SCAN",
      flags: Array.isArray(message.flags) ? message.flags : [],
      identity: message.identity ?? null,
    }).catch(() => {
      // Ignore tabs that are not ready for content-script delivery yet.
    });
    sendResponse({ ok: true, result: { forwarded: true } });
    return true;
  }

  handleMessage(message)
    .then((result) => sendResponse({ ok: true, result }))
    .catch((error) => {
      const messageText = error instanceof Error ? error.message : "Unexpected error.";
      sendResponse({ ok: false, error: messageText });
    });
  return true;
});

browserAPI.storage.onChanged.addListener((changes, area) => {
  if (area !== "local" || !changes[MAIL_SHIELD_TRUSTED_DOMAINS_KEY] || applyingMacTrustedList) {
    return;
  }

  const previous = Array.isArray(changes[MAIL_SHIELD_TRUSTED_DOMAINS_KEY].oldValue)
    ? changes[MAIL_SHIELD_TRUSTED_DOMAINS_KEY].oldValue
    : [];
  const next = Array.isArray(changes[MAIL_SHIELD_TRUSTED_DOMAINS_KEY].newValue)
    ? changes[MAIL_SHIELD_TRUSTED_DOMAINS_KEY].newValue
    : [];

  for (const domain of next) {
    const normalized = String(domain ?? "").trim().toLowerCase();
    if (normalized && !previous.map((item) => String(item).toLowerCase()).includes(normalized)) {
      void pushTrustedDomainToMac(normalized);
    }
  }
});

browserAPI.runtime.onInstalled.addListener(async () => {
  await browserAPI.alarms.create(HEALTH_ALARM, {
    periodInMinutes: EXTENSION_CONFIG.healthCheckMinutes,
  });
  await appendDiagnosticLog("info", "Extension installed or updated");
  await refreshConnectionHealth();
});

browserAPI.alarms.onAlarm.addListener(async (alarm) => {
  if (alarm.name === HEALTH_ALARM) {
    await refreshConnectionHealth();
  }
});

browserAPI.runtime.onStartup.addListener(async () => {
  await appendDiagnosticLog("info", "Background worker started");
  await refreshConnectionHealth();
});

if (browserAPI.tabs?.onActivated) {
  browserAPI.tabs.onActivated.addListener(async ({ tabId }) => {
    const session = await loadSession();
    if (!session?.accessToken) {
      return;
    }

    try {
      const tab = await browserAPI.tabs.get(tabId);
      if (!isWebmailURL(tab?.url)) {
        return;
      }

      try {
        const status = await withTimeout(fetchStatus(), 4000, "Mac status");
        await syncDynamicShieldIfRevisionChanged(status);
        if (status?.dynamicShieldTrustedRevision != null) {
          await saveDynamicShieldRevision(Number(status.dynamicShieldTrustedRevision));
        }
      } catch {
        // Continue with a direct list pull when status is unavailable.
      }

      await syncDynamicShieldTrustedFromMac();
    } catch {
      // Ignore tab/status errors during background sync.
    }
  });
}

if (browserAPI.windows?.onFocusChanged) {
  browserAPI.windows.onFocusChanged.addListener(async (windowId) => {
    if (windowId === browserAPI.windows.WINDOW_ID_NONE) {
      return;
    }

    const session = await loadSession();
    if (!session?.accessToken) {
      return;
    }

    try {
      const tabs = await browserAPI.tabs.query({ windowId, active: true });
      const tab = tabs[0];
      if (!tab || !isWebmailURL(tab.url)) {
        return;
      }

      try {
        const status = await withTimeout(fetchStatus(), 4000, "Mac status");
        await syncDynamicShieldIfRevisionChanged(status);
        if (status?.dynamicShieldTrustedRevision != null) {
          await saveDynamicShieldRevision(Number(status.dynamicShieldTrustedRevision));
        }
      } catch {
        // Continue with a direct list pull when status is unavailable.
      }

      await syncDynamicShieldTrustedFromMac();
    } catch {
      // Ignore focus/sync errors during background sync.
    }
  });
}
