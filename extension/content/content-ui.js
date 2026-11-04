// content-ui.js
// Inline consent panel shown beside password fields (W2.4).
//
// Flow: user types password → explicit Verify click → show granted/denied result.

/**
 * @typedef {'idle' | 'ready' | 'verifying' | 'granted' | 'denied' | 'error'} PanelState
 */

/**
 * Shadow-DOM UI anchored to the active password field.
 */
export class KeyStrokeAuthPanel {
  constructor() {
    this.host = document.createElement("div");
    this.host.id = "keystrokeauth-root";
    this.host.style.all = "initial";
    this.shadow = this.host.attachShadow({ mode: "closed" });
    this.shadow.innerHTML = `
      <style>
        :host { all: initial; }
        .panel {
          position: fixed;
          z-index: 2147483646;
          width: 260px;
          padding: 12px;
          border-radius: 12px;
          border: 1px solid rgba(255,255,255,0.14);
          background: rgba(17,24,39,0.96);
          color: #f9fafb;
          font: 12px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
          box-shadow: 0 10px 30px rgba(0,0,0,0.28);
        }
        .title { font-weight: 700; margin: 0 0 6px; font-size: 13px; }
        .message { margin: 0 0 10px; color: #d1d5db; }
        .button {
          width: 100%;
          border: none;
          border-radius: 8px;
          padding: 9px 10px;
          font-weight: 600;
          cursor: pointer;
        }
        .button.primary { background: #2563eb; color: white; }
        .button.secondary { background: transparent; color: #e5e7eb; border: 1px solid rgba(255,255,255,0.18); margin-top: 8px; }
        .button:disabled { opacity: 0.55; cursor: not-allowed; }
        .granted { color: #4ade80; }
        .denied { color: #f87171; }
      </style>
      <div class="panel" part="panel">
        <p class="title">DynamicKey</p>
        <p class="message" data-role="message"></p>
        <button type="button" class="button primary" data-role="verify">Verify typing rhythm</button>
        <button type="button" class="button secondary" data-role="dismiss">Dismiss</button>
      </div>
    `;

    this.messageEl = this.shadow.querySelector('[data-role="message"]');
    this.verifyButton = this.shadow.querySelector('[data-role="verify"]');
    this.dismissButton = this.shadow.querySelector('[data-role="dismiss"]');
    /** @type {HTMLInputElement | null} */
    this.anchorField = null;
    this.state = "idle";
    /** @type {(() => void) | null} */
    this.onVerify = null;
    /** @type {(() => void) | null} */
    this.onDismiss = null;

    this.verifyButton.addEventListener("mousedown", (event) => event.preventDefault());
    this.dismissButton.addEventListener("mousedown", (event) => event.preventDefault());
    this.verifyButton.addEventListener("click", () => this.onVerify?.());
    this.dismissButton.addEventListener("click", () => this.onDismiss?.());
    this.onScrollOrResize = () => this.reposition();
    document.addEventListener("scroll", this.onScrollOrResize, true);
    window.addEventListener("resize", this.onScrollOrResize);
  }

  /**
   * @param {HTMLInputElement} field
   * @param {{ onVerify: () => void, onDismiss: () => void }} handlers
   */
  show(field, handlers) {
    this.anchorField = field;
    this.onVerify = handlers.onVerify;
    this.onDismiss = handlers.onDismiss;
    if (!this.host.isConnected) {
      document.documentElement.appendChild(this.host);
    }
    this.setState("ready");
    this.reposition();
  }

  hide() {
    this.host.remove();
    this.anchorField = null;
    this.state = "idle";
  }

  /** @param {PanelState} state */
  setState(state) {
    this.state = state;
    switch (state) {
      case "ready":
        this.messageEl.textContent =
          "Type your password at your normal speed, then press Enter or click Verify.";
        this.messageEl.className = "message";
        this.verifyButton.disabled = false;
        this.verifyButton.textContent = "Verify typing rhythm";
        break;
      case "verifying":
        this.messageEl.textContent = "Checking password and rhythm with your Mac app…";
        this.messageEl.className = "message";
        this.verifyButton.disabled = true;
        this.verifyButton.textContent = "Verifying…";
        break;
      case "granted":
        this.messageEl.textContent = "Access granted — rhythm matched your Mac profile.";
        this.messageEl.className = "message granted";
        this.verifyButton.disabled = true;
        this.verifyButton.textContent = "Verified";
        break;
      case "denied":
        this.messageEl.textContent = "Access denied — password or rhythm did not match.";
        this.messageEl.className = "message denied";
        this.verifyButton.disabled = false;
        this.verifyButton.textContent = "Try again";
        break;
      case "error":
        this.verifyButton.disabled = false;
        this.verifyButton.textContent = "Verify typing rhythm";
        break;
      default:
        break;
    }
  }

  /**
   * @param {string} text
   */
  setHint(text) {
    if (this.state === "ready") {
      this.messageEl.textContent = text;
      this.messageEl.className = "message";
    }
  }

  /**
   * @param {string} text
   */
  setError(text) {
    this.setState("error");
    this.messageEl.textContent = text;
    this.messageEl.className = "message denied";
  }

  /**
   * @param {boolean} canVerify
   */
  setVerifyEnabled(canVerify) {
    if (this.state === "ready" || this.state === "denied" || this.state === "error") {
      this.verifyButton.disabled = !canVerify;
    }
  }

  /** Positions the panel below the anchored password field. */
  reposition() {
    if (!this.anchorField) {
      return;
    }
    const rect = this.anchorField.getBoundingClientRect();
    const top = Math.min(window.innerHeight - 140, rect.bottom + 8);
    const left = Math.min(window.innerWidth - 270, Math.max(8, rect.left));
    const panel = this.shadow.querySelector(".panel");
    if (panel instanceof HTMLElement) {
      panel.style.top = `${top}px`;
      panel.style.left = `${left}px`;
    }
  }

  destroy() {
    document.removeEventListener("scroll", this.onScrollOrResize, true);
    window.removeEventListener("resize", this.onScrollOrResize);
    this.hide();
  }
}
