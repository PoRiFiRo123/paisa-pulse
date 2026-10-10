# Paisa Pulse — Project Context for Claude Code

This file hands over context from a planning conversation in claude.ai. Read it and `SPEC.md` before doing anything.

## What we're building
A **free, local-first personal finance tracker for India**. React Native (Expo), iOS + Android, with an **Apple iOS 26 Liquid Glass** look.

- **v1 = manual transaction CRUD only** (create, read, update, delete + undo, duplicate) for Expense / Income / Transfer, plus accounts and categories.
- Auto-capture comes later: SMS/notification parsing on Android, iOS Shortcuts, statement import. Keep the data model ready for it (`source` column on transactions).
- No servers, no sign-up, no ads, no lending upsell. Data stays on the device.

## Key decisions (already made — don't relitigate)
- **Stack:** Expo (latest stable SDK) + TypeScript, Expo Router with **Native Tabs**, `expo-sqlite` + **Drizzle ORM**, Zustand for UI state, FlashList, Reanimated + Gesture Handler, `expo-glass-effect` (GlassView), `expo-blur` fallback, `expo-symbols` (SF Symbols), `expo-haptics`, `expo-local-authentication`.
- **Money:** integer paise everywhere, never floats. Format with `Intl.NumberFormat('en-IN')` (lakh/crore).
- **IDs:** UUIDv7. **Deletes:** soft delete (`deletedAt`) with 5s Undo toast.
- **Transfers** (incl. credit-card bill payments) are not expenses.
- **Liquid Glass rules:** glass only for floating controls (tab bar, toolbar buttons, sheets, menus, keypad). Content (lists, cards, amounts) stays solid. Native components first. Always design the fallback: `isLiquidGlassAvailable()` → blur on iOS < 26, Material 3 on Android.
- Start testing in **Expo Go**; switch to a dev build only for SQLCipher encryption, widgets, and native capture modules.

## Design source of truth
Figma file: https://www.figma.com/design/XuWxnYDOjJSg74G5iJ1UGr

Screens: 01 Home (light), 02 Quick Add Sheet, 03 Activity, 04 Transaction Detail, 05 Accounts, 06 Settings, 07 Home (dark).
Also: Foundations (colours, type), Components (Transaction Row, Row Divider, Category Capsule, Glass Button, Tab Bar, Add Button, Keypad Key, Settings Row), Icons.

Notes:
- The Figma file uses **Inter + stroke icons as stand-ins**. In the app use **SF Pro** (system font), SF Pro Rounded for amounts, and **SF Symbols**.
- The user is on the Figma Starter plan: very few MCP read calls per month. Prefer screenshots the user shares, or ask before making Figma read calls.

### Colour tokens
| Token | Light | Dark |
|---|---|---|
| Background | #F2F2F7 | #000000 |
| Card | #FFFFFF | #1C1C1E |
| Label | #000000 | #FFFFFF |
| Secondary | #8A8A8E | #8E8E93 |
| Separator | #E3E3E8 | #2C2C2E |
| Accent | #5E5CE6 | #7D7AFF |
| Expense | #FF3B30 | #FF453A |
| Income | #34C759 | #30D158 |

Categories: Food #FF9500, Groceries #34C759, Transport #007AFF, Shopping #FF2D55, Bills #FFB800, Rent #AF52DE, Entertainment #5856D6, Health #FF3B30, Subscriptions #32ADE6, Salary #30B0C7.

## The user
- Based in India. Banks: Axis Bank (salary account), Bank of Baroda. Card: Axis MyZone credit card.
- Wants "insane" UI/UX, extreme customisation, ease of use.
- Prefers being asked when something is genuinely ambiguous before implementing.

## Where to start
1. Scaffold the Expo project (TypeScript, Expo Router) matching the folder structure in `SPEC.md` §8.
2. Build the DB layer: Drizzle schema (`SPEC.md` §6), migrations, starter category seed, money helpers + unit tests.
3. Build screens in order: Home → Quick Add sheet → Activity → Detail → Accounts → Settings, matching the Figma designs.
4. Check against the Definition of Done in `SPEC.md` §10.

## Implementation decisions (made with the user, Sep 2026)
- **Expo SDK 57** (RN 0.86, React 19.2, TypeScript 6). Native tabs import from `expo-router/unstable-native-tabs` on this SDK. Routes live in root `app/`, everything else in `src/` (`@/` alias → `src/`).
- **Uncategorised = `categoryId` null.** No special seeded row. Transfers always have a null category.
- **Balances are signed.** Credit cards go negative when you owe; a bill payment is a transfer into the card. Net worth is a plain sum of non-archived, non-excluded accounts.
- **Schema extras beyond SPEC §6:** `createdAt`/`updatedAt` on categories, `excludeFromTotals` on accounts, extra indexes on `transactions(toAccountId)`, `(type, occurredAt)` and `(payee)`, and CHECK constraints (amount > 0, transfer shape).
- **Migrations:** edit `src/db/schema.ts`, then `npm run db:generate`. Never hand-edit files in `src/db/migrations/`.
- **Feature code takes a `DB`** (`src/db/types.ts`) so it runs against the expo-sqlite DB in the app and an in-memory `node:sqlite` DB in tests (`src/db/__tests__/testDb.ts`, which runs the real migration SQL).
- **Figma:** use the `nishitkirani2020@gmail.com` account (Starter, 20 read calls/month; the college account's quota is used up). The full node tree of page `0:1` is saved in `design/figma-page-0-1.xml`, so don't spend a call re-reading it. Sep 2026 usage: 3 read calls (page metadata, Components section, which only returns a sparse outline for sections, and Home `6:39` design context). Home's design context gave every component's exact styling; the other screens were built from the saved node tree plus those styles. Only spend more calls to check a specific screen visually.

## Status (Sep 2026)
All v1 screens are built: onboarding, Home, Quick Add/Edit sheet, Activity + Search tab, Transaction Detail, Accounts (+ account detail and form), Settings, Categories manager (+ form, and a Change Category sheet).
- **Glass:** `src/ui/Glass.tsx` → `GlassView` on iOS 26, `BlurView` on older iOS, solid tonal surface on Android and with Reduce Transparency.
- **Menus:** `src/ui/Menu.tsx` is a cross-platform glass popover (matches Figma "Context Menu (Glass)"). Transaction rows on iOS use native `Link.Menu` + `Link.Preview`.
- **Live data:** use `useQuery` (`src/hooks/useQuery.ts`), which re-runs on any table change. Drizzle's `useLiveQuery` only watches the main table.
- **Quick Add payee/note:** one field; text before `·` is the payee, after it the note.
- **Keypad maths:** an operator strip (+ − × ÷) above the Figma 4×3 keypad.
- **Multi-select:** Activity → "Select" glass button (or "Select" in a row's context menu). The bulk bar changes category or account, or deletes; each is undoable (`src/features/transactions/bulk.ts` snapshots rows first).
- **Undo:** `useToast` remembers the last undoable action for 2 minutes; shaking the phone (`src/ui/ShakeToUndo.tsx`, accelerometer only while an undo exists) asks "Undo …?".
- **Zoom transition:** iOS rows use `Link.Trigger withAppleZoom`; the detail screen's icon is the `Link.AppleZoomTarget`.
- **Drag-to-reorder:** `src/ui/SortableList.tsx` (Reanimated + Gesture Handler, fixed row height, VoiceOver move up/down actions). Used by Accounts and Categories reorder modes.
- **App icons:** `assets/icon.png` (default), `icon-dark.png`, `icon-tinted.png` via `ios.icon`, plus Android adaptive foreground/background/monochrome. Generated from an SVG rupee mark. A true iOS 26 Liquid Glass `.icon` needs Apple's Icon Composer on a Mac.
- **Accessibility:** `src/stores/a11y.ts` tracks Reduce Transparency and Increase Contrast (glass turns solid, stronger secondary and divider colours). Reanimated follows Reduce Motion by default.
- **Splash screen:** held until the database is ready (`DatabaseProvider`).

## Phase 2 + development build (Sep 2026)
- **Dev build:** `eas.json` profiles (development, development-simulator, preview, production); `npm run build:dev:ios|android`, then `npm run start:dev`. Bundle id / package `com.paisapulse.app`. **Set `ios.appleTeamId` in app.json** before the first iOS build (the widget extension needs it for signing).
- **Encryption:** expo-sqlite is built with SQLCipher (`src/db/encryption.ts`). Dev/store builds use `paisa-pulse.enc.db` with a per-install key in SecureStore; an old plaintext `paisa-pulse.db` is exported into it once and deleted. Expo Go (no SQLCipher) keeps the plaintext DB.
- **Custom native modules** (widgets, alternate icons) don't exist in Expo Go: gate them with `HAS_CUSTOM_NATIVE` (`src/lib/native.ts`) and `require` them lazily. `index.js` is the entry (Expo Router + Android widget task handler).
- **Budgets** (`src/features/budgets`): overall or per category (parents include subcategories); Home section, `/budgets`, `/budget-form`.
- **Recurring** (`src/features/recurring`): rules with daily/weekly/monthly/yearly × interval, end date, pause; `processDueRecurring` runs at launch and on foreground (catch-up cap 60), anchored to the start day. `/recurring`, `/recurring-form`, "Repeat…" on the transaction detail, Home "Upcoming".
- **Insights** (`/insights`): single-hue monthly bars, labelled category breakdown, biggest expenses. Chart marks use `chartColor()` (OKLCH lightness clamp, `src/lib/color.ts`).
- **Saved filters** in Activity (bookmark button; chips to apply; long-press to update/rename/delete).
- **Widgets:** one `WidgetSnapshot` (`src/features/widgets/snapshot.ts`) feeds both platforms, refreshed on DB changes (debounced), settings changes and backgrounding.
  - iOS: `targets/widget` (SwiftUI via @bacons/apple-targets): small/medium Home Screen, Lock Screen circular/rectangular/inline, and an iOS 18 Control Center / Action Button "Add Expense" control. Data via App Group `group.com.paisapulse.app`.
  - Android: react-native-android-widget `Spending` widget (`SpendingWidget.tsx`, headless `taskHandler.tsx`, snapshot file).
  - The Swift code has not been compiled in this environment (no Xcode); expect to fix small issues on the first EAS/Xcode build.
- **Quick actions** (long-press app icon) via expo-quick-actions, routed with `useQuickActionRouting` in `(tabs)/_layout`.
- **Alternate app icons** (Midnight, Saffron, Mint, Mono) via expo-alternate-app-icons; Settings › App Icon (hidden in Expo Go).
- **Deep links:** `paisapulse://add?type=expense|income|transfer`; root `unstable_settings.initialRouteName = '(tabs)'` keeps tabs under sheets.
- **Still to do:** a Liquid Glass `.icon` needs Icon Composer on a Mac. (Siri was added in Phase 4.)

## Phase 3: statement import (Sep 2026)
`/import` (Settings › Import Statement, or an account's ••• menu). Flow: pick file → (PDF password) → setup (account, detected bank, column roles, date order) → review (include/exclude, type, category, transfer account) → import as one batch with Undo; recent imports can be undone/restored.
- **Readers** (`src/features/import/readers`): all produce `Sheet` (rows of text cells). CSV (delimiter auto-detect), XLSX via `fflate` + XML (npm `xlsx` was avoided: known CVEs, CDN blocked), HTML tables saved as `.xls`. Binary BIFF `.xls` is not supported (user is told to use PDF/CSV/XLSX). File type is sniffed from bytes, not the extension.
- **PDF:** pdf.js runs in a hidden WebView (`PdfExtractorProvider`, `assets/pdf/extractor.html`, rebuilt with `node scripts/build-pdf-extractor.mjs` from the `pdfjs-dist` devDependency). `layoutToSheet` rebuilds the table: header cells are column anchors; dated lines start rows; text-only lines in description columns (wrapped narrations) join the nearest dated row. The fixture `axis-pdf-items.json` is a real pdf.js extraction from Chromium.
- **Normaliser** (`parse.ts`): header detection, bank templates (Axis, BoB, HDFC, ICICI, SBI + cards; detected from the preamble, then header shape), Indian dates (day-first, named months, Excel serials) and amounts (lakh commas, Dr/Cr, brackets), running-balance check.
- **Narrations** (`narration.ts`): UPI/NEFT/IMPS/POS/ATM/NACH per bank format, Indian merchant names, keyword category rules.
- **Planning** (`plan.ts`): categories learned from past payees first, then rules; card bill payment → transfer to the card (matched by last 4), ATM → transfer to Cash, other own accounts by last 4 or name. Exact re-import via a row fingerprint in `transactions.external_id`; likely duplicates (same account, amount, direction, ±1 day) of manual entries or the other side of a transfer are unticked. `import_batches` + `transactions.import_batch_id` power undo. Backups are v3.
- Test fixtures (`__tests__/fixtures/statements.ts`) are synthetic statements shaped like each bank's export; real exports may differ, which the column-mapping step covers. Ask the user for a (redacted) real statement to tighten a template.
- **Web preview (not a product target):** `expo export -p web` works, but expo-sqlite 57's web worker writes the result length into a byte array (`WorkerChannel.ts`, `resultArray.set(new Uint32Array([length]), 0)`), so sync results over 255 bytes break. For Playwright previews, patch that line temporarily; never commit changes in `node_modules`.

## Phase 4: Quanto parity (Oct 2026)
The user compared us with the Quanto app and asked for everything except receipt scanning, multiple languages and iPad/Mac/Vision versions.
- **Schema (migration 0003):** `budgets.period` ('weekly' | 'monthly', unique per category+period); `transactions.currency` + `original_amount` (minor units; `amount` stays INR paise). New transaction sources `voice`, `screenshot` (TS enum only). Backups are v4. Don't add CHECK constraints on existing tables: drizzle-kit then rebuilds the table and its generated copy SQL selects the new columns, which fails.
- **Weekly budgets:** `budgetProgress(db, month, now, week)`; weekly rows sort after monthly; Home shows weekly only for the current month.
- **Insights periods:** `src/lib/periods.ts` (week/month/quarter/year from the salary-day month; custom range with `previousRange`). Activity accepts `filters.range` (overrides `monthOffset`) so any period can open Activity.
- **Calendar** (`/calendar`, also from Activity and Insights): calendar months, daily net, single-hue heat (sqrt scale). Quick Add takes `?at=` for the tapped day.
- **Subscriptions** (`/subscriptions`): recurring expenses with monthly/yearly cost, renewal, total paid. `detectSubscriptions` finds steady payee+amount cadences (≥3 payments, ≥2 yearly, ±10%, not stale); `trackSubscription` creates the rule and links the past payments; an overdue next payment is never invented.
- **Merchant brands** (`src/features/merchants/brands.ts`, shared with import narrations): name, colour, domain. Rows show a monogram in the brand colour; Settings › Merchant logos (default off) loads favicons from Google's s2 service (only the brand domain is sent).
- **Currency:** Quick Add's ₹ symbol opens a currency menu; rates from open.er-api.com cached 12 h in settings `fx.rates` (rupees per unit), manual rate prompt when offline. `/converter`. CSV export has an "Original amount" column.
- **Voice** (`/capture?mode=voice`): `expo-speech-recognition` (en-IN, on-device when supported). `parseSpokenTransactions` (number words incl. "one fifty", k/lakh, splitting on commas and on "and" only between amounts, dates, accounts, payees/brands, income, transfers, card bills). A date covers later phrases and earlier undated ones. In Expo Go the screen falls back to typing / keyboard dictation.
- **Screenshots** (`/capture?mode=screenshot`): `expo-text-extractor` (Vision / ML Kit; Android needs a plain path, not `file://`). `parsePaymentScreenshot` handles GPay, PhonePe, Paytm, CRED, bank apps; failed/pending and already-logged payments are unticked with a warning.
- **Capture review:** `DraftList` + `commitDrafts` (one Undo for all). Entry points: Add button long-press, Quick Add toolbar (mic, photo), quick actions.
- **Backups** (`/backups`): `src/features/backup/auto.ts` + `stores.ts`. Default daily; keeps 14. iOS: iCloud Drive (`react-native-cloud-storage`, container `iCloud.com.paisapulse.app`, Documents scope › Backups) when signed in, else Documents/backups. Android: files/backups, carried by Google Auto Backup via `plugins/withAndroidBackupRules.js` (which replaces expo-secure-store's rules; `configureAndroidBackup: false`). Onboarding offers the newest backup. `openEncryptedDatabase` sets aside an encrypted DB it can't open (key didn't survive a device restore) instead of crashing (`databaseWasReset`).
- **Siri / Shortcuts** (`targets/intents`, App Intents extension, iOS 17+): Log Expense, Log Income, Log Card Payment (silent, for Wallet automations), Spent This Month, Say Expenses (iOS 18). Entries queue as JSON in the App Group (`pendingCaptures`); `usePendingCaptures` adds them at launch/foreground once each (`external_id = shortcut:<id>`). Settings › Siri & Shortcuts explains the Wallet automation. Swift not compiled here.
- **Before the first iOS build:** enable the iCloud container `iCloud.com.paisapulse.app` for the bundle id (EAS syncs capabilities, or add it in the Apple Developer portal) as well as the App Group.

### Figma node IDs (file `XuWxnYDOjJSg74G5iJ1UGr`, frames 402×874 = iPhone 17 Pro)
| Node | ID |
|---|---|
| 01 Home — Light | `6:39` |
| 02 Quick Add Sheet | `7:205` (sheet `7:272`) |
| 03 Activity | `8:429` |
| 04 Transaction Detail | `9:580` (context menu `9:728`) |
| 05 Accounts | `9:762` |
| 06 Settings | `10:950` |
| 07 Home — Dark | `10:1210` |
| Foundations | `5:3` |
| Components: Transaction Row `5:136`, Row Divider `5:147`, Category Capsule `5:149`, Glass Button `5:159`, Tab Bar `5:164`, Add Button `5:195`, Keypad Key `5:200`, Settings Row `5:202` | |
| Icons section | `4:160` |
