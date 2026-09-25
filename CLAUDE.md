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
- **Figma:** use the `nishitkirani2020@gmail.com` account (Starter, 20 read calls/month; the college account's quota is used up). The full node tree of page `0:1` is saved in `design/figma-page-0-1.xml`, so don't spend a call re-reading it. Call `get_design_context` or `get_screenshot` once per node when you build it.

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
