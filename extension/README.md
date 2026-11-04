# DynamicKey Browser Extension (Phase 2)

Chromium extension (Chrome, Edge, Brave) that pairs with the **DynamicKey Mac app** over localhost.

**Current version:** `0.5.6` — DynamicKey rebrand; W4.3 options page; W4.5 Safari support.

> **Note:** Xcode target and bundle IDs remain `DynamicKey` internally; user-facing name is **DynamicKey**.

---

## Extension settings (W4.3)

Open from the popup (**Extension settings**) or browser extension preferences:

- **Pairing** — connect / disconnect / check Mac app
- **Websites & credentials** — managed in Mac app Settings
- **Debug mode** — verbose `[DynamicKey]` logs in page DevTools console

---

## Safari (W4.5)

The Safari extension ships **inside the Mac app** when you build in Xcode. It is **not** the same as Brave/Chrome “Load unpacked” — Safari only updates when you **rebuild the Mac app**.

### Install / update (required after code changes)

1. **Quit Safari completely** (⌘Q — not just close the window).
2. In Xcode: **Product → Clean Build Folder** (⇧⌘K).
3. **Build & Run** the **KeyStrokeAuth** Mac app (⌘R).
4. Open Safari → **Safari → Settings → Extensions**.
5. Turn **KeyStrokeAuth** OFF, wait 2 seconds, turn it ON again.
6. For dev builds: **Safari → Develop → Allow Unsigned Extensions** (if shown).
7. Re-open Gmail/Outlook and hard-refresh the mail tab (⌘R).

### How to know Safari picked up the new build

DynamicShield banner subtitle shows the extension version, e.g. **`v0.9.27`**. If you still see an older version or the old buttons (no **View Report**), Safari is running a cached bundle — repeat the steps above.

### Safari timeout / pairing errors

Safari’s background worker wakes slower than Brave. If the popup shows a timeout or asks to pair again:

1. Confirm the **Mac app is running** (menu bar shows API active).
2. Click the extension icon again — second try often succeeds after the worker wakes.
3. If it persists: Mac app **Settings → Browser Extension → Generate Pairing Code** → enter in popup once.

Reloading the extension in Safari Settings alone **does not** copy new JS from your project — you must **⌘R in Xcode** first.

---

## W4.2 — Allowlist prompt (new sites)

When the Mac app has a **non-empty** allowlist and the current site is not listed:

1. DynamicKey panel asks: **Add to allowed websites?**
2. **Add** → Mac saves origin → master password + verify flow continues
3. **Not now** → panel dismisses; no verify

When allowlist is **empty** in Mac Settings, all sites are allowed (no prompt).

Test: add `http://localhost:8765` in Settings allowlist only, then visit Spotify — you should see the prompt.

---

## W4.1 — Master password overlay (not site field)

When you focus a website password field:

1. DynamicKey panel appears **centered under the field**
2. Type your **master password in the DynamicKey box** — not in the website field
3. Website password field is locked until verify succeeds
4. After verify → site login auto-fills
5. Panel shows **Log in** or **Sign up** tag based on form detection

Test pages:

- `test-login.html` — log in (`current-password`)
- `test-signup.html` — sign up (`new-password`)

After a successful rhythm verify:

1. The Mac app generates (or reuses) a site password for that origin.
2. The extension **automatically fills** username + site password — no extra button.
3. **First visit** per site: brief message that a password was saved on your Mac (~5s), then panel dismisses.
4. **Return visits**: silent auto-fill; panel dismisses quickly.
5. **Retry autofill** button appears only if auto-fill fails.

Manual credential entry in Mac Settings is optional (import/testing).

### Quick W3.5 test

1. Mac app running, extension paired (green dot). Reload extension after update: `chrome://extensions` → **Reload**.
2. Terminal:

   ```bash
   cd /Volumes/Applications/Development/KeyStroleAuth/extension/test
   python3 -m http.server 8765
   ```

3. Open `http://localhost:8765/test-login.html`.
4. Enter a username (optional).
5. Focus password → type **master password** → **Verify typing rhythm**.
6. Site password fills automatically; first visit shows a short Mac-saved message.
7. Refresh and verify again — second visit should auto-fill silently.

---

## W2 — Verify on websites

The extension:

1. Detects password fields on `http://` and `https://` pages
2. Captures dwell/flight timing while you type
3. Shows a **Verify typing rhythm** panel after you focus a password field
4. Sends `/v1/verify` to the Mac app when you click **Verify**

**Important:** verification uses your **DynamicKey master password** and rhythm — not the website login password.

---

## Requirements

1. **DynamicKey Mac app** running on the same computer (M5 local auth API).
2. A **Chromium-based browser** (Chrome recommended for development).
3. A profile enrolled in the Mac app.

---

## Load unpacked (development)

1. Open the Mac app and confirm **Settings → Browser extension** shows the API as running.
2. In Chrome, go to `chrome://extensions`.
3. Enable **Developer mode** (top right).
4. Click **Load unpacked**.
5. Select this folder:

   `KeyStroleAuth/extension`

6. Pin the DynamicKey extension from the puzzle icon.

---

## Pair with the Mac app

1. Mac app → **Log In** → **Settings** → **Browser extension**.
2. Click **Generate Pairing Code** (valid ~10 minutes).
3. Click the extension icon in the browser toolbar.
4. Enter the code → **Connect to Mac App**.
5. Status dot turns **green** when connected.

**Disconnect** clears the token in the extension only. Use **Revoke Pairings** in Mac Settings to invalidate tokens on the Mac side.

---

## Connection states

| Dot | Meaning |
|-----|---------|
| Green | Paired and Mac app reachable with profile |
| Orange | Not paired yet |
| Red | Mac app not running, or connection failed |
| Orange (no profile) | Mac app running but no enrolled profile |

The background worker rechecks health about every 30 seconds.

---

## Project layout

```
extension/
  manifest.json           Manifest V3
  background/
    service-worker.js     Pairing, health checks, storage
  popup/
    popup.html/js/css     Pairing UI + status
  shared/
    config.js             API URL + protocol version
    api.js                fetch helpers for Mac app
    storage.js            chrome.storage.local session
  icons/
```

Protocol details: [`../docs/extension-protocol.md`](../docs/extension-protocol.md)

---

## Browser target (W1.1)

**Now:** Chromium MV3 (fastest path for development).

**Later (W4):** Safari Web Extension packaged with the Xcode Mac app target.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Cannot reach Mac app | Open DynamicKey on this Mac; check menu bar API URL |
| Pairing failed | Generate a new code; codes expire in 10 minutes |
| Connected → disconnected | Mac app quit or **Revoke Pairings**; reconnect |
| Extension errors on load | Confirm you selected the `extension` folder (contains `manifest.json`) |

---

## Next: W4

- Invisible rhythm capture overlay
- Sign-up vs login detection
- Safari Web Extension + store distribution
