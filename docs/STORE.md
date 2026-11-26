# Store submission kit (App Store + Google Play)

Everything to paste into App Store Connect and Play Console, and what's left before submitting.
Checked against the [app-store-compliance](https://github.com/mjmirza/app-store-compliance) checklist on 26 Nov 2026.

## Builds

| Store | How to build | What's different |
|---|---|---|
| App Store | `xcodebuild … PAISA_DISTRIBUTION=appstore` (Info.plist `PaisaDistribution`) with a paid developer account | No update check, no SideStore link (`Distribution.isAppStore`) |
| Google Play | CI artifact `android-play` → `PaisaPulse-play.aab` (`:app:bundlePlayRelease`) | No self-update, no `RECEIVE_SMS` permission or SMS receiver (`BuildConfig.STORE_BUILD`, `src/play/AndroidManifest.xml`) |
| GitHub / iloader | unchanged (`PaisaPulse.apk`, `PaisaPulse.ipa`) | Everything on |

## Links

- Privacy policy: https://paisa-pulse-sigma.vercel.app/privacy (also in the app: Settings › bottom › Privacy Policy)
- Account deletion (Play asks for this URL): https://paisa-pulse-sigma.vercel.app/delete-account
- Support: hello@nishitrk.tech

## Notes for App Review (paste and fill in)

> Paisa Pulse is a personal finance tracker. The ledger is stored only on the device; no sign-in is needed for anything except Splits › People (sharing expenses with friends).
>
> Demo account for the sharing features: email `[REVIEW_EMAIL]`, password `[REVIEW_PASSWORD]`. It is already connected to a second demo user so the People and Inbox screens have content.
>
> Paths: Add (+) → Quick Add. Settings › Auto-capture → explains the optional Shortcuts automation (the "Log Bank Message" action queues a bank SMS for review; nothing is read without the user setting it up). Settings › Bills, Net Worth, Monthly Recap › Full Report (PDF).
>
> Contacts permission is used only on People › Find Friends from Contacts; numbers are hashed on the device. Camera is used only to scan a card (last 4 digits kept). No in-app purchases. No ads, no tracking.

Create the two demo users once (sign up in the app, connect them, add one shared split). Keep the backend live for the review window.

## Apple privacy labels

Data used to track you: **none**. Data linked to you (only if the user creates an account), all for **App Functionality**:

| Category | Type |
|---|---|
| Contact Info | Email Address, Name, Phone Number (hashed) |
| Contacts | Contacts (hashed numbers, matched not stored) |
| Identifiers | User ID |
| Financial Info | Other Financial Info (shared split expenses) |

Matches `apple/Shared/PrivacyInfo.xcprivacy`. Encryption: `ITSAppUsesNonExemptEncryption = NO` (CryptoKit AES-GCM for the user's own backups + HTTPS).

## Google Play Data safety

- Collected (optional, account only): Personal info → Email address, Name, Phone number; Contacts; Financial info → Other financial info; App activity → none. Purpose: App functionality. Not shared with third parties. Encrypted in transit. Users can request deletion (in app + the URL above).
- On-device only (not "collected" because it never leaves the phone): transactions, SMS/notification text, screenshots, statements, card last 4.
- Financial features declaration: personal finance tracker; no lending, payments processing or investment services.
- Permissions: `READ_CONTACTS` (find friends, prominent disclosure dialog first), notification listener (auto-capture, disclosure dialog first), camera, biometric, notifications. No SMS permission in the Play build.
- New personal developer account: run the closed test (12 testers, 14 days) first.

## Monetisation rule (before turning on Pro)

- **iPhone (App Store):** Pro unlocked in the app must be sold with in-app purchase. Outside the US storefront the app can't link or point to the website to buy. Selling on the website is fine for people who install from GitHub.
- **Android (Play):** use Play Billing (India also offers user choice billing). The GitHub APK can use website billing.

## Still to do by hand

- Paid Apple Developer Program account (App Store) and a Play Console account.
- Store screenshots from the store builds (iPhone 6.9" incl. Dynamic Island; iPhone Duo is optional now, required from April 2027).
- Age rating questionnaires (expect 4+ / Everyone), content rights, DSA trader status if offered in the EU.
- Fill in the demo account above.
