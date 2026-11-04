// popup.js
// Liquid Glass popup dashboard — pairing, connection health, Safe Mode sync, and Mail Shield.

import { browserAPI } from "../shared/browser.js";
import { detectBrowserFamily, pairingClientNameForFamily, isSafariWebExtension } from "../shared/config.js";
import { confirmRepairPairing } from "../shared/repair-pairing.js";
import { withTimeout } from "../shared/async.js";
import { loadMailShieldEnabled, saveMailShieldEnabled } from "../shared/storage.js";

const POPUP_MESSAGE_TIMEOUT_MS = isSafariWebExtension() ? 16000 : 8000;

/** @typedef {import('../shared/storage.js').ConnectionState} ConnectionState */

const CLIENT_ID_HIDE_MS = 30_000;

const statusDot = document.getElementById("statusDot");
const connectionLabel = document.getElementById("connectionLabel");
const connectionPill = document.getElementById("connectionPill");
const pillSeparator = document.getElementById("pillSeparator");
const pairedSection = document.getElementById("pairedSection");
const pairSection = document.getElementById("pairSection");
const blockedSection = document.getElementById("blockedSection");
const clientIdDisplay = document.getElementById("clientIdDisplay");
const clientIdToggle = document.getElementById("clientIdToggle");
const lastVerifiedAt = document.getElementById("lastVerifiedAt");
const pairingCodeInput = document.getElementById("pairingCodeInput");
const pairError = document.getElementById("pairError");
const blockedMessage = document.getElementById("blockedMessage");
const pairButton = document.getElementById("pairButton");
const refreshButton = document.getElementById("refreshButton");
const safeModeButton = document.getElementById("safeModeButton");
const safeModeBanner = document.getElementById("safeModeBanner");
const safeModeCountdown = document.getElementById("safeModeCountdown");
const endSafeModeButton = document.getElementById("endSafeModeButton");
const blockedRefreshButton = document.getElementById("blockedRefreshButton");
const rePairButton = document.getElementById("rePairButton");
const openOptionsButton = document.getElementById("openOptionsButton");
const pairHint = document.getElementById("pairHint");
const mailShieldToggle = document.getElementById("mailShieldToggle");
const extensionVersion = document.getElementById("extensionVersion");
const pairedActionButtons = document.querySelectorAll(".paired-only");

let fullClientId = "";
let clientIdHideTimer = null;
let safeModeCountdownTimer = null;
let dashboardLoadTimer = null;
let dashboardLoadInFlight = null;
let pairingInProgress = false;
let lastRenderedSnapshotKey = "";

connectionPill.hidden = false;

/**
 * Shows the bundled extension version in the popup header.
 */
function renderExtensionVersion() {
  if (!extensionVersion) {
    return;
  }

  const version = browserAPI.runtime.getManifest?.()?.version ?? "dev";
  extensionVersion.textContent = `v${version}`;
}

renderExtensionVersion();

/**
 * @param {string | null | undefined} iso
 * @returns {string}
 */
function formatVerifiedAt(iso) {
  if (!iso) {
    return "—";
  }

  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) {
    return "—";
  }

  return date.toLocaleString();
}

/**
 * Picks the best available last-verified timestamp from the dashboard snapshot.
 * @param {object} snapshot
 * @returns {string | null}
 */
function resolveLastVerifiedAt(snapshot) {
  return snapshot.lastVerifiedAt ?? snapshot.macLastVerifiedAt ?? snapshot.lastCheckedAt ?? null;
}

/**
 * Reads Safe Mode fields from the cached Mac status snapshot.
 * @param {object} snapshot
 * @returns {{ active: boolean, remainingLabel: string | null, expiresAt: string | null }}
 */
function resolveSafeModeFromSnapshot(snapshot) {
  const status = snapshot.lastStatus ?? {};
  return {
    active: Boolean(status.safeModeActive),
    remainingLabel: status.safeModeRemainingLabel ?? null,
    expiresAt: status.safeModeExpiresAt ?? null,
  };
}

/**
 * Formats H:MM:SS countdown for the Safe Mode banner.
 * @param {string | null} remainingLabel
 * @param {string | null} expiresAtIso
 * @returns {string}
 */
function formatSafeModeCountdown(remainingLabel, expiresAtIso) {
  if (remainingLabel) {
    return remainingLabel;
  }

  if (!expiresAtIso) {
    return "24:00:00";
  }

  const ms = Math.max(0, new Date(expiresAtIso).getTime() - Date.now());
  const total = Math.floor(ms / 1000);
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const seconds = total % 60;
  return `${hours}:${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
}

function stopSafeModeCountdownTimer() {
  if (safeModeCountdownTimer) {
    clearInterval(safeModeCountdownTimer);
    safeModeCountdownTimer = null;
  }
}

/**
 * Ticks the Safe Mode banner countdown every second until expiry.
 * @param {string | null} expiresAtIso
 */
function startSafeModeCountdownTimer(expiresAtIso) {
  stopSafeModeCountdownTimer();
  if (!expiresAtIso) {
    return;
  }

  safeModeCountdownTimer = setInterval(() => {
    const ms = Math.max(0, new Date(expiresAtIso).getTime() - Date.now());
    if (ms <= 0) {
      stopSafeModeCountdownTimer();
      checkConnection();
      return;
    }

    safeModeCountdown.textContent = formatSafeModeCountdown(null, expiresAtIso);
  }, 1000);
}

/**
 * Updates Safe Mode banner, toolbar shield button, and connection pill.
 * @param {object} snapshot
 * @param {ConnectionState} state
 * @param {boolean} hasSession
 */
function renderSafeModeUI(snapshot, state, hasSession) {
  const safeMode = resolveSafeModeFromSnapshot(snapshot);
  const showBanner = hasSession && safeMode.active;

  if (safeModeBanner) {
    safeModeBanner.hidden = !showBanner;
  }

  if (showBanner) {
    safeModeCountdown.textContent = formatSafeModeCountdown(
      safeMode.remainingLabel,
      safeMode.expiresAt
    );
    startSafeModeCountdownTimer(safeMode.expiresAt);
    statusDot.className = "status-dot safe-mode";
    connectionLabel.textContent = `Safe Mode — ${formatSafeModeCountdown(safeMode.remainingLabel, safeMode.expiresAt)}`;
  } else {
    stopSafeModeCountdownTimer();
  }

  if (!safeModeButton) {
    return;
  }

  const wrap = safeModeButton.closest(".icon-btn-wrap");
  if (wrap) {
    wrap.dataset.tooltip = safeMode.active ? "Turn Off Safe Mode" : "Safe Mode (24h)";
  }

  safeModeButton.classList.toggle("safe-mode-active", safeMode.active);
  safeModeButton.setAttribute(
    "aria-label",
    safeMode.active ? "Turn Off Safe Mode" : "Activate Safe Mode"
  );
}

/**
 * Shows or hides paired-only toolbar buttons and inline client ID controls.
 * @param {boolean} isPaired
 */
function setPairedExtrasVisible(isPaired) {
  pillSeparator.hidden = !isPaired;
  clientIdToggle.hidden = !isPaired;
  pairedActionButtons.forEach((button) => {
    button.hidden = !isPaired;
  });
}

/**
 * Syncs Mail Shield toggle visuals in the connection pill.
 * @param {boolean} enabled
 */
function renderMailShieldToggle(enabled) {
  mailShieldToggle.classList.toggle("active", enabled);
  mailShieldToggle.setAttribute("aria-pressed", String(enabled));
  mailShieldToggle.title = enabled
    ? "Mail Shield is ON — tap to turn off"
    : "Mail Shield is OFF — tap to turn on";
}

/**
 * Loads Mail Shield preference and updates the pill shield button.
 */
async function syncMailShieldUI() {
  const enabled = await loadMailShieldEnabled();
  renderMailShieldToggle(enabled);
}

/**
 * Sends a message to the background service worker.
 * @template T
 * @param {object} message
 * @returns {Promise<T>}
 */
function sendMessage(message, timeoutMs = POPUP_MESSAGE_TIMEOUT_MS) {
  return withTimeout(
    new Promise((resolve, reject) => {
      browserAPI.runtime.sendMessage(message, (response) => {
        if (browserAPI.runtime.lastError) {
          reject(new Error(browserAPI.runtime.lastError.message));
          return;
        }
        if (!response?.ok) {
          reject(new Error(response?.error ?? "Request failed."));
          return;
        }
        resolve(response.result);
      });
    }),
    timeoutMs,
    "Extension worker"
  );
}

/**
 * @param {string} clientIdValue
 * @returns {string}
 */
function maskClientId(clientIdValue) {
  const length = Math.max(8, Math.min(12, clientIdValue.length));
  return "•".repeat(length);
}

/**
 * Hides the paired client ID behind dots again.
 */
function hideClientId() {
  if (!fullClientId) {
    clientIdDisplay.textContent = "••••••••";
    return;
  }

  clientIdDisplay.textContent = maskClientId(fullClientId);
  clientIdToggle.classList.remove("revealed");
  clientIdToggle.setAttribute("aria-label", "Show paired client ID");
}

/**
 * Reveals the paired client ID briefly, then auto-hides.
 */
function revealClientId() {
  if (!fullClientId) {
    return;
  }

  clientIdDisplay.textContent = fullClientId;
  clientIdToggle.classList.add("revealed");
  clientIdToggle.setAttribute("aria-label", "Hide paired client ID");

  if (clientIdHideTimer) {
    clearTimeout(clientIdHideTimer);
  }

  clientIdHideTimer = setTimeout(() => {
    hideClientId();
    clientIdHideTimer = null;
  }, CLIENT_ID_HIDE_MS);
}

/**
 * @param {ConnectionState} state
 * @param {boolean} hasSession
 * @returns {string}
 */
function connectionLabelFor(state, hasSession) {
  if (hasSession && state === "connected") {
    return "Paired";
  }

  switch (state) {
    case "connected":
      return "Connected to Mac";
    case "not_paired":
      return "Not paired";
    case "no_profile":
      return "Profile not enrolled";
    case "mac_app_stopped":
      return "Mac app not running";
    case "disconnected":
    default:
      return "Disconnected";
  }
}

/**
 * Stable key so we skip full UI resets when the dashboard state did not change.
 * @param {object} snapshot
 * @returns {string}
 */
function snapshotRenderKey(snapshot) {
  return JSON.stringify({
    state: snapshot.state ?? "not_paired",
    sessionId: snapshot.session?.clientId ?? null,
    lastError: snapshot.lastError ?? null,
    safeModeActive: Boolean(snapshot.lastStatus?.safeModeActive),
    verifiedAt: resolveLastVerifiedAt(snapshot),
  });
}

/**
 * Updates visible UI from the dashboard snapshot.
 * @param {object} snapshot
 * @param {{ force?: boolean }} [options]
 */
function renderSnapshot(snapshot, options = {}) {
  const renderKey = snapshotRenderKey(snapshot);
  const state = snapshot.state ?? "not_paired";
  const hasSession = Boolean(snapshot.session);
  const isPaired = Boolean(snapshot.session);

  if (!options.force && renderKey === lastRenderedSnapshotKey) {
    if (snapshot.session && state === "connected") {
      renderSafeModeUI(snapshot, state, hasSession);
    }
    return;
  }

  lastRenderedSnapshotKey = renderKey;

  statusDot.className = `status-dot ${isPaired ? "connected" : state}`;
  connectionLabel.textContent = connectionLabelFor(state, hasSession);

  pairedSection.hidden = true;
  pairSection.hidden = true;
  blockedSection.hidden = true;
  pairError.hidden = true;
  if (pairHint) {
    pairHint.hidden = true;
  }
  connectionPill.hidden = true;
  setPairedExtrasVisible(false);
  if (safeModeBanner) {
    safeModeBanner.hidden = true;
  }
  stopSafeModeCountdownTimer();

  if (state === "mac_app_stopped" || state === "no_profile") {
    blockedSection.hidden = false;
    connectionPill.hidden = false;
    hideClientId();
    lastVerifiedAt.textContent = "—";
    blockedMessage.textContent =
      state === "no_profile"
        ? "Enroll a profile in the DynamicKey Mac app before pairing the extension."
        : "Start the DynamicKey Mac app on this computer, then tap Retry.";
    return;
  }

  if (snapshot.session && state === "connected") {
    pairedSection.hidden = false;
    connectionPill.hidden = false;
    setPairedExtrasVisible(true);
    renderSafeModeUI(snapshot, state, hasSession);
    fullClientId = snapshot.session.clientId;
    hideClientId();

    if (!resolveSafeModeFromSnapshot(snapshot).active) {
      statusDot.className = `status-dot ${isPaired ? "connected" : state}`;
      connectionLabel.textContent = connectionLabelFor(state, hasSession);
    }

    const verifiedIso = resolveLastVerifiedAt(snapshot);
    lastVerifiedAt.textContent = formatVerifiedAt(verifiedIso);
    if (verifiedIso) {
      lastVerifiedAt.setAttribute("datetime", verifiedIso);
    } else {
      lastVerifiedAt.removeAttribute("datetime");
    }

    return;
  }

  if (snapshot.session && state === "disconnected") {
    pairedSection.hidden = false;
    connectionPill.hidden = false;
    setPairedExtrasVisible(true);
    fullClientId = snapshot.session.clientId;
    hideClientId();
    statusDot.className = "status-dot disconnected";
    connectionLabel.textContent = "Mac app unreachable";
    lastVerifiedAt.textContent = formatVerifiedAt(resolveLastVerifiedAt(snapshot));
    return;
  }

  pairSection.hidden = false;
  connectionPill.hidden = false;
  hideClientId();
  lastVerifiedAt.textContent = "—";
  statusDot.className = "status-dot not_paired";
  connectionLabel.textContent = snapshot.lastError ? "Repair pairing" : connectionLabelFor(state, hasSession);

  if (snapshot.lastError) {
    pairError.hidden = false;
    pairError.textContent = snapshot.lastError;
  }
}

/**
 * Loads dashboard data from the background worker.
 * @param {{ force?: boolean }} [options]
 */
async function loadDashboard(options = {}) {
  if (dashboardLoadInFlight) {
    return dashboardLoadInFlight;
  }

  dashboardLoadInFlight = (async () => {
    try {
      try {
        await sendMessage({ type: "CHECK_STATUS" });
      } catch {
        // Fall back to cached snapshot when the Mac app is unreachable.
      }

      const snapshot = await sendMessage({ type: "GET_POPUP_DASHBOARD" });
      renderSnapshot(snapshot, options);
    } catch (error) {
      lastRenderedSnapshotKey = "";
      connectionPill.hidden = false;
      statusDot.className = "status-dot disconnected";
      connectionLabel.textContent = "Disconnected";
      blockedSection.hidden = false;
      blockedMessage.textContent =
        error instanceof Error
          ? error.message
          : "Could not reach the extension background worker.";
    } finally {
      dashboardLoadInFlight = null;
    }
  })();

  return dashboardLoadInFlight;
}

/**
 * Debounces rapid storage events so pairing does not flicker the popup.
 */
function scheduleDashboardReload(options = {}) {
  if (pairingInProgress) {
    return;
  }

  if (dashboardLoadTimer) {
    clearTimeout(dashboardLoadTimer);
  }

  dashboardLoadTimer = setTimeout(() => {
    dashboardLoadTimer = null;
    void loadDashboard(options);
  }, 180);
}

/**
 * Runs a health check against the Mac app API.
 */
async function checkConnection() {
  refreshButton.disabled = true;
  blockedRefreshButton.disabled = true;
  renderExtensionVersion();
  try {
    await loadDashboard({ force: true });
  } catch (error) {
    connectionPill.hidden = false;
    statusDot.className = "status-dot disconnected";
    connectionLabel.textContent = "Disconnected";
    blockedSection.hidden = false;
    blockedMessage.textContent =
      error instanceof Error
        ? error.message
        : "Could not reach the extension background worker.";
  } finally {
    refreshButton.disabled = false;
    blockedRefreshButton.disabled = false;
  }
}

/**
 * Submits the pairing code to the Mac app.
 */
async function submitPairing() {
  pairError.hidden = true;
  if (pairHint) {
    pairHint.hidden = true;
  }
  pairButton.disabled = true;
  pairingInProgress = true;
  try {
    const browserFamily = await detectBrowserFamily();
    await sendMessage({
      type: "PAIR",
      pairingCode: pairingCodeInput.value,
      browserFamily,
      clientName: pairingClientNameForFamily(browserFamily),
    });
    pairingCodeInput.value = "";
    lastRenderedSnapshotKey = "";
    await loadDashboard({ force: true });
  } catch (error) {
    pairError.hidden = false;
    pairError.textContent = error instanceof Error ? error.message : "Pairing failed.";
  } finally {
    pairingInProgress = false;
    pairButton.disabled = false;
  }
}

/**
 * Disconnects this browser only, then shows the pairing form for a fresh code.
 */
async function repairBrowserPairing() {
  const { confirmed, browserLabel } = await confirmRepairPairing();
  if (!confirmed) {
    return;
  }

  rePairButton.disabled = true;
  try {
    await sendMessage({ type: "DISCONNECT" });
    pairingCodeInput.value = "";
    lastRenderedSnapshotKey = "";
    await loadDashboard({ force: true });
    pairSection.hidden = false;
    if (pairHint) {
      pairHint.hidden = false;
      pairHint.textContent = `Enter a new pairing code from the Mac app to reconnect ${browserLabel}.`;
    }
    pairingCodeInput.focus();
  } catch (error) {
    connectionLabel.textContent =
      error instanceof Error ? error.message : "Could not disconnect this browser.";
  } finally {
    rePairButton.disabled = false;
  }
}

/**
 * Activates or ends Safe Mode through the Mac app API (syncs Mac + extension).
 */
async function toggleSafeMode() {
  safeModeButton.disabled = true;
  endSafeModeButton.disabled = true;

  try {
    await sendMessage({ type: "CHECK_STATUS" });
    const snapshot = await sendMessage({ type: "GET_POPUP_DASHBOARD" });
    const safeMode = resolveSafeModeFromSnapshot(snapshot);

    await sendMessage({
      type: safeMode.active ? "SAFE_MODE_DEACTIVATE" : "SAFE_MODE_ACTIVATE",
    });
    await sendMessage({ type: "CHECK_STATUS" });
    await loadDashboard();
  } catch (error) {
    connectionLabel.textContent =
      error instanceof Error ? error.message : "Could not update Safe Mode.";
  } finally {
    safeModeButton.disabled = false;
    endSafeModeButton.disabled = false;
  }
}

clientIdToggle.addEventListener("click", () => {
  if (clientIdToggle.classList.contains("revealed")) {
    if (clientIdHideTimer) {
      clearTimeout(clientIdHideTimer);
      clientIdHideTimer = null;
    }
    hideClientId();
    return;
  }

  revealClientId();
});

pairButton.addEventListener("click", submitPairing);
refreshButton.addEventListener("click", checkConnection);
blockedRefreshButton.addEventListener("click", checkConnection);
rePairButton.addEventListener("click", repairBrowserPairing);
safeModeButton?.addEventListener("click", toggleSafeMode);
endSafeModeButton?.addEventListener("click", toggleSafeMode);

pairingCodeInput.addEventListener("keydown", (event) => {
  if (event.key === "Enter") {
    submitPairing();
  }
});

browserAPI.storage.onChanged.addListener((changes, area) => {
  if (area !== "local") {
    return;
  }

  if (changes["keystrokeauth.mailShieldEnabled"]) {
    renderMailShieldToggle(Boolean(changes["keystrokeauth.mailShieldEnabled"].newValue));
  }

  const dashboardKeys = [
    "keystrokeauth.connectionState",
    "keystrokeauth.session",
    "keystrokeauth.lastVerifiedAt",
    "keystrokeauth.lastStatus",
  ];
  if (dashboardKeys.some((key) => key in changes)) {
    scheduleDashboardReload();
  }
});

// Light poll while paired — updates Safe Mode without resetting the whole popup layout.
setInterval(() => {
  if (!pairedSection || pairedSection.hidden || pairingInProgress) {
    return;
  }

  void sendMessage({ type: "GET_POPUP_DASHBOARD" }, 4000)
    .then((snapshot) => {
      renderSnapshot(snapshot);
    })
    .catch(() => {
      // Ignore transient worker wake failures.
    });
}, 4000);

mailShieldToggle.addEventListener("click", async () => {
  const nextEnabled = !mailShieldToggle.classList.contains("active");
  await saveMailShieldEnabled(nextEnabled);
  renderMailShieldToggle(nextEnabled);
});

openOptionsButton?.addEventListener("click", () => {
  browserAPI.runtime.openOptionsPage();
});

syncMailShieldUI();
checkConnection();
