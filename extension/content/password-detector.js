// password-detector.js
// Finds password inputs on pages, including dynamically added forms (W2.1).
//
// Flow: scan DOM → observe mutations → notify when password fields appear.

const PASSWORD_SELECTOR = [
  'input[type="password"]',
  'input[autocomplete="current-password"]',
  'input[autocomplete="new-password"]',
  'input[name="password" i]',
  'input[id="password" i]',
].join(",");

/**
 * @typedef {(field: HTMLInputElement) => void} PasswordFieldHandler
 */

/**
 * Watches the page for password fields and reports them to a callback.
 */
export class PasswordFieldDetector {
  /**
   * @param {PasswordFieldHandler} onFieldFound
   */
  constructor(onFieldFound) {
    this.onFieldFound = onFieldFound;
    /** @type {WeakSet<HTMLInputElement>} */
    this.seenFields = new WeakSet();
    /** @type {MutationObserver | null} */
    this.observer = null;
  }

  /** Starts DOM scanning and mutation observation. */
  start() {
    this.scan(document);
    this.observer = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        mutation.addedNodes.forEach((node) => {
          if (node instanceof HTMLElement) {
            this.scan(node);
          }
        });
      }
    });
    this.observer.observe(document.documentElement, {
      childList: true,
      subtree: true,
    });
  }

  /** Stops mutation observation. */
  stop() {
    this.observer?.disconnect();
    this.observer = null;
  }

  /**
   * @param {ParentNode} root
   */
  scan(root) {
    if (!(root instanceof ParentNode)) {
      return;
    }

    root.querySelectorAll(PASSWORD_SELECTOR).forEach((element) => {
      if (element instanceof HTMLInputElement && !this.seenFields.has(element)) {
        this.seenFields.add(element);
        this.onFieldFound(element);
      }
    });
  }
}
