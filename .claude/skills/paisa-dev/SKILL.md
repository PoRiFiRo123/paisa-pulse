---
name: paisa-dev
description: How to change, test, build and ship Paisa Pulse (Expo/React Native finance tracker for India, iOS + Android). Use for ANY work in this repo — screens, database, import parsers, widgets, CI builds, releases, the free Apple ID iOS build, the in-app update check — even when the request only says "fix the app" or "add a feature".
---

# Paisa Pulse dev

Read `CLAUDE.md` (project context and decisions) and `SPEC.md` first. This skill is the build/test/ship loop.

## Loop
- `scripts/dev.sh check` before every commit: typecheck + lint + all jest suites. CI runs the same.
- Feature code takes a `DB` and is tested against in-memory SQLite (`src/db/__tests__/testDb.ts`). Add a test for every parser or money/date rule you touch.
- Schema change: edit `src/db/schema.ts`, `npm run db:generate`. Never hand-edit `src/db/migrations/`.
- Money is integer paise. Never floats.

## Builds (GitHub Actions, `.github/workflows/build.yml`)
- Push to `claude/**` or `main` builds three jobs: `tests`, `android` (release APK), `ios` (unsigned archive on `macos-26`, ad-hoc signed with the App Group entitlement, packaged as `PaisaPulse.ipa`).
- Only `main` publishes a GitHub Release `build-<run number>` with both files. Branches upload artifacts only.
- `scripts/dev.sh ci` shows the latest run; `scripts/dev.sh logs ios` prints a failed job's log.
- No EAS for iOS: EAS signing needs the paid Apple Developer Program. The user installs with a free Apple ID via SideStore.

## The free Apple ID build (`app.config.js`)
- `PAISA_FREE_SIGNING=1` (CI sets it for iOS): keeps app + widget (2 of the 3 free app slots), drops the Siri/Shortcuts extension (`targets/intents`) and the iCloud container. Backups go to Files › On My iPhone › Paisa Pulse.
- In code, gate with `FREE_SIGNING` from `src/lib/native.ts` (hide Siri UI, skip iCloud store).
- SideStore/AltStore rename the App Group to `group.com.paisapulse.app.<TEAMID>`. Always get the group from `appGroup()` (`src/features/widgets/publish.ts`) in JS and `Snapshot.appGroup` / `Shared.appGroup` in Swift; both read `ALTAppGroups` from Info.plist (`modules/app-group`).
- Do not add another app extension without asking: it costs the user an app slot.

## Android signing
- The release APK is signed with the same key every build so updates install over the old app. The key comes from the `PAISA_ANDROID_KEYSTORE_B64` repo secret (alias `androiddebugkey`, password `android`), else a key cached by Actions (lost if the cache is evicted: then the next APK will not install over the old one; uninstall after a backup).

## In-app updates (`src/features/updates`)
- `BUILD_NUMBER` comes from `PAISA_BUILD_NUMBER` (CI run number). Local builds are 0 and never check.
- The app reads `releases/latest`, offers `build-N` when N is higher: Android opens the APK, iPhone opens `sidestore://install?url=<ipa>` (falls back to the release page).

## Ship
1. `scripts/dev.sh check`, push the branch, wait for a green run (`dev.sh ci`).
2. Add a line under `## [Unreleased]` in `CHANGELOG.md`.
3. Merge to `main` (PR). The release is published automatically; phones see it within 6 hours or via Settings › Check for Updates.

## Things that are easy to get wrong
- Swift in `targets/` is only compiled by the CI `ios` job. Say so when a Swift change hasn't been through a green run.
- Native modules don't exist in Expo Go: require them lazily behind `HAS_CUSTOM_NATIVE`.
- The web export is a preview tool only (see CLAUDE.md for the expo-sqlite patch). Never commit `node_modules` changes or demo seeders.
