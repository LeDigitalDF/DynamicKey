// async.js
// Small async helpers shared by the popup and background worker.

/**
 * Rejects when a promise does not settle within the allotted time.
 * @template T
 * @param {Promise<T>} promise
 * @param {number} timeoutMs
 * @param {string} [label]
 * @returns {Promise<T>}
 */
export function withTimeout(promise, timeoutMs, label = "Request") {
  let timerId;

  const timeout = new Promise((_, reject) => {
    timerId = setTimeout(() => {
      reject(new Error(`${label} timed out.`));
    }, timeoutMs);
  });

  return Promise.race([promise, timeout]).finally(() => {
    clearTimeout(timerId);
  });
}
