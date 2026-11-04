# KeyStrokeAuth Extension Protocol (v1)

This document defines the **localhost HTTP API** between the KeyStrokeAuth macOS app and the browser extension.

**Transport (M5.1):** HTTP/1.1 on `http://127.0.0.1:17487` only. No TLS (loopback-only). The Mac app binds to loopback and never exposes this port on the LAN.

**Protocol version:** `1`

---

## Security model

1. **Mac app is source of truth** — extension never receives raw rhythm profile data.
2. **Pairing required** — authenticated endpoints need `Authorization: Bearer <accessToken>`.
3. **Origin binding** — verify and fill-approve requests include the website origin.
4. **Local only** — traffic never leaves the machine.
5. **Password in verify body** — sent over loopback for hash + rhythm check; extension must not persist it.

---

## Pairing flow

1. User opens **Settings → Generate Pairing Code** in the Mac app.
2. Mac app stores a short code (8 characters, expires in **10 minutes**).
3. Extension sends `POST /v1/pair` with the code.
4. Mac app returns a long-lived `accessToken` and `clientId`.
5. Extension stores `accessToken` securely (extension storage) and sends it on subsequent requests.

Revoke all pairings from **Settings → Revoke Pairings** or by deleting the Mac profile.

---

## Endpoints

### `GET /v1/status` (no auth)

Health and readiness check.

**Response `200`:**

```json
{
  "protocolVersion": 1,
  "serviceState": "running",
  "hasProfile": true,
  "passThreshold": 70,
  "pairedClientCount": 1,
  "lockoutActive": false,
  "safeModeActive": false,
  "safeModeExpiresAt": null,
  "safeModeRemainingLabel": null,
  "serviceUptimeSeconds": 42
}
```

---

### `POST /v1/pair` (no auth)

Exchange a one-time pairing code for an access token.

**Request:**

```json
{
  "protocolVersion": 1,
  "pairingCode": "AB12CD34",
  "clientName": "Chrome Extension"
}
```

**Response `200`:**

```json
{
  "protocolVersion": 1,
  "accessToken": "uuid",
  "clientId": "uuid",
  "clientName": "Chrome Extension"
}
```

**Errors:** `401 pairing_failed` if code is invalid or expired.

---

### `POST /v1/verify` (auth required)

Verify password + typing rhythm for a website login attempt.

**Headers:**

```
Authorization: Bearer <accessToken>
Content-Type: application/json
```

**Request:**

```json
{
  "protocolVersion": 1,
  "requestId": "550e8400-e29b-41d4-a716-446655440000",
  "origin": "https://example.com",
  "password": "user-typed-password",
  "keystrokes": [
    { "character": "p", "dwellTime": 0.082, "flightTime": 0.0 },
    { "character": "a", "dwellTime": 0.091, "flightTime": 0.044 }
  ],
  "username": "user@example.com",
  "formIntent": "login"
}
```

`formIntent` is optional: `login` (default), `signup`, or `changePassword`. Site passwords are generated only on `signup` or `changePassword`, not on `login`.

**Response `200`:**

```json
{
  "protocolVersion": 1,
  "requestId": "550e8400-e29b-41d4-a716-446655440000",
  "granted": true,
  "matchPercentage": 84,
  "denialReason": null,
  "lockoutRemainingSeconds": null,
  "siteCredentialReady": true,
  "credentialCreated": true,
  "missingSiteCredential": false
}
```

`missingSiteCredential` is `true` when `formIntent` is `login`, access was granted, but no site password exists on the Mac yet.

**Denial reasons:** `wrongPassword`, `rhythmMismatch`, `emptyInput`, `lockedOut` (see `lockoutRemainingSeconds`).

Lockout rules match the Mac app (M3).

---

### `POST /v1/safe-mode/activate` (auth required)

Activates **Safe Mode** for **24 hours** on the Mac app and browser extension. Can be triggered from Settings, Home sidebar, or the extension popup.

**Response `200`:**

```json
{
  "protocolVersion": 1,
  "active": true,
  "expiresAt": "2026-07-13T14:00:00Z",
  "remainingSeconds": 86400,
  "formattedRemainingTime": "24:00:00"
}
```

---

### `POST /v1/safe-mode/deactivate` (auth required)

Ends Safe Mode before the 24-hour window expires. Syncs to Mac app and extension immediately.

**Response `200`:**

```json
{
  "protocolVersion": 1,
  "active": false,
  "expiresAt": null,
  "remainingSeconds": 0,
  "formattedRemainingTime": null
}
```

---

### `POST /v1/fill-approve` (auth required)

Approve autofill after a **recent successful verify** (within **60 seconds**).

**Request:**

```json
{
  "protocolVersion": 1,
  "requestId": "new-uuid",
  "origin": "https://example.com",
  "verificationRequestId": "550e8400-e29b-41d4-a716-446655440000",
  "username": "user@example.com"
}
```

`username` is optional; used if the Mac app must create a site credential during fill-approve.

**Response `200` (approved):**

```json
{
  "protocolVersion": 1,
  "requestId": "new-uuid",
  "approved": true,
  "expiresAt": "2026-06-18T12:00:00Z",
  "message": null,
  "credentials": {
    "username": "user@example.com",
    "password": "generated-or-saved-site-password"
  }
}
```

**Response `200` (not approved):**

```json
{
  "protocolVersion": 1,
  "requestId": "new-uuid",
  "approved": false,
  "expiresAt": null,
  "message": "No recent successful verification for this origin."
}
```

---

### `POST /v1/allowlist/check` (auth required)

Check whether a page origin is permitted under the Mac app allowlist (W4.2).

**Request:**

```json
{
  "protocolVersion": 1,
  "origin": "https://accounts.spotify.com"
}
```

**Response `200`:**

```json
{
  "protocolVersion": 1,
  "origin": "https://accounts.spotify.com",
  "normalizedOrigin": "https://accounts.spotify.com",
  "allowed": false,
  "allowlistActive": true
}
```

When `allowlistActive` is `false` (empty allowlist in Settings), all origins are allowed. When `allowlistActive` is `true` and `allowed` is `false`, the extension prompts the user to add the site before verify.

---

### `POST /v1/allowlist/add` (auth required)

Adds an origin to the allowlist after explicit user approval in the extension panel.

**Request:**

```json
{
  "protocolVersion": 1,
  "origin": "https://accounts.spotify.com"
}
```

**Response `200`:**

```json
{
  "protocolVersion": 1,
  "added": true,
  "normalizedOrigin": "https://accounts.spotify.com",
  "message": null
}
```

---

## Error format

```json
{
  "protocolVersion": 1,
  "error": "unauthorized",
  "message": "Valid extension access token required."
}
```

Common HTTP status codes: `400`, `401`, `404`.

---

## CORS

Responses include `Access-Control-Allow-Origin: *` for browser `fetch()` from extension contexts. `OPTIONS` requests return `204` with allowed methods/headers.

---

## Lifecycle

| Event | Behavior |
|-------|----------|
| App launch | Server starts on `127.0.0.1:17487` |
| App quit | Server stops |
| Mac sleep | Server stops |
| Mac wake | Server restarts |

---

## Test client

Use `scripts/test-extension-client.sh` from the repo root while the Mac app is running:

```bash
./scripts/test-extension-client.sh YOUR_PAIRING_CODE
```

---

## Planned extension responsibilities (Phase 2)

| Step | Extension | Mac app |
|------|-----------|---------|
| Detect login form | ✅ | — |
| Capture keystroke timing | ✅ | — |
| Call `/v1/verify` | ✅ | Verifies |
| Call `/v1/fill-approve` | ✅ | Approves if recent verify; returns site credentials |
| Autofill password | ✅ (after approve) | Auto-generates per-origin site passwords on first grant (W3.5) |

---

## Versioning

Clients must send `protocolVersion: 1`. Breaking changes increment the version and use new route prefixes (e.g. `/v2/...`).
