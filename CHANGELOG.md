# Changelog

Newest first. Every push to `main` becomes a GitHub Release `build-<number>` with
`PaisaPulse.apk` (Android) and `PaisaPulse.ipa` (iPhone, free Apple ID). See [docs/INSTALL.md](docs/INSTALL.md).

## [Unreleased]

- **New iPhone app, rewritten in Swift (SwiftUI).** Native Liquid Glass tab bar with its own Search
  button, native lists, sheets, swipe actions, long-press menus and forms. Home has one card with a
  budget ring. Quick Add is a sheet you can drag between half and full height, with keypad sums.
- **No minus signs anywhere** (iPhone and Android): expenses in soft red, income in green, transfers
  grey, and a card you owe on says "₹X due".
- New: **Splits** with friends (equal split from Quick Add; who owes whom; settle up, pay by UPI).
- New: **Credit card tracking**: limit used, this cycle's spend, statement and due dates, Pay Bill.
- New: **Notifications**: budget alerts at 80% and 100%, card bill reminders, Sunday summary.
- New: **Goals** (save towards a target by a date) and **Net worth over time** chart.
- New: **Backups to Google Drive or Files** on iPhone (same file restores on Android), daily
  automatic backups in Files › On My iPhone › Paisa Pulse.
- New: widget **Add** button, Lock Screen widgets, and an **Add Expense** Control Center / Action
  Button control.
- Not on iPhone yet: statement import, voice and screenshot capture (still in the Android app).

- New: Android and iPhone builds on every push, published as GitHub Releases.
- New: iPhone build that installs with a free Apple ID (SideStore/AltStore/Sideloadly): the app and
  its widgets. Siri & Shortcuts and iCloud backups need a paid Apple account, so this build leaves them
  out; backups are in Files › On My iPhone › Paisa Pulse.
- New: Software Update. The app tells you when a newer build is out (Settings › Software Update, or
  Check for Updates at the bottom of Settings). On iPhone it opens straight in SideStore.
- Better: transaction rows show the account name without card digits, so they no longer cut off.
- Better: in dark mode the selected Expense / Income / Transfer tab is a tinted pill with white text
  (red text on grey was hard to read).

## [0.1.0] - 2026-10-10

- Phases 1–4: manual transactions, accounts, categories, budgets, recurring, insights, calendar,
  subscriptions, statement import (Axis, BoB, HDFC, ICICI, SBI), voice and screenshot capture,
  widgets, Siri, backups.
