// repair-pairing.js
// Shared confirm + labels for disconnecting the current browser and pairing again.

import { detectBrowserFamily, pairingClientNameForFamily } from "./config.js";

/**
 * Asks whether to disconnect only this browser so the user can enter a new pairing code.
 * @returns {Promise<{ confirmed: boolean, browserLabel: string }>}
 */
export async function confirmRepairPairing() {
  const browserFamily = await detectBrowserFamily();
  const browserLabel = pairingClientNameForFamily(browserFamily);
  const confirmed = confirm(
    `Disconnect ${browserLabel} from DynamicKey on this Mac?\n\n`
      + "You can pair again with a new code from the Mac app. Other browsers stay connected."
  );

  return { confirmed, browserLabel };
}
