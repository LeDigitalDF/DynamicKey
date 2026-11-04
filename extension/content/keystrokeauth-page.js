// keystrokeauth-page.js
// Single-file content script (no ES imports) for reliable Chrome injection (W2–W4).
//
// Flow: detect password field → master typed in overlay panel → verify → auto-fill site login.

(() => {
  const ONBOARDING_STORAGE_KEY = "keystrokeauth.onboardingSeenOrigins";
  const ONBOARDING_DISMISS_MS = 3500;
  const SILENT_DISMISS_MS = 200;
  const GRANTED_SUCCESS_DISMISS_MS = 900;
  const GRANTED_LOGIN_AUTO_SUBMIT_MS = 350;
  const LOGIN_IDENTIFIER_CACHE_PREFIX = "keystrokeauth.cachedLoginIdentifier:";
  const SIGNUP_FLOW_CACHE_PREFIX = "keystrokeauth.signupFlowActive:";
  if (window.__keystrokeAuthContentLoaded) {
    return;
  }
  window.__keystrokeAuthContentLoaded = true;

  const browserAPI = globalThis.browser ?? globalThis.chrome;
  let debugModeEnabled = false;

  browserAPI.storage.local.get(
    ["keystrokeauth.debugMode"],
    (result) => {
      debugModeEnabled = Boolean(result["keystrokeauth.debugMode"]);
    }
  );
  browserAPI.storage.onChanged.addListener((changes, area) => {
    if (area !== "local") return;
    if (changes["keystrokeauth.debugMode"]) {
      debugModeEnabled = Boolean(changes["keystrokeauth.debugMode"].newValue);
    }
  });

  function debugLog(...args) {
    if (debugModeEnabled) {
      console.log("[DynamicKey]", ...args);
    }
  }

  class KeystrokeCapture {
    constructor() {
      this.samples = [];
      this.keyDownTimes = new Map();
      this.lastKeyUpTime = null;
      this.boundKeyDown = this.onKeyDown.bind(this);
      this.boundKeyUp = this.onKeyUp.bind(this);
      this.field = null;
    }

    attach(field) {
      this.detach();
      this.field = field;
      this.reset();
      field.addEventListener("keydown", this.boundKeyDown, true);
      field.addEventListener("keyup", this.boundKeyUp, true);
    }

    detach() {
      if (this.field) {
        this.field.removeEventListener("keydown", this.boundKeyDown, true);
        this.field.removeEventListener("keyup", this.boundKeyUp, true);
        this.field = null;
      }
      this.reset();
    }

    reset() {
      this.samples = [];
      this.keyDownTimes.clear();
      this.lastKeyUpTime = null;
    }

    exportSamples() {
      return this.samples.map((sample) => ({ ...sample }));
    }

    onKeyDown(event) {
      if (!this.field) return;

      if (event.key === "Backspace" || event.key === "Delete") {
        if (this.samples.length > 0) this.samples.pop();
        this.lastKeyUpTime = performance.now() / 1000;
        return;
      }

      if (event.key.length !== 1 || event.ctrlKey || event.metaKey || event.altKey) {
        return;
      }

      this.keyDownTimes.set(event.code, performance.now() / 1000);
    }

    onKeyUp(event) {
      if (!this.field) return;
      if (event.key === "Backspace" || event.key === "Delete") return;
      if (event.key.length !== 1) return;

      const keyDownTime = this.keyDownTimes.get(event.code);
      if (keyDownTime === undefined) return;

      const keyUpTime = performance.now() / 1000;
      const dwellTime = Math.max(0, keyUpTime - keyDownTime);
      const flightTime =
        this.lastKeyUpTime === null ? 0 : Math.max(0, keyDownTime - this.lastKeyUpTime);

      this.samples.push({ character: event.key, dwellTime, flightTime });
      this.keyDownTimes.delete(event.code);
      this.lastKeyUpTime = keyUpTime;
    }
  }

  const PASSWORD_SELECTOR = [
    'input[type="password"]',
    'input[autocomplete="current-password"]',
    'input[autocomplete="new-password"]',
    'input[name="password" i]',
    'input[id="password" i]',
    'input[id="login-password" i]',
    'input[id*="password" i]',
    'input[name*="password" i]',
  ].join(",");

  /** True when an input is likely a password field (including text inputs used for masked passwords). */
  function isLikelyPasswordInput(element) {
    if (!(element instanceof HTMLInputElement)) return false;
    const type = (element.getAttribute("type") || "text").toLowerCase();
    if (type === "password") return true;
    if (type !== "text" && type !== "") return false;

    const autocomplete = (element.getAttribute("autocomplete") || "").toLowerCase();
    const haystack = `${element.id} ${element.name} ${element.getAttribute("aria-label") ?? ""}`.toLowerCase();
    return autocomplete.includes("password") || /password/.test(haystack);
  }

  /** True when a password field is still in the document and visibly on screen. */
  function isFieldLive(field) {
    if (!(field instanceof HTMLInputElement)) return false;
    if (!field.isConnected) return false;
    if (!isLikelyPasswordInput(field)) return false;
    if (field.disabled) return false;

    const style = window.getComputedStyle(field);
    if (style.display === "none" || style.visibility === "hidden") return false;

    const rect = field.getBoundingClientRect();
    return rect.width >= 1 && rect.height >= 1;
  }

  class PasswordFieldDetector {
    constructor(onFieldFound) {
      this.onFieldFound = onFieldFound;
      this.seenFields = new WeakSet();
      this.observer = null;
    }

    start() {
      this.scan(document);
      this.observer = new MutationObserver(() => {
        scheduleOverlaySync();
      });
      this.observer.observe(document.documentElement, { childList: true, subtree: true });
    }

    scan(root) {
      if (!root || typeof root.querySelectorAll !== "function") return;
      root.querySelectorAll(PASSWORD_SELECTOR).forEach((element) => {
        if (!isLikelyPasswordInput(element) || this.seenFields.has(element)) return;
        const wired = this.onFieldFound(element);
        if (wired !== false) {
          this.seenFields.add(element);
        }
      });
    }

    rescan() {
      this.scan(document);
    }
  }

  const EXTENSION_ICON_URL = browserAPI.runtime.getURL("icons/icon32.png");

  /** Parses an rgb/rgba color string into [r, g, b] or null. */
  function parseRGB(color) {
    const match = color.match(/rgba?\(\s*(\d+)[,\s]+(\d+)[,\s]+(\d+)/i);
    if (!match) {
      return null;
    }
    return [Number(match[1]), Number(match[2]), Number(match[3])];
  }

  /** Returns relative luminance for a sRGB triplet. */
  function relativeLuminance([red, green, blue]) {
    const channel = (value) => {
      const normalized = value / 255;
      return normalized <= 0.03928
        ? normalized / 12.92
        : ((normalized + 0.055) / 1.055) ** 2.4;
    };
    return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue);
  }

  /** Estimates whether the page behind the password field is visually light. */
  function isLightPageSurface(anchorField) {
    const rect = anchorField.getBoundingClientRect();
    const sampleX = Math.min(window.innerWidth - 1, Math.max(0, rect.left + rect.width / 2));
    const sampleY = Math.min(window.innerHeight - 1, Math.max(0, rect.top + rect.height / 2));
    const stack = document.elementsFromPoint(sampleX, sampleY);

    for (const element of stack) {
      if (!(element instanceof Element)) {
        continue;
      }
      if (element === anchorField || element.contains(anchorField)) {
        const background = window.getComputedStyle(element).backgroundColor;
        const rgb = parseRGB(background);
        if (rgb && background !== "rgba(0, 0, 0, 0)" && background !== "transparent") {
          return relativeLuminance(rgb) > 0.62;
        }
      }
    }

    let node = anchorField.parentElement;
    while (node) {
      const background = window.getComputedStyle(node).backgroundColor;
      const rgb = parseRGB(background);
      if (rgb && background !== "rgba(0, 0, 0, 0)" && background !== "transparent") {
        return relativeLuminance(rgb) > 0.62;
      }
      node = node.parentElement;
    }

    const bodyBackground = window.getComputedStyle(document.body).backgroundColor;
    const bodyRGB = parseRGB(bodyBackground);
    return bodyRGB ? relativeLuminance(bodyRGB) > 0.62 : true;
  }

  /**
   * Resolves the painted width/position for a password field, including common wrappers.
   * @param {HTMLInputElement} field
   * @returns {{ anchorEl: HTMLElement, rect: DOMRect, width: number, left: number }}
   */
  function resolveFieldAnchorMetrics(field) {
    const fieldRect = field.getBoundingClientRect();
    let anchorEl = field;
    let anchorRect = fieldRect;
    let anchorWidth = Math.max(field.offsetWidth, fieldRect.width, field.clientWidth);

    let parent = field.parentElement;
    for (let depth = 0; depth < 6 && parent instanceof HTMLElement; depth += 1) {
      const parentRect = parent.getBoundingClientRect();
      const parentWidth = Math.max(parent.offsetWidth, parentRect.width, parent.clientWidth);
      const heightRatio = parentRect.height / Math.max(fieldRect.height, 1);
      const passwordInputs = parent.querySelectorAll(
        'input[type="password"], input[autocomplete="current-password"], input[autocomplete="new-password"]'
      );
      const isReasonableWrapper =
        parent.contains(field)
        && heightRatio >= 0.7
        && heightRatio <= 2.8
        && passwordInputs.length <= 2
        && parentWidth > anchorWidth + 1;

      if (isReasonableWrapper) {
        anchorEl = parent;
        anchorRect = parentRect;
        anchorWidth = parentWidth;
      }

      parent = parent.parentElement;
    }

    return {
      anchorEl,
      rect: anchorRect,
      width: Math.round(anchorWidth),
      left: Math.round(anchorRect.left),
    };
  }

  /** Returns true when an element looks like a show/hide password control beside the field. */
  function isLikelyPasswordRevealControl(element, field) {
    if (!(element instanceof HTMLElement) || element === field || element.contains(field)) {
      return false;
    }

    const style = window.getComputedStyle(element);
    if (style.display === "none" || style.visibility === "hidden" || Number(style.opacity) === 0) {
      return false;
    }

    const rect = element.getBoundingClientRect();
    if (rect.width < 10 || rect.height < 10) {
      return false;
    }

    const fieldRect = field.getBoundingClientRect();
    const verticalOverlap = Math.min(rect.bottom, fieldRect.bottom) - Math.max(rect.top, fieldRect.top);
    if (verticalOverlap < fieldRect.height * 0.35) {
      return false;
    }

    if (rect.left < fieldRect.left + fieldRect.width * 0.45) {
      return false;
    }

    const haystack = `${element.className} ${element.id} ${element.getAttribute("aria-label") ?? ""} ${element.getAttribute("title") ?? ""}`.toLowerCase();
    const revealPattern = /show|hide|reveal|visibility|password|eye|toggle|unmask|view|peek/;
    const isClickable =
      element.tagName === "BUTTON"
      || element.getAttribute("role") === "button"
      || element.tabIndex >= 0;

    if (revealPattern.test(haystack)) {
      return true;
    }

    if (isClickable && element.querySelector("svg") && rect.width <= 56 && rect.height <= 56) {
      return true;
    }

    return isClickable && rect.left >= fieldRect.right - fieldRect.width * 0.35;
  }

  /** Finds the password reveal (eye) control beside the field, if present. */
  function findPasswordRevealControl(field) {
    const metrics = resolveFieldAnchorMetrics(field);
    const searchRoot = metrics.anchorEl;
    const fieldRect = field.getBoundingClientRect();
    const candidates = searchRoot.querySelectorAll('button, [role="button"], a, span, div');

    let bestMatch = null;
    let bestRight = -1;
    let bestWidth = Number.POSITIVE_INFINITY;

    for (const candidate of candidates) {
      if (!(candidate instanceof HTMLElement) || !isLikelyPasswordRevealControl(candidate, field)) {
        continue;
      }

      const rect = candidate.getBoundingClientRect();
      if (rect.width > 72) {
        continue;
      }

      const isBetter =
        rect.right > bestRight + 1
        || (Math.abs(rect.right - bestRight) <= 1 && rect.width < bestWidth);

      if (isBetter) {
        bestRight = rect.right;
        bestWidth = rect.width;
        bestMatch = candidate;
      }
    }

    if (bestMatch || fieldRect.width < 1) {
      return bestMatch;
    }

    return null;
  }

  /**
   * Computes badge coordinates to sit just left of the password reveal icon when possible.
   * @param {HTMLInputElement} field
   * @param {number} badgeSize
   */
  function resolveBadgePosition(field, badgeSize) {
    const inputRect = field.getBoundingClientRect();
    const top = inputRect.top + (inputRect.height - badgeSize) / 2;
    const gap = 5;
    const revealControl = findPasswordRevealControl(field);

    if (revealControl) {
      const revealRect = revealControl.getBoundingClientRect();
      const left = revealRect.left - badgeSize - gap;
      return {
        top,
        left: Math.max(inputRect.left + 4, left),
      };
    }

    const inset = Math.max(4, Math.round(badgeSize * 0.2));
    const eyeReserve = Math.max(28, Math.round(inputRect.height * 0.85));
    const left = inputRect.right - eyeReserve - badgeSize - inset;

    return {
      top,
      left: Math.max(inputRect.left + 4, left),
    };
  }

  /** Small in-field launcher shown after the user taps Not Now. */
  class FieldLaunchBadge {
    constructor() {
      this.host = document.createElement("div");
      this.host.id = "dynamickey-field-badge";
      this.shadow = this.host.attachShadow({ mode: "closed" });
      this.shadow.innerHTML = `
        <style>
          .badge {
            position: fixed;
            z-index: 2147483645;
            width: var(--badge-size, 28px);
            height: var(--badge-size, 28px);
            padding: 0;
            border: none;
            border-radius: var(--badge-radius, 8px);
            background: rgba(15, 23, 42, 0.82);
            border: 1px solid rgba(255, 255, 255, 0.18);
            backdrop-filter: blur(12px) saturate(140%);
            -webkit-backdrop-filter: blur(12px) saturate(140%);
            box-shadow:
              inset 0 1px 0 rgba(255, 255, 255, 0.1),
              0 2px 12px rgba(0, 0, 0, 0.32);
            cursor: pointer;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            transition: transform 0.14s ease, box-shadow 0.14s ease, border-color 0.14s ease;
          }
          .badge:hover {
            transform: scale(1.06);
            border-color: rgba(255, 255, 255, 0.28);
            box-shadow:
              inset 0 1px 0 rgba(255, 255, 255, 0.14),
              0 4px 16px rgba(0, 0, 0, 0.36),
              0 0 10px rgba(79, 124, 255, 0.22);
          }
          .badge img {
            width: var(--icon-size, 22px);
            height: var(--icon-size, 22px);
            border-radius: var(--icon-radius, 5px);
            display: block;
          }
        </style>
        <button type="button" class="badge" aria-label="Authenticate with DynamicKey">
          <img alt="" data-role="icon" />
        </button>
      `;
      this.button = this.shadow.querySelector(".badge");
      this.iconEl = this.shadow.querySelector('[data-role="icon"]');
      this.iconEl.src = EXTENSION_ICON_URL;
      this.anchorField = null;
      this.resizeObserver = null;
      this.onLaunch = null;
      this.onScrollOrResize = () => this.reposition();
      this.button.addEventListener("mousedown", (event) => event.preventDefault());
      this.button.addEventListener("click", (event) => {
        event.preventDefault();
        event.stopPropagation();
        this.onLaunch?.();
      });
    }

    show(field, onLaunch) {
      this.anchorField = field;
      this.onLaunch = onLaunch;
      if (!this.host.isConnected) {
        document.documentElement.appendChild(this.host);
      }
      this.resizeObserver?.disconnect();
      this.resizeObserver = new ResizeObserver(() => this.reposition());
      this.resizeObserver.observe(field);
      const metrics = resolveFieldAnchorMetrics(field);
      if (metrics.anchorEl !== field) {
        this.resizeObserver.observe(metrics.anchorEl);
      }
      document.addEventListener("scroll", this.onScrollOrResize, true);
      window.addEventListener("resize", this.onScrollOrResize);
      this.reposition();
    }

    hide() {
      this.resizeObserver?.disconnect();
      this.resizeObserver = null;
      this.host.remove();
      this.anchorField = null;
      document.removeEventListener("scroll", this.onScrollOrResize, true);
      window.removeEventListener("resize", this.onScrollOrResize);
    }

    reposition() {
      if (!this.anchorField || !this.button) return;

      if (!isFieldLive(this.anchorField)) {
        this.hide();
        return;
      }

      const metrics = resolveFieldAnchorMetrics(this.anchorField);
      const fieldHeight = metrics.rect.height;
      const fieldWidth = metrics.width;
      if (fieldHeight < 1 || fieldWidth < 1) {
        return;
      }

      const heightBudget = Math.max(12, fieldHeight - 6);
      const widthBudget = Math.max(12, fieldWidth * 0.2);
      const size = Math.round(Math.min(28, heightBudget, widthBudget));
      const clampedSize = Math.max(14, size);
      const iconSize = Math.max(10, Math.round(clampedSize * 0.76));
      const badgeRadius = Math.max(4, Math.round(clampedSize * 0.28));
      const iconRadius = Math.max(3, Math.round(iconSize * 0.22));

      this.button.style.setProperty("--badge-size", `${clampedSize}px`);
      this.button.style.setProperty("--badge-radius", `${badgeRadius}px`);
      this.button.style.setProperty("--icon-size", `${iconSize}px`);
      this.button.style.setProperty("--icon-radius", `${iconRadius}px`);

      const position = resolveBadgePosition(this.anchorField, clampedSize);
      this.button.style.top = `${Math.max(4, position.top)}px`;
      this.button.style.left = `${Math.max(4, position.left)}px`;
    }
  }

  class DynamicKeyPanel {
    constructor() {
      this.host = document.createElement("div");
      this.host.id = "keystrokeauth-root";
      this.shadow = this.host.attachShadow({ mode: "closed" });
      this.shadow.innerHTML = `
        <style>
          .panel {
            position: fixed;
            z-index: 2147483647;
            box-sizing: border-box;
            padding: 16px 14px 14px;
            border-radius: 18px;
            border: 1px solid rgba(255, 255, 255, 0.24);
            backdrop-filter: blur(24px) saturate(160%);
            -webkit-backdrop-filter: blur(24px) saturate(160%);
            font: 13px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            box-shadow:
              inset 0 1px 0 rgba(255, 255, 255, 0.2),
              0 14px 36px rgba(0, 0, 0, 0.28);
            text-align: center;
          }
          .panel.surface-dark {
            background: rgba(255, 255, 255, 0.14);
            color: #f8fafc;
          }
          .panel.surface-light {
            background: rgba(15, 23, 42, 0.84);
            border-color: rgba(15, 23, 42, 0.34);
            color: #f8fafc;
            box-shadow:
              inset 0 1px 0 rgba(255, 255, 255, 0.1),
              0 16px 40px rgba(15, 23, 42, 0.28);
          }
          .brand-header {
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 8px;
            margin-bottom: 10px;
          }
          .brand-logo {
            width: 24px;
            height: 24px;
            border-radius: 7px;
            display: block;
          }
          .brand-name {
            font-size: 14px;
            font-weight: 700;
            letter-spacing: 0.01em;
          }
          .headline {
            margin: 0 0 12px;
            font-size: 15px;
            font-weight: 700;
            color: #f8fafc;
          }
          .message {
            margin: 0 0 12px;
            color: rgba(248, 250, 252, 0.78);
            font-size: 12px;
          }
          .button {
            border: none;
            border-radius: 10px;
            padding: 10px 12px;
            font-weight: 600;
            cursor: pointer;
            font-size: 12px;
          }
          .button.primary {
            width: 100%;
            background: linear-gradient(180deg, rgba(79, 124, 255, 0.95), rgba(59, 99, 230, 0.95));
            color: #fff;
            border: 1px solid rgba(255, 255, 255, 0.22);
          }
          .button.secondary {
            background: rgba(255, 255, 255, 0.08);
            color: #f8fafc;
            border: 1px solid rgba(255, 255, 255, 0.2);
          }
          .button.not-now {
            background: rgba(79, 124, 255, 0.28);
            color: #e8efff;
            border: 1px solid rgba(111, 149, 255, 0.52);
          }
          .button.not-now:hover {
            background: rgba(79, 124, 255, 0.38);
          }
          .button.danger {
            background: rgba(255, 107, 107, 0.16);
            color: #fecaca;
            border: 1px solid rgba(255, 107, 107, 0.34);
          }
          .button:disabled { opacity: 0.55; cursor: not-allowed; }
          .granted { color: #4ade80; }
          .denied { color: #f87171; }
          .master-label {
            display: block;
            font-size: 11px;
            font-weight: 600;
            color: rgba(248, 250, 252, 0.68);
            margin: 0 0 6px;
            text-transform: uppercase;
            letter-spacing: 0.04em;
            text-align: left;
          }
          .master-input {
            width: 100%;
            box-sizing: border-box;
            margin-bottom: 12px;
            padding: 10px 12px;
            border-radius: 10px;
            border: 1px solid rgba(255, 255, 255, 0.24);
            background: rgba(0, 0, 0, 0.22);
            color: #f8fafc;
            font: 14px/1.3 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
          }
          .master-input:focus {
            outline: none;
            border-color: rgba(79, 124, 255, 0.85);
            box-shadow: 0 0 0 2px rgba(79, 124, 255, 0.28);
          }
          .dismiss-row {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 8px;
            margin-top: 4px;
          }
          .panel[data-state="granted"] .dismiss-row,
          .panel[data-state="granted"] [data-role="not-now"],
          .panel[data-state="granted"] [data-role="never-site"] {
            display: none !important;
          }
          .utility-actions {
            display: flex;
            flex-direction: column;
            gap: 8px;
            margin-top: 8px;
          }
        </style>
        <div class="panel">
          <div class="brand-header">
            <img class="brand-logo" data-role="brand-logo" alt="" />
            <span class="brand-name">DynamicKey</span>
          </div>
          <p class="headline" data-role="headline">Authentication Required</p>
          <p class="message" data-role="message">Connecting…</p>
          <div data-role="allowlist-section" hidden>
            <button type="button" class="button primary" data-role="allow-site">Add to Protected Websites</button>
          </div>
          <div data-role="verify-section">
            <label class="master-label" for="ksa-master-input">Master password</label>
            <input
              id="ksa-master-input"
              type="password"
              class="master-input"
              data-role="master-input"
              autocomplete="off"
              spellcheck="false"
              aria-label="DynamicKey master password"
            />
            <div class="utility-actions">
              <button type="button" class="button primary" data-role="autofill" hidden>Retry autofill</button>
              <button type="button" class="button primary" data-role="continue-login" hidden>Log in on website</button>
              <button type="button" class="button secondary" data-role="reset-lockout" hidden>Reset lockout (testing)</button>
            </div>
          </div>
          <div class="dismiss-row" data-role="dismiss-row" hidden>
            <button type="button" class="button not-now" data-role="not-now">Not Now</button>
            <button type="button" class="button danger" data-role="never-site">Never ask again</button>
          </div>
        </div>
      `;

      this.panelEl = this.shadow.querySelector(".panel");
      this.headlineEl = this.shadow.querySelector('[data-role="headline"]');
      this.messageEl = this.shadow.querySelector('[data-role="message"]');
      this.autofillButton = this.shadow.querySelector('[data-role="autofill"]');
      this.continueLoginButton = this.shadow.querySelector('[data-role="continue-login"]');
      this.resetLockoutButton = this.shadow.querySelector('[data-role="reset-lockout"]');
      this.notNowButton = this.shadow.querySelector('[data-role="not-now"]');
      this.neverSiteButton = this.shadow.querySelector('[data-role="never-site"]');
      this.dismissRowEl = this.shadow.querySelector('[data-role="dismiss-row"]');
      this.masterInput = this.shadow.querySelector('[data-role="master-input"]');
      this.verifySectionEl = this.shadow.querySelector('[data-role="verify-section"]');
      this.allowlistSectionEl = this.shadow.querySelector('[data-role="allowlist-section"]');
      this.allowSiteButton = this.shadow.querySelector('[data-role="allow-site"]');
      this.shadow.querySelector('[data-role="brand-logo"]').src = EXTENSION_ICON_URL;
      this.formMode = "login";
      this.anchorField = null;
      this.anchorResizeEl = null;
      this.state = "idle";
      this.resizeObserver = null;
      this.onVerify = null;
      this.onNotNow = null;
      this.onNeverSite = null;
      this.onResetLockout = null;
      this.onAutofill = null;
      this.onContinueLogin = null;
      this.onAllowSite = null;

      this.autofillButton.addEventListener("mousedown", (event) => event.preventDefault());
      this.continueLoginButton.addEventListener("mousedown", (event) => event.preventDefault());
      this.resetLockoutButton.addEventListener("mousedown", (event) => event.preventDefault());
      this.notNowButton.addEventListener("mousedown", (event) => event.preventDefault());
      this.neverSiteButton.addEventListener("mousedown", (event) => event.preventDefault());
      this.allowSiteButton.addEventListener("mousedown", (event) => event.preventDefault());
      this.autofillButton.addEventListener("click", () => this.onAutofill?.());
      this.continueLoginButton.addEventListener("click", () => this.onContinueLogin?.());
      this.resetLockoutButton.addEventListener("click", () => this.onResetLockout?.());
      this.notNowButton.addEventListener("click", () => this.onNotNow?.());
      this.neverSiteButton.addEventListener("click", () => this.onNeverSite?.());
      this.allowSiteButton.addEventListener("click", () => this.onAllowSite?.());
      this.masterInput.addEventListener("mousedown", (event) => event.stopPropagation());
      this.masterInput.addEventListener("keydown", (event) => {
        if (event.key === "Enter") {
          event.preventDefault();
          this.onVerify?.();
        }
      });
      this.onScrollOrResize = () => this.reposition();
      document.addEventListener("scroll", this.onScrollOrResize, true);
      window.addEventListener("resize", this.onScrollOrResize);
    }

    show(field, handlers) {
      this.anchorField = field;
      this.onVerify = handlers.onVerify;
      this.onNotNow = handlers.onNotNow;
      this.onNeverSite = handlers.onNeverSite;
      this.onResetLockout = handlers.onResetLockout ?? null;
      this.onAutofill = handlers.onAutofill ?? null;
      this.onContinueLogin = handlers.onContinueLogin ?? null;
      this.onAllowSite = handlers.onAllowSite ?? null;
      this.formMode = handlers.formMode ?? "login";
      if (this.panelEl) {
        this.panelEl.dataset.state = "idle";
      }
      if (!this.host.isConnected) {
        document.documentElement.appendChild(this.host);
      }
      this.resizeObserver?.disconnect();
      this.resizeObserver = new ResizeObserver(() => this.reposition());
      this.resizeObserver.observe(field);
      const metrics = resolveFieldAnchorMetrics(field);
      this.anchorResizeEl = metrics.anchorEl;
      if (metrics.anchorEl !== field) {
        this.resizeObserver.observe(metrics.anchorEl);
      }
      this.showResetLockout(false);
      this.showAutofill(false);
      this.showContinueLogin(false);
      this.showDismissRow(true);
      this.setFormMode(this.formMode);
      this.clearMasterInput();
      this.showVerifySection(false);
      this.showAllowlistSection(false);
      this.headlineEl.hidden = false;
      this.headlineEl.textContent = "Authentication Required";
      this.messageEl.textContent = "Connecting…";
      this.messageEl.className = "message";
      this.state = "idle";
      this.reposition();
    }

    hide() {
      this.resizeObserver?.disconnect();
      this.resizeObserver = null;
      this.anchorResizeEl = null;
      this.host.remove();
      this.anchorField = null;
      this.state = "idle";
      this.clearMasterInput();
    }

    setFormMode(mode) {
      this.formMode = mode;
    }

    focusMasterInput() {
      this.masterInput?.focus();
    }

    clearMasterInput() {
      if (this.masterInput) {
        this.masterInput.value = "";
      }
    }

    getMasterPassword() {
      return this.masterInput?.value ?? "";
    }

    containsFocus() {
      const active = this.shadow.activeElement;
      return active === this.masterInput || active === this.autofillButton
        || active === this.continueLoginButton || active === this.resetLockoutButton
        || active === this.notNowButton || active === this.neverSiteButton
        || active === this.allowSiteButton;
    }

    showVerifySection(visible) {
      if (this.verifySectionEl) {
        this.verifySectionEl.hidden = !visible;
      }
    }

    showAllowlistSection(visible) {
      if (this.allowlistSectionEl) {
        this.allowlistSectionEl.hidden = !visible;
      }
      if (visible) {
        this.headlineEl.hidden = true;
        this.showDismissRow(true);
      }
    }

    showAllowlistPrompt(normalizedOrigin) {
      this.state = "allowlist";
      this.showVerifySection(false);
      this.showAllowlistSection(true);
      this.showResetLockout(false);
      this.showAutofill(false);
      this.messageEl.textContent =
        `This website is not protected yet. Tap Add to Protected Websites below, or add ${normalizedOrigin} in DynamicKey on your Mac.`;
      this.messageEl.className = "message";
      window.requestAnimationFrame(() => this.reposition());
    }

    showVerifyUI() {
      this.showAllowlistSection(false);
      this.showVerifySection(true);
      this.headlineEl.hidden = false;
      this.headlineEl.textContent = "Authentication Required";
      this.showDismissRow(true);
    }

    setState(state) {
      this.state = state;
      switch (state) {
        case "ready":
          this.headlineEl.hidden = false;
          this.headlineEl.textContent = "Authentication Required";
          this.messageEl.textContent = "Press Enter when finished typing.";
          this.messageEl.className = "message";
          break;
        case "verifying":
          this.messageEl.textContent = "Checking with your Mac app…";
          this.messageEl.className = "message";
          break;
        case "granted":
          this.applyGrantedPanelLayout();
          break;
        case "denied":
          this.headlineEl.textContent = "Authentication Required";
          this.messageEl.textContent = "Access denied — password or rhythm did not match.";
          this.messageEl.className = "message denied";
          break;
        case "error":
          break;
        default:
          break;
      }
      window.requestAnimationFrame(() => this.reposition());
    }

    setHint(text) {
      if (this.state === "ready") {
        this.messageEl.textContent = text;
        this.messageEl.className = "message";
      }
    }

    setError(text) {
      this.setState("error");
      this.headlineEl.textContent = "Authentication Required";
      this.messageEl.textContent = text;
      this.messageEl.className = "message denied";
    }

    setVerifyEnabled() {
      // Enter submits verification; no separate verify button.
    }

    showResetLockout(visible) {
      this.resetLockoutButton.hidden = !visible;
    }

    showAutofill(visible) {
      this.autofillButton.hidden = !visible;
    }

    showContinueLogin(visible) {
      this.continueLoginButton.hidden = !visible;
    }

    showDismissRow(visible) {
      if (this.dismissRowEl) {
        this.dismissRowEl.hidden = !visible;
      }
      if (this.notNowButton) {
        this.notNowButton.hidden = !visible;
      }
      if (this.neverSiteButton) {
        this.neverSiteButton.hidden = !visible;
      }
    }

    showGrantedCompactUI() {
      this.applyGrantedPanelLayout();
    }

    /** Keeps the success message in the same anchored panel below the field (no duplicate top popup). */
    applyGrantedPanelLayout() {
      this.showVerifySection(false);
      this.showAllowlistSection(false);
      this.showResetLockout(false);
      this.showAutofill(false);
      this.showContinueLogin(false);
      this.showDismissRow(false);
      this.headlineEl.hidden = false;
      this.headlineEl.textContent = "Access granted";
      if (this.panelEl) {
        this.panelEl.dataset.state = "granted";
      }
      window.requestAnimationFrame(() => this.reposition());
    }

    shouldKeepVisible() {
      return this.state === "allowlist" || this.state === "verifying"
        || this.state === "denied" || this.state === "error";
    }

    reposition() {
      if (!this.anchorField || !this.panelEl) return;

      const metrics = resolveFieldAnchorMetrics(this.anchorField);
      const panelWidth = metrics.width;
      if (panelWidth < 1) {
        return;
      }

      this.panelEl.style.width = `${panelWidth}px`;
      this.panelEl.style.minWidth = `${panelWidth}px`;
      this.panelEl.style.maxWidth = `${panelWidth}px`;

      const useLightSurface = isLightPageSurface(this.anchorField);
      this.panelEl.classList.toggle("surface-light", useLightSurface);
      this.panelEl.classList.toggle("surface-dark", !useLightSurface);

      const panelHeight = this.panelEl.offsetHeight || 240;
      const top = Math.min(window.innerHeight - panelHeight - 8, metrics.rect.bottom + 10);

      const clampedLeft = Math.min(window.innerWidth - panelWidth - 8, Math.max(8, metrics.left));
      this.panelEl.style.top = `${Math.round(top)}px`;
      this.panelEl.style.left = `${clampedLeft}px`;
    }
  }

  /** True when the page URL is a password-change or reset flow. */
  function isChangePasswordPageContext() {
    return /change-password|password-reset|reset-password|update-password|forgot-password|recover-password|reset_password|forgot_password/i.test(
      `${location.pathname}${location.search}${location.hash}`
    );
  }

  /** Detects active reset/set-password flows — ignores mere "Forgot password?" links on login pages. */
  function pageLooksLikePasswordReset() {
    const urlHaystack = `${location.pathname}${location.search}${location.hash}`.toLowerCase();
    if (/reset|forgot|recover/.test(urlHaystack) && /password|passwd/.test(urlHaystack)) {
      return true;
    }

    const pageHaystack = pageContextHaystack();
    if (/reset.?password|password.?reset|forgot.?password|recover.?password|set.?new.?password|create.?new.?password/.test(
      pageHaystack
    )) {
      return true;
    }

    const bodyText = (document.body?.innerText ?? "").slice(0, 4000).toLowerCase();
    return /you requested a password reset|enter (your )?new password below|choose a new password for your account|set a new password for your account|create a new password for your account/.test(
      bodyText
    );
  }

  /** True when an existing stored site password should be reused (log-in), not rotated. */
  function shouldTreatAsStoredCredentialLogin(field, mode) {
    if (mode === "signup") {
      return false;
    }
    if (hasCurrentPasswordField(document)) {
      return false;
    }
    if (visiblePasswordFields().length >= 2) {
      return false;
    }

    const autocomplete = (field.getAttribute("autocomplete") || "").toLowerCase();
    if (autocomplete === "new-password") {
      return false;
    }
    if (isChangePasswordPageContext()) {
      return false;
    }
    if (pageLooksLikePasswordReset()) {
      return false;
    }

    return true;
  }

  /** True when fill should replace the Mac-stored site password (real change/reset forms only). */
  function shouldRotateSitePassword(field, mode) {
    if (mode !== "changePassword") {
      return false;
    }
    if (hasCurrentPasswordField(document)) {
      return true;
    }
    if (visiblePasswordFields().length >= 2) {
      return true;
    }
    if (isChangePasswordPageContext()) {
      return true;
    }
    if (pageLooksLikePasswordReset()) {
      return true;
    }

    const autocomplete = (field.getAttribute("autocomplete") || "").toLowerCase();
    return autocomplete === "new-password";
  }

  /** Returns visible password inputs on the page (ignores hidden fields). */
  function visiblePasswordFields(scope) {
    const root = scope ?? document;
    return [...root.querySelectorAll(PASSWORD_SELECTOR)].filter((input) => isFieldLive(input));
  }

  /** Page path/title context — SPAs often omit a wrapping <form>. */
  function pageContextHaystack() {
    return `${window.location.pathname} ${window.location.hash} ${document.title}`.toLowerCase();
  }

  function pageLooksLikeLogin() {
    const haystack = pageContextHaystack();
    return /\/login|\/signin|sign-in|log-in|log_in/.test(haystack);
  }

  function pageLooksLikeSignup() {
    const haystack = pageContextHaystack();
    if (pageLooksLikeLogin() && !/signup|register|create|join|password/.test(haystack)) {
      return false;
    }
    return /signup|sign-up|sign_up|register|registration|create.?account|create-account|join|get.?started|get-started|set.?password|choose.?password|create.?password/.test(
      haystack
    );
  }

  function hasCurrentPasswordField(scope) {
    const root = scope ?? document;
    return Boolean(
      root.querySelector(
        'input[autocomplete="current-password"], input[name*="current" i][type="password"]'
      )
    );
  }

  function findConfirmPasswordField(passwordField) {
    const root = passwordField.form ?? document;
    return root.querySelector(
      'input[autocomplete="new-password"], input[name*="confirm" i][type="password"]'
    );
  }

  function passwordFieldLabelHaystack(passwordField) {
    const id = passwordField.getAttribute("id");
    if (id) {
      const label = document.querySelector(`label[for="${CSS.escape(id)}"]`);
      if (label?.textContent) {
        return label.textContent.toLowerCase();
      }
    }
    return `${passwordField.getAttribute("aria-label") ?? ""} ${passwordField.placeholder ?? ""}`.toLowerCase();
  }

  function pageHasSignupCopy() {
    const bodyText = (document.body?.innerText ?? "").slice(0, 5000).toLowerCase();
    if (/already have an account|sign in instead|log in instead|existing account/.test(bodyText)) {
      return true;
    }
    return /create (your|an|a)? account|create account|sign up for|register for free|get started free|set (your|a)? password|choose (your|a)? password|sign up to|join .+ today|start for free/.test(
      bodyText
    );
  }

  function markSignupFlowActive(origin) {
    try {
      sessionStorage.setItem(`${SIGNUP_FLOW_CACHE_PREFIX}${origin}`, "1");
    } catch {
      // Ignore storage failures in private modes.
    }
  }

  function isSignupFlowActive(origin) {
    try {
      return sessionStorage.getItem(`${SIGNUP_FLOW_CACHE_PREFIX}${origin}`) === "1";
    } catch {
      return false;
    }
  }

  function clearSignupFlowActive(origin) {
    try {
      sessionStorage.removeItem(`${SIGNUP_FLOW_CACHE_PREFIX}${origin}`);
    } catch {
      // Ignore storage failures in private modes.
    }
  }

  /** Detects multi-step or same-page sign-up when URL alone looks like log-in (e.g. Mistral). */
  function looksLikeSignupStep(passwordField) {
    if (pageLooksLikeSignup() || pageHasSignupCopy()) {
      return true;
    }

    const autocomplete = (passwordField.getAttribute("autocomplete") || "").toLowerCase();
    if (autocomplete === "new-password") {
      return true;
    }
    if (autocomplete === "current-password" || hasCurrentPasswordField(document)) {
      return false;
    }

    const labelHaystack = passwordFieldLabelHaystack(passwordField);
    if (/create|choose|set|pick|enter/.test(labelHaystack) && /password/.test(labelHaystack)) {
      return true;
    }

    const origin = window.location.origin;
    const cachedEmail = readCachedLoginIdentifier(origin);
    const liveEmail = resolveLoginIdentifier(passwordField);
    const hasEmailContext = Boolean(
      (cachedEmail && isEmailAddress(cachedEmail))
      || (liveEmail && isEmailAddress(liveEmail))
    );

    if (!hasEmailContext) {
      return false;
    }

    if (isSignupFlowActive(origin)) {
      return true;
    }

    const bodyText = (document.body?.innerText ?? "").slice(0, 4000).toLowerCase();
    if (/welcome back|sign in to|log in to|log into/.test(bodyText)) {
      return false;
    }

    if (hasEmailContext && visiblePasswordFields().length === 1) {
      return /sign up|signup|register|create (your|an|a)? account|get started|join now/.test(bodyText);
    }

    return false;
  }

  /** Detects sign-up, log-in, or change-password from field and form context (W4.3). */
  function detectFormMode(passwordField) {
    const autocomplete = (passwordField.getAttribute("autocomplete") || "").toLowerCase();
    const pagePasswordFields = visiblePasswordFields();

    if (isChangePasswordPageContext()) {
      if (autocomplete === "new-password" || pagePasswordFields.length >= 2) {
        return "changePassword";
      }
      return "login";
    }

    if (pageLooksLikePasswordReset()) {
      if (autocomplete === "new-password" || pagePasswordFields.length >= 2) {
        return "changePassword";
      }
    }

    const form = passwordField.form;

    if (form) {
      const haystack = `${form.getAttribute("action") ?? ""} ${form.id ?? ""} ${form.className ?? ""}`.toLowerCase();
      const hasCurrentPassword = hasCurrentPasswordField(form);

      if (
        (hasCurrentPassword && autocomplete === "new-password")
        || /change.?password|reset.?password|update.?password|forgot.?password|new.?password/.test(haystack)
      ) {
        return "changePassword";
      }

      const confirmField = findConfirmPasswordField(passwordField);
      if (confirmField && confirmField !== passwordField && autocomplete !== "current-password") {
        return "signup";
      }

      if (/signup|sign-up|register|create.?account|join/.test(haystack)) {
        return "signup";
      }
    }

    // SPA / multi-step sign-up — confirm field or second password elsewhere on the page.
    const documentConfirmField = findConfirmPasswordField(passwordField);
    if (
      documentConfirmField
      && documentConfirmField !== passwordField
      && autocomplete !== "current-password"
      && !hasCurrentPasswordField(document)
    ) {
      return "signup";
    }

    if (
      pagePasswordFields.length >= 2
      && !hasCurrentPasswordField(document)
      && autocomplete !== "current-password"
    ) {
      return "signup";
    }

    if (autocomplete === "new-password") {
      return "signup";
    }

    const fieldHaystack = `${passwordField.name ?? ""} ${passwordField.id ?? ""} ${passwordFieldLabelHaystack(passwordField)}`;
    if (/new|signup|register|create|choose/.test(fieldHaystack.toLowerCase()) && autocomplete !== "current-password") {
      return "signup";
    }

    if (pageLooksLikeSignup() && autocomplete !== "current-password") {
      return "signup";
    }

    if (pageHasSignupCopy() && autocomplete !== "current-password" && !hasCurrentPasswordField(document)) {
      return "signup";
    }

    if (looksLikeSignupStep(passwordField)) {
      return "signup";
    }

    return "login";
  }

  /** Re-detect form intent at verify/autofill time; never rotate stored passwords on log-in. */
  async function resolveFormMode(field) {
    let mode = detectFormMode(field);

    let hasCredential = false;
    try {
      const check = await sendMessageWithRetry({
        type: "CHECK_CREDENTIAL",
        origin: window.location.origin,
      });
      hasCredential = Boolean(check?.hasCredential);
    } catch (error) {
      debugLog("resolveFormMode: credential check failed", error);
    }

    if (hasCredential && shouldTreatAsStoredCredentialLogin(field, mode)) {
      mode = "login";
      debugLog("resolveFormMode: stored credential — treating as log-in reuse");
      panel.setFormMode(mode);
      return mode;
    }

    if (!hasCredential && (mode === "login" || mode === "changePassword")) {
      const clearlyLoginPage =
        mode === "login"
        && pageLooksLikeLogin()
        && !pageLooksLikeSignup()
        && !pageHasSignupCopy()
        && !looksLikeSignupStep(field);
      const clearlyChangeWithStoredPassword = mode === "changePassword" && hasCurrentPasswordField(document);

      if (!clearlyLoginPage && !clearlyChangeWithStoredPassword) {
        if (mode === "changePassword" || pageLooksLikePasswordReset()) {
          mode = "signup";
          debugLog("resolveFormMode: password reset without stored credential → sign-up generation");
        } else {
          mode = "signup";
          debugLog("resolveFormMode: no Mac credential — treating as sign-up");
        }
      }
    }

    panel.setFormMode(mode);
    return mode;
  }

  let siteFieldReadOnlyRestore = null;
  const wiredPasswordFields = new WeakSet();

  function lockSitePasswordField(field) {
    if (siteFieldReadOnlyRestore === null) {
      siteFieldReadOnlyRestore = field.readOnly;
    }
    field.readOnly = true;
  }

  function unlockSitePasswordField(field) {
    if (!field) return;
    if (siteFieldReadOnlyRestore !== null) {
      field.readOnly = siteFieldReadOnlyRestore;
      siteFieldReadOnlyRestore = null;
    }
  }

  function deactivateSession(field) {
    cancelPanelDismiss();
    panel.masterInput?.removeEventListener("input", onMasterInputChange);
    panel.masterInput?.removeEventListener("keyup", onMasterInputChange);
    capture.detach();
    if (field?.isConnected) {
      unlockSitePasswordField(field);
    } else {
      siteFieldReadOnlyRestore = null;
    }
    panel.hide();
    if (fieldBadge.anchorField === field) {
      fieldBadge.hide();
    }
    if (field) {
      snoozedFields.delete(field);
    }
    activeField = null;
  }

  function relaunchFromBadge(field) {
    if (!isFieldLive(field)) {
      snoozedFields.delete(field);
      fieldBadge.hide();
      return;
    }

    clearPagePasswordSnooze();
    fieldBadge.hide();
    activateField(field);
  }

  /** Marks every live password field on the page as snoozed so Not Now applies to the whole form. */
  function snoozeAllVisiblePasswordFields() {
    visiblePasswordFields().forEach((input) => {
      snoozedFields.add(input);
    });
  }

  /** Clears page-wide snooze when the user explicitly re-opens DynamicKey from a field badge. */
  function clearPagePasswordSnooze() {
    visiblePasswordFields().forEach((input) => {
      snoozedFields.delete(input);
    });
  }

  function snoozeSession(field) {
    cancelPanelDismiss();
    panel.masterInput?.removeEventListener("input", onMasterInputChange);
    panel.masterInput?.removeEventListener("keyup", onMasterInputChange);
    capture.detach();
    unlockSitePasswordField(field);
    panel.hide();
    activeField = null;
    snoozeAllVisiblePasswordFields();
    fieldBadge.show(field, () => relaunchFromBadge(field));
  }

  async function neverOnThisWebsite(field) {
    panel.setState("verifying");
    panel.messageEl.textContent = "Updating allowed websites…";
    try {
      await sendMessageWithRetry({
        type: "ALLOWLIST_IGNORE",
        origin: window.location.origin,
      });
      deactivateSession(field);
    } catch (error) {
      panel.setError(error instanceof Error ? error.message : "Could not update allowed websites.");
    }
  }

  const capture = new KeystrokeCapture();
  const panel = new DynamicKeyPanel();
  const fieldBadge = new FieldLaunchBadge();
  const snoozedFields = new WeakSet();
  let activeField = null;
  let lastVerificationRequestId = null;
  let panelDismissTimer = null;
  let overlaySyncTimer = null;
  let passwordFieldDetector = null;

  /** Hides the snoozed badge and auth panel when password fields leave the page. */
  function syncPasswordFieldOverlay() {
    passwordFieldDetector?.rescan();

    const hasVisiblePasswordFields = visiblePasswordFields().length > 0;

    if (fieldBadge.anchorField && !isFieldLive(fieldBadge.anchorField)) {
      const stale = fieldBadge.anchorField;
      snoozedFields.delete(stale);
      fieldBadge.hide();
    }

    if (!hasVisiblePasswordFields) {
      if (fieldBadge.anchorField) {
        fieldBadge.hide();
      }
      if (activeField) {
        deactivateSession(activeField);
      } else if (panel.host.isConnected) {
        cancelPanelDismiss();
        panel.hide();
      }
      return;
    }

    if (activeField && !isFieldLive(activeField)) {
      deactivateSession(activeField);
    }
  }

  function scheduleOverlaySync() {
    if (overlaySyncTimer !== null) {
      window.clearTimeout(overlaySyncTimer);
    }
    overlaySyncTimer = window.setTimeout(() => {
      overlaySyncTimer = null;
      syncPasswordFieldOverlay();
    }, 150);
  }

  function cancelPanelDismiss() {
    if (panelDismissTimer !== null) {
      window.clearTimeout(panelDismissTimer);
      panelDismissTimer = null;
    }
  }

  function schedulePanelDismiss(delayMs) {
    cancelPanelDismiss();
    panelDismissTimer = window.setTimeout(() => {
      if (activeField) {
        deactivateSession(activeField);
      } else {
        panel.hide();
      }
      panelDismissTimer = null;
    }, delayMs);
  }

  async function getOnboardingSeenOrigins() {
    const result = await browserAPI.storage.local.get(ONBOARDING_STORAGE_KEY);
    const list = result[ONBOARDING_STORAGE_KEY];
    return Array.isArray(list) ? list : [];
  }

  async function markOnboardingSeen(origin) {
    const seen = await getOnboardingSeenOrigins();
    if (seen.includes(origin)) return;
    seen.push(origin);
    await browserAPI.storage.local.set({ [ONBOARDING_STORAGE_KEY]: seen });
  }

  async function shouldShowOnboarding(origin, credentialCreated) {
    if (credentialCreated) return true;
    const seen = await getOnboardingSeenOrigins();
    return !seen.includes(origin);
  }

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

  async function sendMessageWithRetry(message, attempts = 3) {
    let lastError = null;
    for (let index = 0; index < attempts; index += 1) {
      try {
        return await sendMessage(message);
      } catch (error) {
        lastError = error;
        await new Promise((resolve) => setTimeout(resolve, 120));
      }
    }
    throw lastError ?? new Error("Could not reach extension background.");
  }

  async function canVerifyOnThisPage() {
    const snapshot = await sendMessageWithRetry({ type: "GET_SNAPSHOT" });
    return snapshot.state === "connected" && Boolean(snapshot.session);
  }

  /** Retries Mac connection briefly so a slow wake does not block sign-up with a dead-end error. */
  async function waitForMacConnection(attempts = 5, delayMs = 450) {
    for (let attempt = 0; attempt < attempts; attempt += 1) {
      if (await canVerifyOnThisPage()) {
        return true;
      }
      if (attempt < attempts - 1) {
        await new Promise((resolve) => window.setTimeout(resolve, delayMs));
      }
    }
    return false;
  }

  function canSubmitVerification() {
    return panel.getMasterPassword().length > 0 && capture.exportSamples().length > 0;
  }

  function updateVerifyButtonState() {
    panel.setVerifyEnabled(canSubmitVerification());
  }

  function clearMasterInputForRetry() {
    panel.clearMasterInput();
    capture.reset();
    updateVerifyButtonState();
    panel.focusMasterInput();
  }

  async function resetLockoutForTesting(field) {
    panel.setState("verifying");
    panel.messageEl.textContent = "Resetting lockout…";
    try {
      await sendMessageWithRetry({ type: "RESET_LOCKOUT" });
      panel.showResetLockout(false);
      panel.setState("ready");
      clearMasterInputForRetry();
    } catch (error) {
      panel.setError(error instanceof Error ? error.message : "Could not reset lockout.");
    }
  }

  function dismissProtectedPrompt(field) {
    cancelPanelDismiss();
    panel.hide();
    snoozeAllVisiblePasswordFields();
    fieldBadge.show(field, () => relaunchFromBadge(field));
  }

  function beginProtectedSession(field) {
    activeField = field;
    lockSitePasswordField(field);
    beginVerifyFlow(field);
  }

  async function activateField(field) {
    if (!isFieldLive(field)) {
      snoozedFields.delete(field);
      fieldBadge.hide();
      return;
    }

    if (fieldBadge.anchorField === field) {
      fieldBadge.hide();
    }
    snoozedFields.delete(field);

    if (activeField && activeField !== field) {
      deactivateSession(activeField);
    }
    if (activeField === field && panel.host.isConnected && panel.state !== "allowlist" && panel.state !== "error") {
      panel.focusMasterInput();
      return;
    }

    panel.show(field, {
      formMode: detectFormMode(field),
      onVerify: () => submitVerification(field),
      onNotNow: () => {
        if (activeField === field) {
          snoozeSession(field);
        } else {
          dismissProtectedPrompt(field);
        }
      },
      onNeverSite: () => neverOnThisWebsite(field),
      onResetLockout: () => resetLockoutForTesting(field),
      onAutofill: () => autofillSiteLogin(field),
      onContinueLogin: () => continueToSiteLogin(field),
      onAllowSite: () => approveAllowlistAndContinue(field),
    });

    try {
      const ready = await waitForMacConnection();
      if (!ready) {
        panel.showVerifyUI();
        panel.setError(
          "Could not reach DynamicKey on your Mac yet. Open the app, confirm the extension shows Connected, then click this password field again."
        );
        return;
      }

      const allowStatus = await sendMessageWithRetry({
        type: "ALLOWLIST_CHECK",
        origin: window.location.origin,
      });

      if (!allowStatus.allowed) {
        panel.showAllowlistPrompt(allowStatus.normalizedOrigin || window.location.origin);
        return;
      }

      beginProtectedSession(field);
    } catch (error) {
      panel.setError(
        error instanceof Error
          ? error.message
          : "Could not reach the DynamicKey extension background."
      );
    }
  }

  async function beginVerifyFlow(field) {
    await resolveFormMode(field);
    panel.showVerifyUI();
    capture.attach(panel.masterInput);

    panel.masterInput.removeEventListener("input", onMasterInputChange);
    panel.masterInput.removeEventListener("keyup", onMasterInputChange);
    panel.masterInput.addEventListener("input", onMasterInputChange);
    panel.masterInput.addEventListener("keyup", onMasterInputChange);

    panel.setState("ready");
    updateVerifyButtonState();
    panel.focusMasterInput();
  }

  async function approveAllowlistAndContinue(field) {
    panel.setState("verifying");
    panel.messageEl.textContent = "Adding website to Protected Websites…";

    try {
      await sendMessageWithRetry({
        type: "ALLOWLIST_ADD",
        origin: window.location.origin,
      });
      beginProtectedSession(field);
    } catch (error) {
      panel.setError(error instanceof Error ? error.message : "Could not add website to Protected Websites.");
      panel.showAllowlistPrompt(window.location.origin);
    }
  }

  function onMasterInputChange() {
    if (!activeField) return;
    updateVerifyButtonState();
    if (panel.getMasterPassword().length > 0 && capture.exportSamples().length === 0) {
      panel.setHint("Type each character manually — pasted passwords cannot capture rhythm.");
    }
  }

  function setNativeInputValue(field, value) {
    const normalized = String(value ?? "").trim();
    const prototype =
      field instanceof HTMLTextAreaElement
        ? window.HTMLTextAreaElement.prototype
        : window.HTMLInputElement.prototype;
    const nativeSetter = Object.getOwnPropertyDescriptor(prototype, "value")?.set;

    if (nativeSetter) {
      nativeSetter.call(field, normalized);
    } else {
      field.value = normalized;
    }

    // React and other frameworks track input values internally — sync those trackers too.
    const tracker = field._valueTracker;
    if (tracker) {
      tracker.setValue("");
      tracker.setValue(normalized);
    }

    field.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertFromPaste" }));
    field.dispatchEvent(new Event("change", { bubbles: true }));
  }

  function isEmailAddress(value) {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(value ?? "").trim());
  }

  function isEmailLikeInput(input) {
    if (!(input instanceof HTMLInputElement)) {
      return false;
    }
    const type = (input.type || "text").toLowerCase();
    if (type === "email") {
      return true;
    }
    const haystack = `${input.name ?? ""} ${input.id ?? ""} ${input.autocomplete ?? ""} ${input.placeholder ?? ""} ${input.getAttribute("aria-label") ?? ""}`.toLowerCase();
    return /email|e-mail|mail/.test(haystack);
  }

  function isUsernameOnlyInput(input) {
    if (!(input instanceof HTMLInputElement) || isEmailLikeInput(input)) {
      return false;
    }
    const haystack = `${input.name ?? ""} ${input.id ?? ""} ${input.autocomplete ?? ""} ${input.placeholder ?? ""} ${input.getAttribute("aria-label") ?? ""}`.toLowerCase();
    return /username|user.?name|display.?name|nickname|handle/.test(haystack);
  }

  function isLoginIdentifierCandidate(input, passwordField) {
    if (!(input instanceof HTMLInputElement) || input === passwordField) {
      return false;
    }
    const type = (input.type || "text").toLowerCase();
    if (type === "password" || type === "hidden" || type === "checkbox" || type === "radio" || type === "submit" || type === "button") {
      return false;
    }
    return ["text", "email", "tel", ""].includes(type) || isEmailLikeInput(input);
  }

  function collectLoginIdentifierFields(passwordField) {
    const seen = new Set();
    const fields = [];

    const addFields = (root) => {
      if (!root) return;
      root.querySelectorAll("input").forEach((input) => {
        if (!isLoginIdentifierCandidate(input, passwordField) || seen.has(input)) {
          return;
        }
        seen.add(input);
        fields.push(input);
      });
    };

    addFields(passwordField.form);
    addFields(document);

    return fields;
  }

  function scoreLoginIdentifierField(input, passwordField) {
    let score = 0;
    const value = input.value?.trim() ?? "";

    if (value) {
      score += 12;
    }
    if (isEmailAddress(value)) {
      score += 120;
    }
    if (isEmailLikeInput(input)) {
      score += 60;
    }
    if (isUsernameOnlyInput(input)) {
      score -= 35;
    }
    if (passwordField.form && input.form === passwordField.form) {
      score += 8;
    }
    if (isFieldLive(input)) {
      score += 4;
    }

    return score;
  }

  function findBestLoginIdentifierField(passwordField) {
    const candidates = collectLoginIdentifierFields(passwordField);
    if (candidates.length === 0) {
      return null;
    }

    return candidates
      .slice()
      .sort((left, right) => scoreLoginIdentifierField(right, passwordField) - scoreLoginIdentifierField(left, passwordField))[0];
  }

  function cacheLoginIdentifier(origin, value) {
    const normalized = String(value ?? "").trim();
    if (!normalized) {
      return;
    }
    try {
      sessionStorage.setItem(`${LOGIN_IDENTIFIER_CACHE_PREFIX}${origin}`, normalized);
    } catch {
      // Ignore storage failures in private modes.
    }
  }

  function readCachedLoginIdentifier(origin) {
    try {
      return sessionStorage.getItem(`${LOGIN_IDENTIFIER_CACHE_PREFIX}${origin}`)?.trim() || null;
    } catch {
      return null;
    }
  }

  /** Resolves the login identifier to store/fill, preferring email over display username. */
  function resolveLoginIdentifier(passwordField) {
    const origin = window.location.origin;

    collectLoginIdentifierFields(passwordField).forEach((input) => {
      const value = input.value?.trim() ?? "";
      if (value && isEmailAddress(value)) {
        cacheLoginIdentifier(origin, value);
      }
    });

    const field = findBestLoginIdentifierField(passwordField);
    const fieldValue = field?.value?.trim() || "";
    const cached = readCachedLoginIdentifier(origin);

    if (fieldValue && isEmailAddress(fieldValue)) {
      cacheLoginIdentifier(origin, fieldValue);
      return fieldValue;
    }

    if (cached && isEmailAddress(cached)) {
      if (!fieldValue || isUsernameOnlyInput(field) || !isEmailAddress(fieldValue)) {
        return cached;
      }
    }

    if (fieldValue) {
      if (isEmailLikeInput(field)) {
        cacheLoginIdentifier(origin, fieldValue);
      }
      return fieldValue;
    }

    return cached;
  }

  /** Picks the best on-page field to receive the stored login identifier during autofill. */
  function findFieldToFillForIdentifier(passwordField, identifier) {
    if (isEmailAddress(identifier)) {
      const emailCandidates = collectLoginIdentifierFields(passwordField).filter(
        (input) => isEmailLikeInput(input) || isEmailAddress(input.value)
      );
      if (emailCandidates.length > 0) {
        return emailCandidates
          .slice()
          .sort((left, right) => scoreLoginIdentifierField(right, passwordField) - scoreLoginIdentifierField(left, passwordField))[0];
      }
    }

    return findBestLoginIdentifierField(passwordField);
  }

  function wireLoginIdentifierCapture() {
    const captureIdentifier = (event) => {
      const target = event.target;
      if (!(target instanceof HTMLInputElement)) {
        return;
      }
      const value = target.value?.trim() ?? "";
      if (!value) {
        return;
      }
      if (isEmailAddress(value) || isEmailLikeInput(target)) {
        cacheLoginIdentifier(window.location.origin, value);
        if (visiblePasswordFields().length === 0) {
          markSignupFlowActive(window.location.origin);
        }
      }
    };

    document.addEventListener("input", captureIdentifier, true);
    document.addEventListener("change", captureIdentifier, true);
    document.addEventListener("blur", captureIdentifier, true);
  }

  function findUsernameField(passwordField) {
    return findBestLoginIdentifierField(passwordField);
  }

  function findPasswordFieldsToFill(primaryField) {
    const fields = [primaryField];
    if (!primaryField.form) return fields;

    primaryField.form
      .querySelectorAll('input[type="password"], input[autocomplete="new-password"]')
      .forEach((input) => {
        if (input instanceof HTMLInputElement && input !== primaryField && !fields.includes(input)) {
          fields.push(input);
        }
      });
    return fields;
  }

  /** Classifies a change-password field as current, new, or unknown from autocomplete and labels. */
  function classifyChangePasswordField(field) {
    const autocomplete = (field.getAttribute("autocomplete") || "").toLowerCase();
    const haystack = `${field.name ?? ""} ${field.id ?? ""} ${field.getAttribute("aria-label") ?? ""} ${field.getAttribute("placeholder") ?? ""}`.toLowerCase();
    const labelText = findAssociatedLabelText(field).toLowerCase();
    const combined = `${haystack} ${labelText}`;

    if (
      autocomplete === "current-password"
      || /\b(current|old|existing|nåværende|gjeldende|gammelt?)\b/.test(combined)
    ) {
      return "current";
    }
    if (
      autocomplete === "new-password"
      || /\b(new|confirm|repeat|verify|bekreft|nytt|ny)\b/.test(combined)
    ) {
      return "new";
    }
    return "unknown";
  }

  /** Reads visible label text linked to an input for locale-aware field classification. */
  function findAssociatedLabelText(field) {
    if (field.id) {
      const byFor = document.querySelector(`label[for="${CSS.escape(field.id)}"]`);
      if (byFor?.textContent) {
        return byFor.textContent.trim();
      }
    }

    const wrapped = field.closest("label");
    if (wrapped?.textContent) {
      return wrapped.textContent.trim();
    }

    const labelledBy = field.getAttribute("aria-labelledby");
    if (labelledBy) {
      return labelledBy
        .split(/\s+/)
        .map((id) => document.getElementById(id)?.textContent?.trim() ?? "")
        .filter(Boolean)
        .join(" ");
    }

    return field.getAttribute("aria-label")?.trim() ?? "";
  }

  /** Fills change-password forms: current field gets stored password, new/confirm fields get the generated password. */
  function findChangePasswordFields(primaryField) {
    const inForm = primaryField.form
      ? [...primaryField.form.querySelectorAll('input[type="password"]')].filter(
          (input) => input instanceof HTMLInputElement
        )
      : [];

    if (inForm.length >= 2) {
      return inForm;
    }

    const visiblePageFields = [...document.querySelectorAll('input[type="password"]')].filter((input) => {
      if (!(input instanceof HTMLInputElement) || input.disabled) return false;
      const style = window.getComputedStyle(input);
      return style.display !== "none" && style.visibility !== "hidden";
    });

    return visiblePageFields.length >= 2 ? visiblePageFields : [primaryField];
  }

  function fillChangePasswordForm(primaryField, credentials) {
    const passwordFields = findChangePasswordFields(primaryField);

    const currentPassword = String(credentials.currentPassword ?? credentials.password ?? "").trim();
    const newPassword = String(credentials.password ?? "").trim();
    const roles = passwordFields.map((field) => classifyChangePasswordField(field));
    const hasExplicitCurrent = roles.includes("current");
    const hasExplicitNew = roles.includes("new");

    passwordFields.forEach((field, index) => {
      let value = newPassword;
      const role = roles[index];

      if (role === "current") {
        value = currentPassword;
      } else if (role === "new") {
        value = newPassword;
      } else if (passwordFields.length >= 2) {
        if (!hasExplicitCurrent && !hasExplicitNew) {
          value = index === 0 ? currentPassword : newPassword;
        } else if (!hasExplicitCurrent && index === 0) {
          value = currentPassword;
        }
      }

      setNativeInputValue(field, value);
    });

    return passwordFields;
  }

  /** Finds the website's primary submit control for log-in flows. */
  function findSiteLoginButton(passwordField) {
    const form = passwordField.form;
    if (form) {
      const inForm = form.querySelector(
        'button[type="submit"], input[type="submit"], button:not([type="button"]):not([type="reset"])'
      );
      if (inForm instanceof HTMLElement) {
        return inForm;
      }
    }

    const candidates = [...document.querySelectorAll("button, input[type='submit'], [role='button']")];
    return candidates.find((element) => {
      if (!(element instanceof HTMLElement)) return false;
      const label = `${element.textContent ?? ""} ${element.getAttribute("value") ?? ""} ${element.getAttribute("aria-label") ?? ""}`;
      return /log\s*in|sign\s*in|continue|next|submit/i.test(label);
    }) ?? null;
  }

  /** Clicks the site login button or submits the password form when possible. */
  function trySubmitSiteLogin(passwordField) {
    const loginButton = findSiteLoginButton(passwordField);
    if (loginButton instanceof HTMLElement) {
      loginButton.click();
      return true;
    }

    const form = passwordField.form;
    if (!form) return false;

    if (typeof form.requestSubmit === "function") {
      form.requestSubmit();
      return true;
    }

    if (typeof form.submit === "function") {
      form.submit();
      return true;
    }

    return false;
  }

  function continueToSiteLogin(passwordField) {
    cancelPanelDismiss();
    trySubmitSiteLogin(passwordField);
    deactivateSession(passwordField);
  }

  function scheduleAutoSiteLogin(passwordField) {
    window.setTimeout(() => {
      if (activeField !== passwordField || panel.state !== "granted") return;
      if (trySubmitSiteLogin(passwordField)) {
        deactivateSession(passwordField);
        return;
      }
      panel.showContinueLogin(true);
      schedulePanelDismiss(GRANTED_SUCCESS_DISMISS_MS);
    }, GRANTED_LOGIN_AUTO_SUBMIT_MS);
  }

  function finishGrantedSuccess(passwordField, options = {}) {
    const { autoSubmitLogin = false } = options;
    schedulePanelDismiss(GRANTED_SUCCESS_DISMISS_MS);
    if (autoSubmitLogin) {
      scheduleAutoSiteLogin(passwordField);
    }
  }

  function finishAutofillSuccess(passwordField, verifyResult, showOnboarding, fillResult) {
    panel.showAutofill(false);
    panel.setState("granted");
    panel.showGrantedCompactUI();
    panel.messageEl.className = "message granted";

    if (verifyResult.credentialCreated || panel.formMode === "signup") {
      clearSignupFlowActive(window.location.origin);
    }

    if (panel.formMode === "login") {
      if (showOnboarding) {
        panel.messageEl.textContent =
          `Access granted (${verifyResult.matchPercentage}%). Site password filled — continuing to log in…`;
      } else {
        panel.messageEl.textContent = "Access granted. Site password filled.";
      }
      finishGrantedSuccess(passwordField, { autoSubmitLogin: true });
      return;
    }

    if (showOnboarding) {
      if (panel.formMode === "changePassword" && fillResult?.credentialCreated) {
        panel.messageEl.textContent =
          `Access granted (${verifyResult.matchPercentage}%). Your current password was filled in the first field; a new site password was generated for the remaining fields.`;
      } else if (verifyResult.credentialCreated) {
        panel.messageEl.textContent =
          `Access granted (${verifyResult.matchPercentage}%). A strong site password was saved on your Mac and filled here.`;
      } else {
        panel.messageEl.textContent =
          `Access granted (${verifyResult.matchPercentage}%). Your site login was filled from your Mac.`;
      }
      if (panel.formMode === "changePassword") {
        finishGrantedSuccess(passwordField);
      } else {
        finishGrantedSuccess(passwordField);
      }
      return;
    }

    panel.messageEl.textContent = "Access granted. Site password filled.";
    if (panel.formMode === "changePassword") {
      finishGrantedSuccess(passwordField);
      return;
    }
    finishGrantedSuccess(passwordField);
  }

  function highlightAutofilledFields(...fields) {
    fields.filter(Boolean).forEach((field) => {
      field.style.boxShadow = "0 0 0 3px rgba(74, 222, 128, 0.55)";
      field.style.transition = "box-shadow 0.2s ease";
      window.setTimeout(() => {
        field.style.boxShadow = "";
      }, 3500);
    });
  }

  async function performAutofill(passwordField) {
    if (!lastVerificationRequestId) {
      return { ok: false, error: "Verify your rhythm first." };
    }

    const username = resolveLoginIdentifier(passwordField);

    try {
      const formIntent = await resolveFormMode(passwordField);
      const result = await sendMessageWithRetry({
        type: "FILL_APPROVE",
        origin: window.location.origin,
        verificationRequestId: lastVerificationRequestId,
        username,
        formIntent,
        rotateSitePassword: shouldRotateSitePassword(passwordField, formIntent),
      });

      if (!result.approved) {
        return { ok: false, error: result.message ?? "Autofill was not approved. Verify again first." };
      }

      if (!result.credentials) {
        return {
          ok: false,
          error: `No site login is available for ${window.location.origin}. Verify again so your Mac app can generate one.`,
        };
      }

      const identifierField = findFieldToFillForIdentifier(passwordField, result.credentials.username);
      if (identifierField && result.credentials.username) {
        setNativeInputValue(identifierField, result.credentials.username);
      }

      let passwordFields;
      if (panel.formMode === "changePassword") {
        passwordFields = fillChangePasswordForm(passwordField, result.credentials);
      } else {
        passwordFields = findPasswordFieldsToFill(passwordField);
        passwordFields.forEach((field) => {
          setNativeInputValue(field, result.credentials.password);
        });
      }

      highlightAutofilledFields(identifierField, ...passwordFields);

      debugLog("autofill complete", passwordFields.length, "password field(s)");

      return {
        ok: true,
        passwordLength: result.credentials.password.length,
        username: result.credentials.username,
        credentialCreated: panel.formMode === "changePassword",
      };
    } catch (error) {
      return {
        ok: false,
        error: error instanceof Error ? error.message : "Autofill failed.",
      };
    }
  }

  async function autofillSiteLogin(passwordField) {
    cancelPanelDismiss();
    panel.setState("verifying");
    panel.messageEl.textContent = "Filling site login from your Mac…";

    const fillResult = await performAutofill(passwordField);

    if (!fillResult.ok) {
      panel.showVerifyUI();
      panel.setError(fillResult.error ?? "Autofill failed.");
      panel.showAutofill(true);
      return;
    }

    panel.showAutofill(false);
    panel.setState("granted");
    panel.showGrantedCompactUI();
    panel.messageEl.textContent = `Site login filled (${fillResult.passwordLength} characters).`;
    panel.messageEl.className = "message granted";

    if (panel.formMode === "login") {
      finishGrantedSuccess(passwordField, { autoSubmitLogin: true });
    } else if (panel.formMode === "changePassword") {
      finishGrantedSuccess(passwordField);
    } else {
      finishGrantedSuccess(passwordField);
    }
  }

  async function autoFillAfterGrant(field, verifyResult) {
    const showOnboarding = await shouldShowOnboarding(
      window.location.origin,
      Boolean(verifyResult.credentialCreated)
    );

    panel.setState("verifying");
    panel.messageEl.textContent = "Filling site login from your Mac…";

    const fillResult = await performAutofill(field);

    if (!fillResult.ok) {
      panel.showVerifyUI();
      panel.setError(fillResult.error ?? "Autofill failed. Tap Retry autofill.");
      panel.showAutofill(true);
      return;
    }

    await markOnboardingSeen(window.location.origin);
    finishAutofillSuccess(field, verifyResult, showOnboarding, fillResult);
  }

  async function submitVerification(field) {
    if (!canSubmitVerification()) {
      panel.setError("Type your master password at normal speed, then press Enter.");
      return;
    }

    const password = panel.getMasterPassword();
    const keystrokes = capture.exportSamples();
    const username = resolveLoginIdentifier(field);
    panel.setState("verifying");

    const formIntent = await resolveFormMode(field);

    try {
      const result = await sendMessageWithRetry({
        type: "VERIFY_LOGIN",
        origin: window.location.origin,
        password,
        keystrokes,
        username,
        formIntent,
      });

      if (result.granted) {
        lastVerificationRequestId = result.requestId;
        debugLog("verify granted", result.matchPercentage, formIntent);
        panel.clearMasterInput();
        capture.reset();
        unlockSitePasswordField(field);

        if (result.missingSiteCredential) {
          panel.setState("granted");
          panel.showGrantedCompactUI();
          panel.messageEl.textContent =
            `Access granted (${result.matchPercentage}%), but no site password is saved for this website yet. Sign up on this site with DynamicKey first, or add credentials in Mac Settings.`;
          panel.messageEl.className = "message granted";
          schedulePanelDismiss(GRANTED_SUCCESS_DISMISS_MS);
          return;
        }

        if (result.siteCredentialReady === false) {
          panel.setError("Access granted, but no site password is available to fill.");
          return;
        }

        await autoFillAfterGrant(field, result);
      } else {
        lastVerificationRequestId = null;
        panel.showAutofill(false);
        if (result.denialReason === "lockedOut") {
          panel.showResetLockout(true);
          const seconds = result.lockoutRemainingSeconds ?? 0;
          panel.setError(`Too many failed attempts. Try again in ${seconds}s.`);
          clearMasterInputForRetry();
        } else if (result.denialReason === "untrustedContext") {
          clearMasterInputForRetry();
          panel.setState("ready");
          panel.messageEl.textContent =
            "Trusted device required. Add this keyboard or Wi‑Fi in DynamicKey Settings → Trusted Keyboards / Trusted Networks, then try again.";
          panel.messageEl.className = "message denied";
        } else {
          clearMasterInputForRetry();
          panel.setState("ready");
          panel.messageEl.textContent = `Access denied — rhythm match ${result.matchPercentage}%. Type your master password again, then press Enter.`;
          panel.messageEl.className = "message denied";
        }
      }
    } catch (error) {
      panel.setError(error instanceof Error ? error.message : "Verification failed.");
      clearMasterInputForRetry();
    } finally {
      if (panel.state !== "denied" && panel.state !== "error") {
        capture.reset();
        updateVerifyButtonState();
      }
    }
  }

  function wirePasswordField(field) {
    if (wiredPasswordFields.has(field)) {
      return true;
    }

    const begin = () => {
      const mode = detectFormMode(field);
      if (isFixPasswordAssistActive() && mode === "signup") {
        debugLog("Fix It assist — ignoring sign-up field focus.");
        return;
      }

      if (snoozedFields.has(field)) {
        if (isFieldLive(field)) {
          fieldBadge.show(field, () => relaunchFromBadge(field));
        } else {
          snoozedFields.delete(field);
        }
        return;
      }

      if (activeField && activeField !== field) {
        deactivateSession(activeField);
      }
      if (activeField === field && panel.host.isConnected) {
        panel.focusMasterInput();
        return;
      }
      activateField(field);
    };

    field.addEventListener("focus", begin);
    field.addEventListener("click", begin);

    field.addEventListener("keydown", (event) => {
      if (activeField !== field) return;
      if (panel.state === "allowlist") return;
      if (event.key === "Tab") return;
      event.preventDefault();
      panel.focusMasterInput();
    });

    field.addEventListener("paste", (event) => {
      if (activeField !== field) return;
      event.preventDefault();
    });

    field.addEventListener("blur", () => {
      window.setTimeout(() => {
        if (activeField !== field) return;
        if (snoozedFields.has(field)) return;
        if (panel.containsFocus()) return;
        if (panel.shouldKeepVisible()) return;
        deactivateSession(field);
      }, 200);
    });

    wiredPasswordFields.add(field);
    return true;
  }

  passwordFieldDetector = new PasswordFieldDetector((field) => wirePasswordField(field));
  wireLoginIdentifierCapture();
  passwordFieldDetector.start();

  window.addEventListener("popstate", scheduleOverlaySync);
  window.addEventListener("hashchange", scheduleOverlaySync);
  window.addEventListener("pageshow", scheduleOverlaySync);

  const FIX_PASSWORD_HASH = "dynamickey-fix-password";
  const FIX_PASSWORD_QUERY = "dynamickey-fix";
  const FIX_PASSWORD_SESSION_KEY = "keystrokeauth.fixPasswordAssist";
  let fixPasswordBannerEl = null;

  /** Reads Fix It signal from query (preferred), legacy hash, or sessionStorage; strips URL so SPAs load. */
  function consumeFixPasswordSignal() {
    const params = new URLSearchParams(location.search);
    if (params.get(FIX_PASSWORD_QUERY) === "1") {
      sessionStorage.setItem(FIX_PASSWORD_SESSION_KEY, "1");
      params.delete(FIX_PASSWORD_QUERY);
      const nextSearch = params.toString();
      const nextUrl = `${location.pathname}${nextSearch ? `?${nextSearch}` : ""}${location.hash}`;
      history.replaceState(null, "", nextUrl);
      return true;
    }

    const legacyHash = (location.hash || "").replace(/^#/, "");
    if (legacyHash === FIX_PASSWORD_HASH) {
      sessionStorage.setItem(FIX_PASSWORD_SESSION_KEY, "1");
      history.replaceState(null, "", `${location.pathname}${location.search}`);
      return true;
    }

    return sessionStorage.getItem(FIX_PASSWORD_SESSION_KEY) === "1";
  }

  function isFixPasswordAssistActive() {
    return sessionStorage.getItem(FIX_PASSWORD_SESSION_KEY) === "1";
  }

  function fixPasswordBannerMessage() {
    const onChangePage = isChangePasswordPageContext();
    const changeFormVisible = visiblePasswordFields().length >= 2;
    if (onChangePage && changeFormVisible) {
      return "DynamicKey Fix It: select a password field — DynamicKey will verify your rhythm. Your current password fills the first field; a new password is generated for the remaining fields.";
    }
    if (onChangePage) {
      return "DynamicKey Fix It: log in to this site first if prompted — click the password field and verify with DynamicKey to autofill your saved login. Then complete the change-password form.";
    }
    return "DynamicKey Fix It: log in to this site if prompted, then open Change password in account settings. DynamicKey will assist when you reach the change-password form.";
  }

  /** LeakPeek Fix It — banner + focus when Mac opens with ?dynamickey-fix=1 (W5). */
  function activateFixPasswordAssist() {
    if (!consumeFixPasswordSignal() && !isFixPasswordAssistActive()) {
      if (fixPasswordBannerEl) {
        fixPasswordBannerEl.remove();
        fixPasswordBannerEl = null;
      }
      return;
    }

    if (!fixPasswordBannerEl) {
      fixPasswordBannerEl = document.createElement("div");
      fixPasswordBannerEl.id = "keystrokeauth-fix-banner";
      fixPasswordBannerEl.setAttribute("role", "status");
      Object.assign(fixPasswordBannerEl.style, {
        position: "fixed",
        top: "12px",
        left: "50%",
        transform: "translateX(-50%)",
        zIndex: "2147483646",
        maxWidth: "min(520px, calc(100vw - 24px))",
        padding: "12px 16px",
        borderRadius: "12px",
        background: "rgba(20, 22, 28, 0.92)",
        color: "#f5f5f7",
        font: "13px/1.45 -apple-system, BlinkMacSystemFont, sans-serif",
        boxShadow: "0 8px 28px rgba(0,0,0,0.35)",
        border: "1px solid rgba(255,255,255,0.12)",
      });
      document.documentElement.appendChild(fixPasswordBannerEl);
    }

    fixPasswordBannerEl.textContent = fixPasswordBannerMessage();
    // Fields are wired by PasswordFieldDetector — only open the panel when the user focuses a field.
  }

  let fixAssistCheckTimer = null;

  function scheduleFixPasswordAssistCheck() {
    if (fixAssistCheckTimer !== null) {
      window.clearTimeout(fixAssistCheckTimer);
    }
    fixAssistCheckTimer = window.setTimeout(() => {
      fixAssistCheckTimer = null;
      activateFixPasswordAssist();
    }, 300);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", activateFixPasswordAssist);
  } else {
    activateFixPasswordAssist();
  }
  window.addEventListener("hashchange", scheduleFixPasswordAssistCheck);
  window.addEventListener("popstate", scheduleFixPasswordAssistCheck);
})();
