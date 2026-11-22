# Changelog

Newest first. Every push to `main` becomes a GitHub Release `build-<number>` with
`PaisaPulse.apk` (Android) and `PaisaPulse.ipa` (iPhone, free Apple ID). See [docs/INSTALL.md](docs/INSTALL.md).

## [Unreleased]

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
