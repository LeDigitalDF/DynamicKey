// api.js
// HTTP client for the KeyStrokeAuth Mac app localhost API (W1).
//
// Flow: fetch status (no auth) → pair with code → authenticated calls use bearer token.

import { EXTENSION_CONFIG, detectBrowserFamily, pairingClientNameForFamily } from "./config.js";

/**
 * @param {string} path
 * @returns {string}
 */
function urlFor(path) {
  return `${EXTENSION_CONFIG.baseURL}${path}`;
}

/**
 * @param {Response} response
 * @returns {Promise<any>}
 */
async function parseJSON(response) {
  const text = await response.text();
  if (!text) {
    return null;
  }
  try {
    return JSON.parse(text);
  } catch {
    throw new Error("Mac app returned invalid JSON.");
  }
}

/**
 * @param {Response} response
 * @param {any} body
 */
function buildAPIError(response, body) {
  const message =
    body?.message ||
    body?.error ||
    `Mac app request failed (${response.status}).`;
  const error = new Error(message);
  error.name = "KeyStrokeAuthAPIError";
  error.status = response.status;
  return error;
}

/**
 * Fetches Mac app health without authentication.
 * @returns {Promise<object>}
 */
export async function fetchStatus() {
  const response = await fetch(urlFor(EXTENSION_CONFIG.routes.status), {
    method: "GET",
    headers: { Accept: "application/json" },
  });

  const body = await parseJSON(response);
  if (!response.ok) {
    throw buildAPIError(response, body);
  }
  return body;
}

/**
 * Exchanges a pairing code from Mac app Settings for an access token.
 * @param {string} pairingCode
 * @param {{ clientName?: string, browserFamily?: string }} [pairingHints]
 * @returns {Promise<object>}
 */
export async function pairWithCode(pairingCode, pairingHints = {}) {
  const browserFamily = pairingHints.browserFamily || (await detectBrowserFamily());
  const clientName = pairingHints.clientName || pairingClientNameForFamily(browserFamily);

  const response = await fetch(urlFor(EXTENSION_CONFIG.routes.pair), {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      protocolVersion: EXTENSION_CONFIG.protocolVersion,
      pairingCode: pairingCode.trim().toUpperCase(),
      clientName,
      browserFamily,
    }),
  });

  const body = await parseJSON(response);
  if (!response.ok) {
    throw buildAPIError(response, body);
  }
  return body;
}

/**
 * Checks whether the Mac app has a saved credential for an origin (popup dashboard).
 * @param {string} accessToken
 * @param {string} origin
 * @returns {Promise<object>}
 */
export async function checkCredentialForOrigin(accessToken, origin) {
  const response = await fetch(urlFor(EXTENSION_CONFIG.routes.credentialsCheck), {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({
      protocolVersion: EXTENSION_CONFIG.protocolVersion,
      origin,
    }),
  });

  const body = await parseJSON(response);
  if (!response.ok) {
    throw buildAPIError(response, body);
  }
  return body;
}

/**
 * Brings the DynamicKey Mac app to the front.
 * @param {string} accessToken
 * @param {"open" | "retrain"} intent
 * @returns {Promise<object>}
 */
export async function openMacApp(accessToken, intent = "open") {
  const response = await fetch(urlFor(EXTENSION_CONFIG.routes.openApp), {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({
      protocolVersion: EXTENSION_CONFIG.protocolVersion,
      intent,
    }),
  });

  const body = await parseJSON(response);
  if (!response.ok) {
    throw buildAPIError(response, body);
  }
  return body;
}

/**
 * Brings the Mac app forward and opens the retrain typing profile flow.
 * @param {string} accessToken
 * @returns {Promise<object>}
 */
export async function openMacAppForRetrain(accessToken) {
  return openMacApp(accessToken, "retrain");
}

/**
 * Activates Safe Mode on the Mac app (24 hours — syncs Mac + extension).
 * @param {string} accessToken
 * @returns {Promise<object>}
 */
export async function activateSafeMode(accessToken) {
  const response = await fetch(urlFor(EXTENSION_CONFIG.routes.safeModeActivate), {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({ protocolVersion: EXTENSION_CONFIG.protocolVersion }),
  });

  const body = await parseJSON(response);
  if (!response.ok) {
    throw buildAPIError(response, body);
  }
  return body;
}

/**
 * Ends Safe Mode on the Mac app (syncs Mac + extension).
 * @param {string} accessToken
 * @returns {Promise<object>}
 */
export async function deactivateSafeMode(accessToken) {
  const response = await fetch(urlFor(EXTENSION_CONFIG.routes.safeModeDeactivate), {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({ protocolVersion: EXTENSION_CONFIG.protocolVersion }),
  });

  const body = await parseJSON(response);
  if (!response.ok) {
    throw buildAPIError(response, body);
  }
  return body;
}

/**
 * Derives a user-facing connection state from Mac app status payload.
 * @param {object} status
 * @returns {'connected' | 'mac_app_stopped' | 'no_profile' | 'disconnected'}
 */
export function connectionStateFromStatus(status) {
  if (!status || status.serviceState !== "running") {
    return "mac_app_stopped";
  }
  if (!status.hasProfile) {
    return "no_profile";
  }
  return "connected";
}

/**
 * Verifies password and typing rhythm with the Mac app (W2.3 / W3.5).
 * @param {string} accessToken
 * @param {{ requestId: string, origin: string, password: string, keystrokes: object[], username?: string, formIntent?: string }} payload
 * @returns {Promise<object>}
 */
export async function verifyLogin(accessToken, payload) {
  const response = await fetch(urlFor(EXTENSION_CONFIG.routes.verify), {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({
      protocolVersion: EXTENSION_CONFIG.protocolVersion,
      requestId: payload.requestId,
      origin: payload.origin,
      password: payload.password,
      keystrokes: payload.keystrokes,
      username: payload.username ?? null,
      formIntent: payload.formIntent ?? "login",
    }),
  });

  const body = await parseJSON(response);
  if (!response.ok) {
    throw buildAPIError(response, body);
  }
  return body;
}

/**
 * Clears Mac app sign-in lockout during extension testing (W2).
 * @param {string} accessToken
 * @returns {Promise<object>}
 */
export async function resetLockout(accessToken) {
  const response = await fetch(urlFor(EXTENSION_CONFIG.routes.resetLockout), {
    method: "POST",
    headers: {
      Accept: "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
  });

  const body = await parseJSON(response);
  if (!response.ok) {
    throw buildAPIError(response, body);
  }
  return body;
}

/**
 * Requests autofill approval and site credentials from the Mac app (W3.2 / W3.5).
 * @param {string} accessToken
 * @param {{ requestId: string, origin: string, verificationRequestId: string, username?: string, formIntent?: string, rotateSitePassword?: boolean }} payload
 * @returns {Promise<object>}
 */
export async function requestFillApprove(accessToken, payload) {
  const response = await fetch(urlFor(EXTENSION_CONFIG.routes.fillApprove), {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({
      protocolVersion: EXTENSION_CONFIG.protocolVersion,
      requestId: payload.requestId,
      origin: payload.origin,
      verificationRequestId: payload.verificationRequestId,
      username: payload.username ?? null,
      formIntent: payload.formIntent ?? "login",
      rotateSitePassword: payload.rotateSitePassword === true,
    }),
  });

  const body = await parseJSON(response);
  if (!response.ok) {
    throw buildAPIError(response, body);
  }
  return body;
}

/**
 * Checks whether an origin is allowed under the Mac app allowlist (W4.2).
 * @param {string} accessToken
 * @param {string} origin
 * @returns {Promise<object>}
 */
export async function checkAllowlist(accessToken, origin) {
  const response = await fetch(urlFor(EXTENSION_CONFIG.routes.allowlistCheck), {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({
      protocolVersion: EXTENSION_CONFIG.protocolVersion,
      origin,
    }),
  });

  const body = await parseJSON(response);
  if (!response.ok) {
    throw buildAPIError(response, body);
  }
  return body;
}

/**
 * Adds an origin to the Mac app allowlist after user approval (W4.2).
 * @param {string} accessToken
 * @param {string} origin
 * @returns {Promise<object>}
 */
export async function addToAllowlist(accessToken, origin) {
  const response = await fetch(urlFor(EXTENSION_CONFIG.routes.allowlistAdd), {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({
      protocolVersion: EXTENSION_CONFIG.protocolVersion,
      origin,
    }),
  });

  const body = await parseJSON(response);
  if (!response.ok) {
    throw buildAPIError(response, body);
  }
  return body;
}

/**
 * Marks an origin as not allowed on the Mac app allowlist (red dot).
 * @param {string} accessToken
 * @param {string} origin
 * @returns {Promise<object>}
 */
export async function ignoreOnAllowlist(accessToken, origin) {
  const response = await fetch(urlFor(EXTENSION_CONFIG.routes.allowlistIgnore), {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({
      protocolVersion: EXTENSION_CONFIG.protocolVersion,
      origin,
    }),
  });

  const body = await parseJSON(response);
  if (!response.ok) {
    throw buildAPIError(response, body);
  }
  return body;
}

/**
 * Fetches actively trusted DynamicShield sender domains from the Mac app.
 * @param {string} accessToken
 * @returns {Promise<object>}
 */
export async function fetchDynamicShieldTrustedDomains(accessToken) {
  const response = await fetch(urlFor(EXTENSION_CONFIG.routes.dynamicShieldList), {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({
      protocolVersion: EXTENSION_CONFIG.protocolVersion,
    }),
  });

  const body = await parseJSON(response);
  if (!response.ok) {
    throw buildAPIError(response, body);
  }
  return body;
}

/**
 * Marks an email sender domain as trusted in DynamicShield (Mac Allowed List sync).
 * @param {string} accessToken
 * @param {string} senderDomain
 * @returns {Promise<object>}
 */
export async function trustDynamicShieldSender(accessToken, senderDomain) {
  const response = await fetch(urlFor(EXTENSION_CONFIG.routes.dynamicShieldTrust), {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({
      protocolVersion: EXTENSION_CONFIG.protocolVersion,
      senderDomain,
    }),
  });

  const body = await parseJSON(response);
  if (!response.ok) {
    throw buildAPIError(response, body);
  }
  return body;
}

/**
 * Logs a DynamicShield warning or dismiss event to Mac Security Activity.
 * @param {string} accessToken
 * @param {{ event: string, senderDomain?: string|null, flagSummary?: string|null }} payload
 * @returns {Promise<object>}
 */
export async function logDynamicShieldEvent(accessToken, payload) {
  const response = await fetch(urlFor(EXTENSION_CONFIG.routes.dynamicShieldEvent), {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({
      protocolVersion: EXTENSION_CONFIG.protocolVersion,
      event: payload.event,
      senderDomain: payload.senderDomain ?? null,
      flagSummary: payload.flagSummary ?? null,
    }),
  });

  const body = await parseJSON(response);
  if (!response.ok) {
    throw buildAPIError(response, body);
  }
  return body;
}
