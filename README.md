# DynamicKey

A Mac app plus a Safari browser extension, built for the Meta Global AI Developer Hackathon (indie track).

DynamicKey replaces password-only login with a local check that has to agree on several signals at once, and it helps the user judge email risk instead of deciding for them. Everything that identifies the user stays on this Mac.

## What it is

- **Mac app:** the vault. It holds the master password check, the typing profile, trusted keyboards and networks, saved site credentials, the security activity log, and LeakPeek.
- **Safari extension:** the helper in the browser. It shows the password overlay on websites, pairs with the Mac app, and runs DynamicShield inside Gmail web.
- **Home screen:** system status, security score, LeakPeek status, quick stats, and recent activity, plus the Daily Summary on the first launch of the day.

## How login works

Logging in takes more than a password. All of these have to agree, or there is no login and no use:

1. **Master password.** It is only a check to unlock the app. It is never a password for any website.
2. **Typing rhythm.** The app compares how you type against your enrolled profile (dwell time, flight time, profile strength), stored in the keychain on this Mac.
3. **Trusted keyboard.** The input layout in use must be a trusted one (for example, Norwegian).
4. **Trusted network.** The WiFi network in use must be a registered one (for example, your home network).

The Mac app itself needs the same check. A correct master password with a non-matching rhythm still does not log in, and the same holds for a non-trusted keyboard or network. In testing, a second person typing the correct master password could not sign in.

**Match threshold** is user-adjustable from 50% to 90% (70% is Balanced; higher is stricter), with adaptive advice to raise it when sign-ins are consistent. **Safe Mode** covers 24 hours when rhythm is unreliable, for example an injured hand: it authenticates with Touch ID on the Mac keyboard. Face ID will be used on the future iPhone app. The Mac app comes first.

**Trusted keyboards and networks** are managed in settings with a plus button to add. Adding needs no extra authentication, because the session is already fully verified at login. The reasons to add are everyday ones: a public WiFi while out, or a replacement keyboard when the old one breaks.

## Site passwords

Site passwords are separate from the master password. The app generates random 24-character passwords, stores them locally, and fills them after verification. The user never needs to know them, and a leaked master password cannot be replayed at any website, because it is not the password for that site.

## Extension pairing

Pairing uses a one-time code generated only in the Mac app. A new code is needed for each pairing. The paired extension shows a masked token and a last-verified timestamp.

## Password overlay

The overlay appears on all websites' password fields. It asks for the master password, with states for a Mac app that cannot be reached (with recovery steps) and for rhythm coaching ("type at normal speed"). Not Now collapses the overlay to a fingerprint icon inside the password field; pressing the icon brings it back. Never ask again silences future prompts. When master password and rhythm match, the app logs the user into the site.

## Security Activity

A log of sign-in, extension, and DynamicShield activity on this Mac, with the match percentage per entry and Today, Yesterday, and Last 7 days filters.

## LeakPeek

Two scans, both with results that stay inside DynamicKey:

- **Scan Now** checks saved passwords with k-anonymity (HIBP): only a hash prefix leaves the Mac.
- **Check Breaches** looks up saved emails in public breach records.

After both scans, each saved site shows Safe and Email safe badges. Neither scan reads what you type in the browser. Background auto-scan runs automatically so results stay fresh without manual scans, and to keep free API usage within limits.

## DynamicShield

DynamicShield is built into Gmail web. On opening a mail it shows a risk score with itemized reasons and points, plus View Report, Hide for Now, and Mark Sender Safe. The panel can be minimized to a compact bar showing the risk level and the number of unique risks.

It warns only and never blocks. The guiding principle is to treat every mail as a potential risk, not every mail as dangerous: most users click things they should not click, so the warning makes them more careful, and when the user decides a mail is safe they click Mark Sender Safe. That feedback feeds future scores, so the system improves with use. By design it is never 100%.

## Daily Summary

On the first launch of the day, the Home Screen shows a security brief, not a general assistant digest:

- Overnight sign-ins, with rhythm match, flagging anything unusual.
- LeakPeek overnight: new leaks, or none.
- Passwords needing attention.
- One action for today.

Local code gathers the counts. Muse narrates them in a sentence or two.

## How Meta AI is used

The on-device check always decides. A Meta model never sees typing data, passwords, or mail content, and never makes a login decision.

What happens instead: local code produces a short verdict (for example, "matched, slightly slower than usual"), and only that verdict string is sent to Muse Spark (`muse-spark-1.3` via the Meta Model API), which turns it into a human-facing message. The same split applies to the Daily Summary (counts only) and to DynamicShield risk scores (score and reasons only, narrated in plain words). If the API is unavailable, login still works and the message falls back to a plain local one.

In the finished app the user can choose local AI or Muse AI. For the demo, the Muse option is turned on so the API call is visible.

## Privacy

- Master password, rhythm profile, and credentials stay on this Mac.
- No typing biometrics leave the device.
- The Meta API key is entered by the user in Settings and stored in the macOS Keychain. It is never stored in the source or in this repo.
- Reset Data removes the rhythm profile, master password, and site credentials, and returns the app to setup.

## Demo

Screen-recorded demo video: https://youtu.be/lKsu7OE8wFo

- This 2:15 demo video shows DynamicKey working for real: logging in with master password and typing rhythm, the Daily Summary on the Home screen, and logging into a real website through the Safari extension, with Safe Mode as fallback. Everything is checked on the Mac itself; the Meta model only explains the verdict.


## Run it

1. Open the project in Xcode.
2. In Settings, choose Muse AI and enter your Meta API key; it is stored in the Keychain and shown masked.
3. Build and run.

## Project structure

- Mac app: login UI for enroll and verify, typing rhythm profile, trusted keyboards and networks, saved site credentials, security activity log, LeakPeek, and Daily Summary.
- Services: MetaExplanationService for verdict-only narration, MorningSummaryService for the first-launch-of-day summary, and MetaAPIKeychainStore for Keychain storage of the Meta API key.
- Safari extension: password overlay on websites, pairing with the Mac app, and DynamicShield inside Gmail web.

## Status

Hackathon demo, not a production authentication product. This repo was created purely for the hackathon submission.

## License

This app is not open source. The code in this repo is licensed under the PolyForm Noncommercial License 1.0.0 (see LICENSE): anyone may use it for noncommercial purposes, but commercial use requires permission. The app is intended for release on the App Store.
