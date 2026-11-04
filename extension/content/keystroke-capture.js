// keystroke-capture.js
// Records dwell and flight timing from password field key events (W2.2).
//
// Flow: keydown starts timer → keyup computes dwell → append KeystrokeData sample.

/**
 * @typedef {{ character: string, dwellTime: number, flightTime: number }} KeystrokeSample
 */

/**
 * Captures per-key timing compatible with the Mac app KeystrokeData format.
 */
export class KeystrokeCapture {
  constructor() {
    /** @type {KeystrokeSample[]} */
    this.samples = [];
    /** @type {Map<string, number>} */
    this.keyDownTimes = new Map();
    this.lastKeyUpTime = null;
    this.boundKeyDown = this.onKeyDown.bind(this);
    this.boundKeyUp = this.onKeyUp.bind(this);
    /** @type {HTMLInputElement | null} */
    this.field = null;
  }

  /**
   * Attaches capture listeners to a password input element.
   * @param {HTMLInputElement} field
   */
  attach(field) {
    this.detach();
    this.field = field;
    this.reset();
    field.addEventListener("keydown", this.boundKeyDown, true);
    field.addEventListener("keyup", this.boundKeyUp, true);
  }

  /** Removes listeners and clears timing state. */
  detach() {
    if (this.field) {
      this.field.removeEventListener("keydown", this.boundKeyDown, true);
      this.field.removeEventListener("keyup", this.boundKeyUp, true);
      this.field = null;
    }
    this.reset();
  }

  /** Clears captured samples without removing listeners. */
  reset() {
    this.samples = [];
    this.keyDownTimes.clear();
    this.lastKeyUpTime = null;
  }

  /**
   * @returns {KeystrokeSample[]}
   */
  exportSamples() {
    return this.samples.map((sample) => ({ ...sample }));
  }

  /**
   * @param {KeyboardEvent} event
   */
  onKeyDown(event) {
    if (!this.field) {
      return;
    }

    if (event.key === "Backspace" || event.key === "Delete") {
      if (this.samples.length > 0) {
        this.samples.pop();
      }
      this.lastKeyUpTime = performance.now() / 1000;
      return;
    }

    if (event.key.length !== 1 || event.ctrlKey || event.metaKey || event.altKey) {
      return;
    }

    this.keyDownTimes.set(event.code, performance.now() / 1000);
  }

  /**
   * @param {KeyboardEvent} event
   */
  onKeyUp(event) {
    if (!this.field) {
      return;
    }

    if (event.key === "Backspace" || event.key === "Delete") {
      return;
    }

    if (event.key.length !== 1) {
      return;
    }

    const keyDownTime = this.keyDownTimes.get(event.code);
    if (keyDownTime === undefined) {
      return;
    }

    const keyUpTime = performance.now() / 1000;
    const dwellTime = Math.max(0, keyUpTime - keyDownTime);
    const flightTime =
      this.lastKeyUpTime === null ? 0 : Math.max(0, keyDownTime - this.lastKeyUpTime);

    this.samples.push({
      character: event.key,
      dwellTime,
      flightTime,
    });

    this.keyDownTimes.delete(event.code);
    this.lastKeyUpTime = keyUpTime;
  }
}
