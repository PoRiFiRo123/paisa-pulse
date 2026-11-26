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

## Builds, free Apple ID iOS, updates (Nov 2026)
Load the `paisa-dev` skill (`.claude/skills/paisa-dev/SKILL.md`) before any work: build/test loop, CI, the free-signing iOS variant and the update check.
- **CI** (`.github/workflows/build.yml`): every push builds a release APK and a free-Apple-ID .ipa; `main` publishes Release `build-<run number>`. No EAS for iOS (needs a paid account).
- **Free signing** (`app.config.js`, `PAISA_FREE_SIGNING=1`): app + widget only, no Siri extension, no iCloud; App Group resolved at run time from `ALTAppGroups` (`modules/app-group`). Chosen with the user: app + widget, same iOS look on Android.
- **Updates** (`src/features/updates`): compares `build-N` with `BUILD_NUMBER`; Android opens the APK, iPhone opens SideStore.

## Native iPhone app (Swift, Nov 2026)
The user chose to rewrite iOS in SwiftUI; Android stays on this Expo app. Code in `apple/` (XcodeGen `project.yml`; CI generates the project on macOS). Load `paisa-dev` first.
- `apple/Shared` (app + widget): SwiftData models mirroring this repo's tables (ids as strings, paise ints), `Ledger`/`Periods`/`Budgets`/`Recurrence`/`Splits`/`Cards` pure maths, `Money` (en_IN, **never a minus sign**), `AppGroup` (ALTAppGroups), `Store` (DB in the App Group).
- `apple/App`: screens. Backups use this app's v4 JSON (`BackupCodec`), plus `friends`, `splitEntries`, `goals`, `txnSplitShares` keys the RN app ignores.
- **No minus signs anywhere** (user decision, both apps): expense soft red (#E5484D / #FF6B6B), income green, transfers grey, account below zero reads "₹X due".
- Since ported (see the sections below): statement import, screenshot capture, currencies, merchant logos, alternate icons, saved filters. Voice stays Android-only.
- CI `ios` job: build, unit tests (`apple/Tests`), simulator screenshots (launch args `-PaisaDemo YES -PaisaTab <tab>` / `-PaisaAdd YES`) pushed to the `ci-screenshots` branch (read them with `gh api repos/PoRiFiRo123/paisa-pulse/contents/<name>.png?ref=ci-screenshots`).

## Two native apps, one product (decided with the user, 22 Nov 2026)
- **iOS = Swift (`apple/`), Android = Kotlin + Jetpack Compose (`androidApp/`).** The Expo app (`app/`, `src/`) is retired: keep it only as a reference for porting (parsers, brands, import).
- **Parity rule: every feature, screen and UX change ships on both apps together, looking and behaving the same.** Android mirrors the iOS design: same layout, colours, sheets, floating glass tab bar (blur via Haze), motion. Fonts/icons: Inter + rounded Material Symbols mapped from the SF Symbol names stored in data (Apple licenses SF Pro/SF Symbols for Apple platforms only). Only exception: voice capture is Android-only.
- **Data deletion:** "Delete all data" now, plus periodic auto-delete (monthly / quarterly / half-yearly / yearly / custom) = remove transactions older than the period; fold them into accounts' opening balances so balances stay right; save a backup first.
- **Loans:** a separate Loans section (lent / borrowed, due date, part repayments, reminders), apart from split balances.
- **Split v2:** contacts picker (people you split with first), who paid, equal / amount / shares, saved groups with settle-up, request via Messages with a QR code + a link to a static pay page on GitHub Pages (no domain, no Pi; details only in the URL), "Pay with…" UPI app picker, "Did it go through?".
- Both apps read and write the same backup JSON (v4 + extra keys), so data moves between phones.
- **Cards (Nov 2026, both apps):** `PaymentCard` (debit linked to a bank account; credit linked to its card account) stores network, last 4, expiry, name, nickname, colour only (user decision: never the full number or CVV). Added by camera scan (iOS VisionKit DataScanner live; Android photo + ML Kit text recognition, on device) or typed. `CardNumber.parse` (Swift + Kotlin, tested) checks Luhn, then keeps last 4. Transactions have `cardId` ("Paid with"). Backup keys `cards` + transactions' `cardId`. NFC was ruled out (iOS blocks payment cards; free Apple IDs can't use NFC).
- **Wallet Accounts screen (both):** every account is a card in an overlapping stack; its linked cards show as a fanned stack inside the account (tap to spread). iOS uses the zoom navigation transition.
- **Currencies + converter (both):** `Currency` (open.er-api.com, 12 h cache, offline cache, typed rate). Quick Add's currency symbol opens the list; `amount` stays INR paise, `currency` + `originalAmount` keep the foreign value.
- **App icons (both):** Default, Midnight, Saffron, Mint, Mono (iOS alternate icon sets; Android activity-aliases `.Icon<Name>`). Colour pickers draw real swatches (iOS menus otherwise tint every icon the same).

### Batch 2 on both apps (Nov 2026)
- **Statement import:** Swift `apple/App/Import/{Statement,Narration,ImportPlan,ImportView}.swift`, Kotlin `logic/{Statement,Narration,ImportPlan}.kt` + `ui/screens/Import.kt`. Ported from `src/features/import`; Android's `GoldenTest` checks the Kotlin port against the RN output (`src/test/resources/*-golden.txt`, generated in IST) and iOS `ImportTests` uses the same expected values. Same fingerprint everywhere, so re-imports are recognised across apps. PDFs: both apps load the RN app's pdf.js page (`pdf-extractor.html`, copied from `assets/pdf/extractor.html`) in a hidden WebView/WKWebView and call `window.extractPdf(b64, pw)`. xlsx on iOS: own ZIP reader + Compression. `ImportBatch` (backup key `importBatches`) powers undo/restore.
- **Screenshot capture** (both, `Capture.swift`/`Capture.kt` + screens): Vision on iOS, ML Kit on Android. **Voice** is Android-only (`VoiceParser`, system speech dialog, en-IN, offline preferred).
- **Brands** (`Shared/Brands.swift`, `logic/Brands.kt`, generated from `src/features/merchants/brands.ts`; regenerate both if the list changes). `MerchantBadge` on rows; Settings › Merchant logos loads Google s2 favicons (Coil on Android).
- **Subscriptions** (`Shared/Subscriptions.swift`, `logic/Subscriptions.kt`), **PeriodKind** (week/month/quarter/year/custom for Insights), **SavedFilter** (backup key `savedFilters`, JSON shared with RN), Activity **select mode** (bulk category/account/delete, tab bar hidden), **reorder sheets**, quick actions (iOS shortcut items via `QuickActions`, Android dynamic shortcuts). Deep link `paisapulse://capture[?mode=voice]`.
- Kotlin logic can be compiled and run locally: kotlinc from the GitHub release zip, with stub `kotlinx.serialization` annotations (no Android SDK needed for `logic/` + `data/Models.kt`).

### Stage 3 on both apps (Nov 2026)
- **Split v2:** `SplitMath` (Swift `Shared/Stage3.swift`, Kotlin `logic/Stage3.kt`, tested on both): who paid (nil = you), include me, equal / amounts / shares. You paid → expense with `splitShare` + `SplitEntry` per friend (+). A friend paid → no transaction, only `SplitEntry(payer, −yourShare)`; paying back via "Pay with…" + "Did it go through?" adds an expense (source `settle`) and a + entry. `SplitGroup` (backup `splitGroups`), `SplitEntry.groupId`, `Friend.phone` (iOS gained it). Screens: iOS `More/SplitsV2.swift`, Android `ui/screens/Splits2.kt` (editor is a full-screen dialog over Quick Add). Contacts via the system pickers (no permission). Requests: Messages/SMS with a pay-page link, UPI QR (CoreImage / zxing). Your UPI ID + name: prefs `myUpiId`, `myName` (Splits › For requests).
- **Pay page:** `docs/pay/index.html` (+ vendored MIT `qrcode.js`), served by GitHub Pages from `main` `/docs` at `https://porifiro123.github.io/paisa-pulse/pay/#pa=…&pn=…&am=…&tn=…`. Details only in the fragment. Pages must be enabled in the repo settings (the API is blocked from this environment).
- **Loans:** `Loan` + `LoanPayment` (backup `loans`, `loanPayments`), `LoanMath`; reminders on the due date (iOS scheduled; Android checked by maintenance/daily worker). iOS `Notifier.refresh` now clears all pending requests first (it schedules everything ahead).
- **Clean up:** `Cleanup` (prefs `autoCleanup`, `autoCleanupMonths`, `lastCleanupAt`); `DataCleanup.run` backs up, folds old transactions into opening balances, deletes them; `runIfDue` from maintenance (daily). Delete All Data backs up, wipes, sends you to onboarding.

### Batch 4 on both apps (Nov 2026)
- Logic: Swift `Shared/Batch4.swift`, Kotlin `logic/Batch4.kt` (tested: `Batch4Test`, iOS `Batch4Tests`): `PayeeMemory`, `Tags` (lowercase, spaces → `-`), `Forecast.monthEnd` (bank/cash/wallet balances + recurring rules to month end − 90-day average of non-recurring expenses × days left), `Recap`, `CardStatement.last` (billed vs paid since the statement), `HomeSections` (prefs `homeOrder`, `homeHidden`), `BackupCrypto`.
- Models: `TxnTemplate` (backup `templates`), `Valuation` (backup `valuations`), `Txn.tags` (backup), `Txn.receipt` (file name only; photos in Documents/receipts or files/receipts, not backed up), `AccountType.investment`. `Ledger.balances(…, valuations, asOf)` anchors an investment at its latest valuation and adds only later transactions.
- **Encrypted backup format** (both apps): `{"paisaEncrypted":1,"kdf":"pbkdf2-sha256","iterations":200000,"salt","iv"(12 bytes),"data"(ciphertext+16-byte GCM tag)}`, all base64. Password in the Keychain (iOS) / Android Keystore-wrapped prefs `paisa_secure` (`BackupPassword`). Auto backups are encrypted when a password is set. iOS test `testAndroidEncryptedBackupOpens` decrypts a file made by the Kotlin code.
- Screens: iOS `More/Batch4Views.swift`, Android `ui/screens/Batch4.kt` (Templates, Tags, TagDetail, Recap with share, Home layout, investment Value section, ForecastCard).
- Android Quick Settings tile `widget/AddExpenseTile.kt` opens `paisapulse://add?type=expense`.

### Add button (Nov 2026, both apps)
- The round + sits beside the floating tab bar (replacing the separate Search button; search is Activity's search field). Tap = expense, long-press = menu (Income, Transfer, Expense, top 3 templates, From Screenshots, Android also Say It). No + in top bars.
- iOS uses the **native system TabView** again (user, 24 Nov 2026: the custom bar didn't look like real Liquid Glass): `MainTabs` in `Core/RootView.swift`; the + is the search-role `Tab` (iOS draws it as the separate round glass button), whose selection opens Quick Add and keeps the current tab. No long-press menu on iOS: Quick Add has the templates row and a "From Screenshots" toolbar button. `router.hideTabBar` → `.toolbar(.hidden, for: .tabBar)`; `TemplateAdd` lives in `Core/TemplateAdd.swift`. Don't replace native components with custom look-alikes on iOS. Android: `TabBar` in `ui/Components.kt` + `AddButton(big = true)` in `ui/screens/Common.kt`.
- iOS App Intents (`Shared/Intents.swift`) must not open `paisapulse://` themselves ("launch is prohibited"): they call `PendingRoute.open`, which the app handles. `PaisaShortcuts` (AppShortcutsProvider) lists Add Expense / Add Income.

### Polish (Nov 2026, both apps)
- iOS `App/Core/Polish.swift` + `Shaders.metal`; Android `ui/Polish.kt`. Use these instead of one-off code: `Animation.quick` / `quick()` (0.2 s), `.rolling(value)` / `RollingText` for big amounts, `.pressable` (replaces `.plain`) / `Modifier.pressScale()`, `SkeletonRows`, `Haptic.soft()` / `Haptics`, `LiquidBackground` / `Modifier.liquidBackground()`, `LiquidProgress` (all progress bars). Shaders run at 30 fps and stop in Low Power / power save / Reduce Motion (Android: AGSL on API 33+, still gradient below).
- Celebrations: `Celebrations.check` (iOS, on save + foreground) / `Celebrations.init` (Android, debounced on Store) → goal reached, month under budget (checked once the month is over), all splits settled. Each fires once (defaults / prefs `paisa-celebrate`).
- Toast errors: `router.showError` / `Ui.showError` (error haptic). Privacy: iOS covers the window when inactive; Android disables the recents screenshot (API 33+) when App Lock or hidden amounts are on.
- Brand: the ₹ mark (`AppLogo` image set / `R.drawable.app_logo`); launch colour `LaunchBackground` / `@color/launch_background`.

### Auto-capture (Nov 2026, both apps)
- Parser: Kotlin `logic/BankAlerts.kt`, Swift `App/Import/BankAlerts.swift` (tests `BankAlertsTest` / `BankAlertsTests`, same cases). `PendingAlert(text, sender, receivedAt)` → `CaptureDraft`; key `alert:<UPI ref>` or `alert:<amount>:<java hashCode of normalised text>` stored in `Txn.externalId` (dedupe), `source = "sms"`.
- Android: `work/AlertCapture.kt` — `AlertListener` (NotificationListenerService), `SmsAlertReceiver` (RECEIVE_SMS, optional), `AlertQueue` (prefs `paisa-alerts`, posts a "tap to add" notification → `paisapulse://capture?mode=alerts`). Pref `autoCapture`. Screen `ui/screens/AutoCapture.kt`.
- iOS: no SMS access; `LogBankMessageIntent` (in `PaisaShortcuts`) queues text in the App Group (`PendingAlerts`, key `pendingAlerts`). Settings › Auto-capture explains the Shortcuts Message automation. Review = `CaptureView(mode: "alerts")`, Home banner when the queue isn't empty.

### Bills (Nov 2026, both apps)
- `Bills.upcoming` (Swift `Shared/Bills.swift`, Kotlin `logic/Bills.kt`; tests `BillsTest`/`BillsTests`): card bills (last statement's unpaid amount, else what's owed; next due day) + active recurring expenses within N days. Screens iOS `More/BillsView.swift`, Android `ui/screens/Bills.kt`. Reminders under `notifyBills`: cards 3 days before (existing), recurring 2 days before.

### Net worth + monthly report (Nov 2026, both apps)
- `NetWorth.breakdown` (Swift `Shared/NetWorth.swift`, Kotlin `logic/NetWorth.kt`): have / owe / by account type. Net Worth screen: total with change since last month, 6M/1Y/2Y chart, breakdown.
- `Report.rows/movers/biggest` (Swift `Shared/Report.swift`, Kotlin `logic/Report.kt`; tests on both): Recap gains "What changed" and **Full Report (PDF)** (iOS `More/ReportPDF.swift` with UIGraphicsPDFRenderer, Android `ui/screens/ReportPdf.kt` with PdfDocument; A4, same layout).
- Perf: core sums take ~1–35 ms on a desktop JVM with 20k transactions; Android remembers the net-worth history per (db, range).

### Navigation and members (Nov 2026, both apps)
- **iOS: list → detail links that can leave their list use value navigation** (`NavigationLink(value: NavRoute…)`, `apple/App/Core/NavRoutes.swift`; every tab stack calls `navDestinations()`; screens resolve by id and show "was deleted" if gone). A destination-style `NavigationLink { Detail() }` freezes the app when its row disappears while the detail is open (first plan hid Home's "Plan a trip" row; archiving a trip/account; a loan moving Open → Settled). Accounts' wallet keeps its zoom via a local `WalletRoute`. Android's `Route` stack is id-based already.
- **Members:** group and plan forms share `MemberPicker` (iOS, SplitsV2.swift) / `MemberPickerRows` (Android, Account.kt): tick friends, add by name (removed again on Cancel), or **Find Someone on Paisa Pulse** (`PeopleView(onPick:)` / `FindOnPaisaPulseDialog`: search @username/email/phone or your people, connects, returns the Friend with id = their user id like the sync). Linked friends show a badge; group screens have **Add People**.
- iOS plan form sets Type/Where through bindings, not onChange (loading an existing plan used to wipe its places).

### Website (Nov 2026)
- `website/` (static, no build). Vercel project `paisa-pulse` with root directory `website`, live at https://paisa-pulse-sigma.vercel.app (canonical URL used in every page, `sitemap.xml`, `robots.txt`, `llms*.txt`; change them all together when a custom domain is attached). Look: paper (#F3EEE4) + ink + forest (#1F4D3A) + marigold, Instrument Serif / Geist / Geist Mono, paper grain. Honours reduced motion.
- Pages: `/` (home), `/download` (device-aware: Android APK `releases/latest/download/PaisaPulse.apk`, iPhone steps, QR on desktop via vendored `js/qrcode.js`), `/privacy`, `/delete-account`, `404.html`.
- Home: hero SMS → transaction loop, numbers strip (counters), **Try it live** (paste an SMS; `js/parser.js` is a JS port of BankAlerts, tested by `scripts/website-parser.test.mjs`, CI job `website`; brands + category rules in `js/data.js` are generated by `node scripts/gen-website-data.mjs` — regenerate when brands change), sticky "How it works", 3D coverflow of real CI screenshots (`img/shots/*-light|dark.webp`, swapped by theme), features, privacy receipt, pricing, FAQ.
- `js/site.js` (all pages): night mode (follows the system; toggle stored in localStorage `theme`, `data-theme` on `<html>`, colours are CSS tokens in `styles.css`), device detection for download links, magnetic buttons, reveals (`.js .reveal`, so content shows without JS). Cross-page view transitions in CSS.
- Search/AI: canonical + Open Graph/Twitter tags (`img/og.jpg`, 1200×630), JSON-LD (Organization, WebSite, MobileApplication, FAQPage on home — keep the FAQ JSON-LD in step with the visible FAQ; BreadcrumbList + HowTo on /download), `robots.txt` (AI crawlers allowed), `sitemap.xml`, `llms.txt` + `llms-full.txt` (facts for AI assistants; keep them true when features change), `site.webmanifest`.
- Layout: floating pill nav (`.nav`, shrinks on scroll, highlights the current section; ≤1000px a menu button opens the links under it). Inputs stay ≥16px (iOS zooms smaller fields). `html, body { overflow-x: clip }`; grids use `minmax(0, …)`. Breakpoints: ≤400 / ≤560 phones, ≤720 story phone-on-top, 721–1024 tablets (two-column hero + story), short landscape (≤520px tall) drops the sticky phones, ≥1600 / ≥2200 widen `--maxw`. Scale with `zoom`, not `transform`, on elements that have a load animation. Check new work with an overflow audit at 320–2560px.
- Home also has an iPhone / Android switch on the screenshot coverflow (`img/shots/android-*.webp` from the Android CI screenshots), a **feature tour** rail (`.rail` / `.tcard`, ten cards with CSS-drawn mini screens; keep their claims true), and a back-to-top button with a scroll-progress ring (`site.js`, every page).
- Positioning (user, 26 Nov 2026): lead with what other apps don't do. Hero copy says it's more than a tracker; **Only in Paisa Pulse** bento (`#only`, `.bento`/`.bx`, `grid-auto-flow: dense`, keep the units a multiple of 3); **comparison table** (`#compare`, `.ctable`) uses generic app types only (SMS trackers, bank-linking apps, split apps, manual trackers) — never name competitors; "Everything in it" index lists all 26 features. Keep llms*.txt "What makes it different" and the FAQ JSON-LD in step.
- Hero entrance: the phone stage animates in first (`stageIn`), the SMS loop starts at 450 ms, copy follows; on ≤760px the stage sits above the copy (`order: -1`, `zoom: .8`, bottom fade). Bento tiles each have a looping scene: `.demo[data-steps="ms,ms,…"][data-loop]` — `main.js` adds cumulative `st1…stN` classes while on screen (final frame with Reduce Motion); `[data-count-to][data-at]` counters tick at that step; CSS per scene (`.d-sms`, `.d-shot`, `.d-fx`, `.d-split`, `.d-stmt`, `.d-backup`, `.d-fore`, `.d-voice`, `.d-loan`, `.d-clean`).
- Hero height is capped (`min(100svh - 64px, 860px)`) so tall windows don't leave a gap. Screenshot coverflow has dots + arrows (`.car-ctrl`, follows the visible platform), neighbours peek on phones (`62vw` shots), and touch devices get a one-time nudge when it scrolls into view.
- Pro is "coming soon" (mailto, no backend yet).

### Store readiness (Nov 2026)
- `docs/STORE.md`: build commands, review notes, privacy label / Data safety answers, monetisation rule (IAP on App Store, Play Billing on Play; website billing only for GitHub builds).
- Android flavors `github` (default CI APK) and `play` (`:app:bundlePlayRelease`, CI artifact `android-play`): `BuildConfig.STORE_BUILD` hides self-update and the SMS row; `src/play/AndroidManifest.xml` removes `RECEIVE_SMS` + `SmsAlertReceiver`. Gradle tasks are now `testGithubReleaseUnitTest` / `assembleGithubRelease`.
- iOS: `PaisaDistribution` Info.plist key from build setting `PAISA_DISTRIBUTION` (default `sideload`; `appstore` hides the updater via `Distribution.isAppStore`), `ITSAppUsesNonExemptEncryption = NO`, `Shared/PrivacyInfo.xcprivacy` (UserDefaults CA92.1 + 1C8F.1; collected data only for accounts). `sidestore` removed from LSApplicationQueriesSchemes (open() doesn't need it).
- Android `DisclosureDialog` (Common.kt) before contacts, SMS and notification access. Backups exclude `paisa_secure`, `paisa-cloud`, `cloud-cache.json`.
- Website: `/privacy`, `/delete-account`; both apps link the privacy policy at the bottom of Settings.

### Share a screenshot (Nov 2026, both apps)
- iOS share extension `apple/Share` (target `PaisaShare`, bundle `com.paisapulse.app.share`, App Group): reads images with `ScreenText.read` (Vision, in `Capture.swift`), parses with `ScreenshotParser`, shows editable cards, Save writes `Txn(source: "screenshot")` into the shared SwiftData store. Its sources are `Share`, `Shared`, `App/Import/Capture.swift`, `App/Import/Narration.swift`; `Rx` moved to `Shared/Rx.swift` for that. The user installs over USB (iloader), no SideStore, so app + widget + share = the 3 free slots: ask before adding any other extension.
- Android: `SEND`/`SEND_MULTIPLE image/*` intent filter on `MainActivity` → `Ui.handleShare` → `Route.Capture("screenshot")` reads `Ui.sharedImages`.
- Parser cases for more apps: Android `ScreenshotAppsTest`, iOS `ScreenshotAppsTests` (same inputs). Golden `capture-golden.txt` line 1 lost its warning (GPay "Completed" now counts as sent).

### V2: payment method, currencies, planning (Nov 2026, both apps)
- Logic: Swift `Shared/V2.swift`, Kotlin `logic/V2.kt` (tested: `V2Test`, iOS `V2Tests`): `PaymentMethod` (ids upi, debit_card, credit_card, net_banking, neft, imps, rtgs, cash, cheque, wallet, auto_debit, other; `guess(accountType, cardKind)`, `fromText` for narrations), `Fx.rate(from, to, inrPer)`, `ForexMarkup` (basis points; default 413 = 3.5% + 18% GST), `BaseCurrency.convert` / `BaseCurrencyChange`, `TripKinds`, `TripMath` (status, summary, wallets, `budgetTxns` drops trips with `countInBudgets == false`; use it wherever budgets are computed).
- Reference data: `scripts/gen-reference-data.py` generates `Shared/ReferenceData.swift` + `logic/ReferenceData.kt` (`Banks`: 68 banks/wallets with colours, `World`: countries → currency + symbol). Regenerate both, never edit by hand.
- **Main currency** (`baseCurrency` setting, default INR): `amount` is in it; `Money.base` drives formatting (INR lakh/crore, others thousands, compact K/M/B). Changing it converts the whole backup JSON at today's rate (or only relabels), after a backup.
- Models: `Txn.paymentMethod`, `tripId`, `tripItemId`, `walletId`; `PaymentCard.forexMarkupBps`; `Trip` (places as JSON on iOS `placesJSON`), `TripItem`, `TripWallet` (currency nil = main, amount in its minor units, rate = main per unit). Backup keys `trips`, `tripItems`, `tripWallets`; settings `baseCurrency`, `converterCurrencies`, `customAccent`.
- Trip people = a `SplitGroup` (`trip.groupId`); settle up through the group screen. Quick Add picks the ongoing trip and its currency, shows Trip / For / Paid from.
- Screens: iOS `More/PlanningViews.swift`, `More/MoneyViews.swift`; Android `ui/screens/Planning.kt`, `ui/screens/MoneyScreens.kt`. Home section key `trips` ("Planning").
- Accent `custom` uses `customAccent` (any colour). Home-screen icons can't be custom colours (they must be bundled): 11 presets with previews (`IconPreview-*` image sets / `drawable-nodpi/icon_preview_*`), Android aliases `.Icon<Name>`.
- Not built: sharing a trip between phones (needs a cloud service and account chosen by the user).

### Accounts and sharing (Nov 2026, both apps)
- **Supabase**, only for shared things (user decision: personal ledger stays on the phone). Schema + all access in `supabase/migrations/0001_accounts.sql`: tables have RLS on and no policies; the apps call only the security definer functions (`ensure_profile`, `update_profile`, `find_people`, `match_contacts`, `connect`, `create_invite`/`accept_invite`, `save_space`/`leave_space`, `save_expense`/`delete_expense`/`respond_share`, `save_settlement`/`respond_settlement`, `sync(since)`, `mark_read`, `export_my_data`, `delete_account`). Add new migrations as new numbered files; never edit an applied one. Test SQL locally: `sudo service postgresql start`, then apply an `auth` stub (schema auth, `auth.users`, `auth.uid()` from `request.jwt.claim.sub`, roles anon/authenticated, schema extensions) and the migration.
- **CI `cloud` job** (`.github/scripts/supabase-setup.py`, Management API): applies migrations once each (`public._paisa_migrations`), turns email confirmation off (`mailer_autoconfirm`), outputs URL + publishable key → Android `BuildConfig.SUPABASE_URL/KEY`, iOS `Shared/CloudConfig.swift` (committed empty; CI overwrites). Needs secret `SUPABASE_ACCESS_TOKEN` (optional variable `SUPABASE_PROJECT_REF`). The Management API and Supabase are blocked from this environment: only CI can reach them. **Never commit tokens** (`.env` is gitignored).
- Sign-in: **email + password, no emails sent** (user decision, 23 Nov 2026): `/auth/v1/signup` and `/auth/v1/token?grant_type=password`, change password with `PUT /auth/v1/user`, 8+ characters (checked in the apps). **Forgot password:** `/auth/v1/recover` emails a 6-digit code, `/auth/v1/verify` (type `recovery`) signs in, then `PUT /auth/v1/user` sets the new password. Emails go through **Resend** SMTP on the user's domain `nishitrk.tech` (secret `RESEND_API_KEY`, optional variable `MAIL_FROM`, default `no-reply@nishitrk.tech`; CI sets Supabase's SMTP + recovery template). The domain must be verified in Resend. Sign-up still needs no email.
- Finding people: @username prefix, exact email, exact phone; phones are stored and matched as sha256 of the last 10 digits (`CloudLogic.phoneHash` = SQL `_phone_hash`). Invites: code + `docs/invite/index.html` (`https://porifiro123.github.io/paisa-pulse/invite/#c=CODE&n=Name` → `paisapulse://invite?c=CODE`).
- **Sync model** (`logic/CloudLogic.kt`, `Shared/CloudLogic.swift`, tested by `CloudTest` / `CloudTests`): your phone is the truth for what you record. `plan` turns splits with linked friends (`Friend.userId`, backup key `userId`) into expenses / settle-ups / groups / trips (ids = local ids, so they must stay UUIDs); `pushed` hashes in prefs (`cloud.pushed`) find changes and deletions. Others' items come back via `mirror`: `SplitEntry` ids `c:<expense>:<user>` and `c:settle:<id>` (never pushed back), friends with id = their user id, and their groups/trips with id = space id (trip.groupId = space id). Pending shares/settle-ups live only in the cloud cache and the Inbox until accepted. Settle-up entries are recognised by the notes "Settled up" / "Paid by UPI".
- Clients: Android `cloud/Cloud.kt` (HttpURLConnection, session in Keystore-encrypted prefs, cache `files/cloud-cache.json`, `CloudWorker` every 15 min, debounced sync on Store changes), screens `ui/screens/Account.kt` (Account, People, Inbox, `AccountRow`, `FriendAccountGroupContent`). iOS `App/Cloud/Cloud.swift` (URLSession, Keychain, cache in Application Support, BGAppRefresh `com.paisapulse.app.sync`, push on `ModelContext.didSave`), `App/Cloud/AccountViews.swift`. Notifications are local (shown when a sync finds new inbox items); remote push needs the paid Apple account. Subscriptions/monetisation: later.
