// content-script.js
// Detects password fields, captures rhythm, and verifies via Mac app (W2).
//
// Flow: find field → focus shows consent panel → user verifies → background POST /v1/verify.

import { KeystrokeCapture } from "./keystroke-capture.js";
import { PasswordFieldDetector } from "./password-detector.js";
import { KeyStrokeAuthPanel } from "./content-ui.js";

const capture = new KeystrokeCapture();
const panel = new KeyStrokeAuthPanel();
/** @type {HTMLInputElement | null} */
let activeField = null;

/**
 * Sends a runtime message to the background worker.
 * @template T
 * @param {object} message
 * @returns {Promise<T>}
 */
function sendMessage(message) {
  return new Promise((resolve, reject) => {
    chrome.runtime.sendMessage(message, (response) => {
      if (chrome.runtime.lastError) {
        reject(new Error(chrome.runtime.lastError.message));
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
 * @returns {Promise<boolean>}
 */
async function canVerifyOnThisPage() {
  try {
    const snapshot = await sendMessage({ type: "GET_SNAPSHOT" });
    return snapshot.state === "connected" && Boolean(snapshot.session);
  } catch {
    return false;
  }
}

/**
 * @param {HTMLInputElement} field
 * @returns {boolean}
 */
function canSubmitVerification(field) {
  return field.value.length > 0 && capture.exportSamples().length > 0;
}

/**
 * @param {HTMLInputElement} field
 */
function wirePasswordField(field) {
  field.addEventListener("focus", async () => {
    if (!(await canVerifyOnThisPage())) {
      return;
    }

    activeField = field;
    capture.attach(field);

    panel.show(field, {
      onVerify: () => submitVerification(field),
      onDismiss: () => {
        capture.detach();
        panel.hide();
        activeField = null;
      },
    });

    updateVerifyButtonState(field);
  });

  field.addEventListener("input", () => {
    if (activeField === field) {
      updateVerifyButtonState(field);
      if (field.value.length > 0 && capture.exportSamples().length === 0) {
        panel.setHint("Type each character manually — pasted passwords cannot capture rhythm.");
      }
    }
  });

  field.addEventListener("keyup", () => {
    if (activeField === field) {
      updateVerifyButtonState(field);
    }
  });

  field.addEventListener("keydown", (event) => {
    if (activeField !== field || event.key !== "Enter") {
      return;
    }

    event.preventDefault();
    if (!canSubmitVerification(field)) {
      panel.setError("Type your password at normal speed, then press Enter or click Verify.");
      return;
    }

    submitVerification(field);
  });

  field.addEventListener("blur", () => {
    window.setTimeout(() => {
      if (document.activeElement === field) {
        return;
      }
      if (activeField === field) {
        capture.detach();
        panel.hide();
        activeField = null;
      }
    }, 150);
  });
}

/**
 * @param {HTMLInputElement} field
 */
function updateVerifyButtonState(field) {
  panel.setVerifyEnabled(canSubmitVerification(field));
}

/**
 * @param {HTMLInputElement} field
 */
async function submitVerification(field) {
  const password = field.value;
  const keystrokes = capture.exportSamples();

  if (!password || keystrokes.length === 0) {
    panel.setError("Type your password before verifying.");
    return;
  }

  panel.setState("verifying");

  try {
    const result = await sendMessage({
      type: "VERIFY_LOGIN",
      origin: window.location.origin,
      password,
      keystrokes,
    });

    if (result.granted) {
      panel.setState("granted");
      panel.messageEl.textContent = `Access granted — rhythm match ${result.matchPercentage}%.`;
      panel.messageEl.className = "message granted";
    } else {
      panel.setState("denied");
      if (result.matchPercentage > 0) {
        panel.messageEl.textContent = `Access denied — rhythm match ${result.matchPercentage}%.`;
      }
      if (result.denialReason === "lockedOut") {
        const seconds = result.lockoutRemainingSeconds ?? 0;
        panel.setError(`Too many failed attempts. Try again in ${seconds}s.`);
      }
    }
  } catch (error) {
    panel.setError(error instanceof Error ? error.message : "Verification failed.");
  } finally {
    capture.reset();
    updateVerifyButtonState(field);
  }
}

const detector = new PasswordFieldDetector((field) => {
  wirePasswordField(field);
});

detector.start();
