// browser.js
// Cross-browser WebExtensions API shim for Chromium and Safari (W4.5).

/** @type {typeof chrome} */
export const browserAPI = globalThis.browser ?? globalThis.chrome;
