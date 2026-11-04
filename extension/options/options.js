// options.js
// Extension settings page: pairing, Mac app guidance, and developer toggles.

import { browserAPI } from "../shared/browser.js";
import { detectBrowserFamily, pairingClientNameForFamily } from "../shared/config.js";
import { confirmRepairPairing } from "../shared/repair-pairing.js";
import { loadDebugMode, saveDebugMode } from "../shared/storage.js";

const statusDot = document.getElementById("statusDot");
const statusText = document.getElementById("statusText");
const versionLabel = document.getElementById("versionLabel");
const pairedSection = document.getElementById("pairedSection");
const pairSection = document.getElementById("pairSection");
const blockedSection = document.getElementById("blockedSection");
const browserLabel = document.getElementById("browserLabel");
const clientId = document.getElementById("clientId");
const lastChecked = document.getElementById("lastChecked");
const pairingCodeInput = document.getElementById("pairingCodeInput");
const pairError = document.getElementById("pairError");
const pairHint = document.getElementById("pairHint");
const blockedMessage = document.getElementById("blockedMessage");
const pairButton = document.getElementById("pairButton");
const refreshButton = document.getElementById("refreshButton");
const rePairButton = document.getElementById("rePairButton");
const blockedRefreshButton = document.getElementById("blockedRefreshButton");
const openMacAppButton = document.getElementById("openMacAppButton");
const developerToggle = document.getElementById("developerToggle");
const developerBody = document.getElementById("developerBody");
const debugModeToggle = document.getElementById("debugModeToggle");
const exportDiagnosticButton = document.getElementById("exportDiagnosticButton");

let currentBrowserLabel = "Browser Extension";

/**
 * Sends a message to the background service worker.
 * @template T
 * @param {object} message
 * @returns {Promise<T>}
 */
function sendMessage(message) {
  return new Promise((resolve, reject) => {
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
  });
}

/**
 * @param {string} state
 * @returns {string}
 */
function statusLabel(state) {
  switch (state) {
    case "connected":
      return "Connected to DynamicKey on this Mac.";
    case "not_paired":
      return "Not paired — enter a pairing code below.";
    case "no_profile":
      return "Enroll a profile in the Mac app first.";
    case "mac_app_stopped":
      return "Open DynamicKey on this Mac, then retry.";
    case "disconnected":
    default:
      return "Mac app unreachable — check connection or re-pair.";
  }
}

/**
 * Updates the visible browser label in the paired summary card.
 * @param {object} snapshot
 */
async function renderBrowserLabel(snapshot) {
  const family = await detectBrowserFamily();
  currentBrowserLabel = snapshot.session?.clientName ?? pairingClientNameForFamily(family);
  browserLabel.textContent = currentBrowserLabel;
}

/**
 * @param {object} snapshot
 */
function renderSnapshot(snapshot) {
  const state = snapshot.state ?? "not_paired";
  statusDot.className = `status-dot ${snapshot.session && state === "connected" ? "connected" : state}`;
  statusText.textContent = statusLabel(state);

  pairedSection.hidden = true;
  pairSection.hidden = true;
  blockedSection.hidden = true;
  pairError.hidden = true;
  if (pairHint) {
    pairHint.hidden = true;
  }

  if (state === "mac_app_stopped" || state === "no_profile") {
    blockedSection.hidden = false;
    blockedMessage.textContent =
      state === "no_profile"
        ? "Enroll a profile in the DynamicKey Mac app before pairing the extension."
        : "Start the DynamicKey Mac app on this computer, then tap Retry.";
    return;
  }

  if (snapshot.session && (state === "connected" || state === "disconnected")) {
    pairedSection.hidden = false;
    void renderBrowserLabel(snapshot);
    clientId.textContent = `Client ID ${snapshot.session.clientId}`;
    lastChecked.textContent = snapshot.lastCheckedAt
      ? `Last checked ${new Date(snapshot.lastCheckedAt).toLocaleString()}`
      : "Last checked —";

    if (state === "disconnected") {
      statusDot.className = "status-dot disconnected";
      statusText.textContent = "Mac app unreachable — try Check Connection or Re-pair.";
    }
    return;
  }

  pairSection.hidden = false;
  void renderBrowserLabel(snapshot);
  if (snapshot.lastError) {
    pairError.hidden = false;
    pairError.textContent = snapshot.lastError;
  }
}

async function loadSnapshot() {
  try {
    await sendMessage({ type: "CHECK_STATUS" });
  } catch {
    // Use cached snapshot when the Mac app is unreachable.
  }

  const snapshot = await sendMessage({ type: "GET_POPUP_DASHBOARD" });
  renderSnapshot(snapshot);
}

async function checkConnection() {
  refreshButton.disabled = true;
  blockedRefreshButton.disabled = true;
  try {
    await loadSnapshot();
  } finally {
    refreshButton.disabled = false;
    blockedRefreshButton.disabled = false;
  }
}

async function submitPairing() {
  pairError.hidden = true;
  if (pairHint) {
    pairHint.hidden = true;
  }
  pairButton.disabled = true;
  try {
    const browserFamily = await detectBrowserFamily();
    await sendMessage({
      type: "PAIR",
      pairingCode: pairingCodeInput.value,
      browserFamily,
      clientName: pairingClientNameForFamily(browserFamily),
    });
    pairingCodeInput.value = "";
    await loadSnapshot();
  } catch (error) {
    pairError.hidden = false;
    pairError.textContent = error instanceof Error ? error.message : "Pairing failed.";
  } finally {
    pairButton.disabled = false;
  }
}

/**
 * Disconnects this browser only, then opens the pairing form again.
 */
async function repairBrowserPairing() {
  const { confirmed, browserLabel: label } = await confirmRepairPairing();
  if (!confirmed) {
    return;
  }

  rePairButton.disabled = true;
  try {
    await sendMessage({ type: "DISCONNECT" });
    pairingCodeInput.value = "";
    await loadSnapshot();
    pairSection.hidden = false;
    if (pairHint) {
      pairHint.hidden = false;
      pairHint.textContent = `Enter a new pairing code from the Mac app to reconnect ${label}.`;
    }
    pairingCodeInput.focus();
  } catch (error) {
    statusText.textContent =
      error instanceof Error ? error.message : "Could not disconnect this browser.";
  } finally {
    rePairButton.disabled = false;
  }
}

async function openDynamicKeyApp() {
  openMacAppButton.disabled = true;
  try {
    await sendMessage({ type: "OPEN_MAC_APP", intent: "open" });
    statusText.textContent = "Opened DynamicKey on this Mac.";
  } catch (error) {
    statusText.textContent =
      error instanceof Error ? error.message : "Could not open DynamicKey.";
  } finally {
    openMacAppButton.disabled = false;
  }
}

/**
 * Expands or collapses the developer options card.
 */
function toggleDeveloperSection() {
  const isExpanded = developerToggle.getAttribute("aria-expanded") === "true";
  const nextExpanded = !isExpanded;
  developerToggle.setAttribute("aria-expanded", nextExpanded ? "true" : "false");
  developerToggle.closest(".collapsible-card")?.setAttribute(
    "data-collapsed",
    nextExpanded ? "false" : "true"
  );
  developerBody.hidden = !nextExpanded;
}

/**
 * Saves a plain-text diagnostic report for support troubleshooting.
 */
async function exportDiagnosticReport() {
  exportDiagnosticButton.disabled = true;
  try {
    const report = await sendMessage({ type: "GET_DIAGNOSTIC_REPORT" });
    const blob = new Blob([report.text], { type: "text/plain;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = report.filename ?? "dynamickey-diagnostic.txt";
    document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
    URL.revokeObjectURL(url);
    statusText.textContent = "Diagnostic report saved — attach it when contacting support.";
  } catch (error) {
    statusText.textContent =
      error instanceof Error ? error.message : "Could not export diagnostic report.";
  } finally {
    exportDiagnosticButton.disabled = false;
  }
}

async function loadDebugToggle() {
  debugModeToggle.checked = await loadDebugMode();
}

pairButton.addEventListener("click", submitPairing);
refreshButton.addEventListener("click", checkConnection);
rePairButton.addEventListener("click", repairBrowserPairing);
openMacAppButton.addEventListener("click", openDynamicKeyApp);
developerToggle.addEventListener("click", toggleDeveloperSection);
blockedRefreshButton.addEventListener("click", checkConnection);
pairingCodeInput.addEventListener("keydown", (event) => {
  if (event.key === "Enter") {
    submitPairing();
  }
});
debugModeToggle.addEventListener("change", async () => {
  await saveDebugMode(debugModeToggle.checked);
});
exportDiagnosticButton.addEventListener("click", exportDiagnosticReport);

let snapshotReloadTimer = null;
browserAPI.storage.onChanged.addListener(() => {
  if (snapshotReloadTimer) {
    clearTimeout(snapshotReloadTimer);
  }
  snapshotReloadTimer = setTimeout(() => {
    snapshotReloadTimer = null;
    loadSnapshot();
  }, 400);
});

versionLabel.textContent = `Extension v${browserAPI.runtime.getManifest().version}`;
loadDebugToggle();
loadSnapshot();
