# Paisa Pulse — Product Spec v3
**Manual-first · React Native (Expo) · Liquid Glass · Local-first · Free**

> v2 changes: the first release covers **manual transaction CRUD only**, and the stack moves from Flutter to **React Native with Expo**. Auto-capture (SMS/notifications/Shortcuts), statement import and sync move to later phases (see §11).
>
> v3 changes: the design language is now **Apple Liquid Glass (iOS 26)**, built with native system components wherever possible so it looks and behaves like Apple's own apps. Android gets the Material 3 equivalent. See §5 and the new §5A.

---

## 1. Product Vision
A free, private, beautiful money tracker for India. v1 makes **manual entry so fast and pleasant** that logging a transaction takes under 3 seconds. Automation comes later on top of a solid core.

**Promise:** "Fast to log, beautiful to look at, your data never leaves your phone."

## 2. v1 Scope

### In scope
- **Transactions CRUD:** create, view, edit, delete (with undo)
- **Accounts CRUD:** bank, credit card, cash, wallet
- **Categories CRUD:** with icon/emoji and colour
- Transaction list grouped by day, with search and filters
- Monthly summary (spent, received, net)
- Light / Dark / AMOLED themes
- Local encrypted storage, biometric/PIN lock
- Export to CSV/JSON; import from its own JSON backup

### Out of scope for v1
- Automatic capture (SMS, notifications, iOS Shortcuts)
- Bank statement import
- Budgets, recurring transactions, goals
- Cloud sync, multi-device, sharing
- Charts beyond the monthly summary

## 3. Target User
Indian salaried users aged 22–40 with 2–4 bank accounts, 1–3 credit cards and mostly UPI spending, on Android or iPhone. They want a clean, fast tracker without ads, loans or sign-ups.

## 4. Core Features (v1)

### 4.1 Transactions
| Operation | Behaviour |
|---|---|
| **Create** | FAB → Quick Add sheet. Required: amount, type, account. Optional: category (defaults to "Uncategorised"), date/time (defaults to now), note, payee. |
| **Read** | Activity list grouped by day with sticky daily totals. Tap a row to open the detail view. |
| **Update** | Edit from the detail view (same sheet as Create, pre-filled). Long-press for multi-select bulk edit of category and account. |
| **Delete** | Swipe left → delete → toast with **Undo** (5s). Implemented as a soft delete, purged after 30 days. |
| **Duplicate** | "Duplicate" action on the detail view, handy for repeat spends like a daily coffee. |

**Transaction types:** Expense, Income, Transfer (between two own accounts; a credit card bill payment is a Transfer, not an expense).

**Validation**
- Amount > 0, stored as integer **paise** (no floating point)
- Transfer requires distinct from/to accounts
- Date cannot be more than 1 year in the future

### 4.2 Accounts
- Fields: name, type, institution (free text), last 4 digits (optional), opening balance, colour, icon
- Credit card extras: credit limit, statement day, due day (stored now, used later)
- Balance = opening balance + sum of its transactions (computed, never stored)
- Archive instead of delete when an account has transactions

### 4.3 Categories
- Two-level nesting (e.g., Food → Groceries)
- Separate sets for Expense and Income
- Reorder, rename, recolour, archive, merge (merging moves all transactions)
- **Starter pack for India:** Food & Dining, Groceries, Transport (Fuel, Metro/Auto/Cab), Shopping, Bills & Utilities (Electricity, Mobile/Internet, DTH), Rent, EMI/Loans, Health, Entertainment, Subscriptions, Travel, Education, Gifts & Donations, Investments, Personal Care, Family; Income: Salary, Freelance, Interest, Refund, Cashback, Other

### 4.4 Search & Filters
- Free-text search on note and payee
- Filters: date range, type, account(s), category(ies), amount range
- Saved filters come in v1.1

### 4.5 Settings
Currency display (₹, lakh/crore grouping), month start day (e.g. 1st or salary day), week start, theme, app lock, export/backup, about.

## 5. Design Language & Screens

### 5.0 Liquid Glass design language
Apple's Liquid Glass (iOS 26) is a translucent material that refracts and reflects the content behind it and reacts to touch. The rule Apple follows in its own apps: **glass is for the navigation and control layer that floats above content, not for the content itself.** Lists, cards and numbers stay solid and readable; bars, buttons, sheets and menus are glass.

**Principles**
1. **Content first, controls float.** Transactions scroll edge-to-edge underneath a floating glass tab bar and glass toolbar buttons.
2. **Native before custom.** Use real system components (tab bar, navigation bar, sheets, menus, search, date pickers, switches). They get Liquid Glass, accessibility and future iOS updates for free. Custom glass (`GlassView`) only where no system component exists (e.g. the hero card on Home, the keypad).
3. **Glass never on glass.** Don't stack glass surfaces; group nearby glass buttons in a `GlassContainer` so they merge like Apple's controls do.
4. **Concentric, rounded geometry.** Corners match the device's display corners; nested elements use smaller concentric radii. Capsule-shaped buttons.
5. **Colour from content.** Mostly monochrome chrome (white/black text via `DynamicColorIOS`) with one accent colour and colour-coded categories. The glass adapts to light or dark content behind it automatically.
6. **Motion that feels physical.** Spring animations, zoom transitions from a row into its detail screen, the tab bar minimising on scroll, sheets morphing from the button that opened them.
7. **Legibility and accessibility always win.** Honour Reduce Transparency (glass becomes frosted/solid), Increase Contrast, Reduce Motion, Dynamic Type and VoiceOver.

**Typography & icons:** San Francisco system font (SF Pro Rounded for large amounts, tabular digits), Dynamic Type sizes, **SF Symbols** for every icon (Material Symbols on Android).

**Haptics:** selection tick on keypad and pickers, success on save, warning on delete, soft impact when the sheet snaps between heights.

### 5.1 Platform strategy
| | iOS 26+ | iOS 18 and earlier | Android |
|---|---|---|---|
| Tab bar | Native Liquid Glass tab bar (minimises on scroll, separate search tab) | Classic translucent iOS tab bar | Material 3 bottom navigation |
| Custom glass surfaces | `GlassView` (native `UIGlassEffect`) | Blur fallback (`expo-blur`) | Blur/tonal surface fallback |
| Icons | SF Symbols | SF Symbols | Material Symbols |
| Sheets, menus, pickers | Native iOS | Native iOS | Native Material equivalents |

Liquid Glass itself exists only on iOS 26+. Android users get the same layout and flow with Material 3 styling rather than a fake glass imitation, which keeps the app feeling native on both platforms.

### 5.2 Navigation
- **Native tabs** (Expo Router Native Tabs): **Home · Activity · Accounts · Settings**, plus a **search tab** shown as its own glass button on the right of the bar, like Apple Music and the App Store.
- **Add button:** a glass capsule "+" button floating above the tab bar (like Notes/Reminders). Tap opens Quick Add; long-press opens a native context menu: Expense / Income / Transfer.
- **Large titles** that collapse into a compact inline title on scroll, with glass toolbar buttons (filter, edit) in the navigation bar.
- **Stack navigation** with native swipe-back gesture everywhere.

### 5.3 Onboarding (≤ 60 seconds, no sign-up)
Full-bleed animated gradient background with glass cards floating on top (the only screens with a decorative background, so the glass has something to refract).
1. Welcome + privacy promise
2. Add your accounts (suggestions: Cash, a bank account, a credit card)
3. Pick accent colour + app icon style (default, dark, tinted, clear)
4. Optional: turn on Face ID / fingerprint lock

### 5.4 Home
- **Large title** "September" (current month); tap it for a native pull-down menu to jump to another month.
- **Hero glass card:** "Spent this month" in large rounded numerals, income and net beneath, sitting over a soft accent-coloured gradient so the glass reads. Swipe sideways to change month.
- **Recent transactions:** inset grouped list (like Settings/Wallet), last 5 with "See all".
- **Top categories:** horizontal scroll of category capsules with amounts.
- **Empty state:** SF Symbol illustration + "Add your first expense" glass button.

### 5.5 Quick Add / Edit Sheet
- **Native sheet with detents** (medium ↔ large), grabber, and glass background on iOS 26; morphs out of the "+" button.
- Top: **segmented control** Expense / Income / Transfer, colour-coded.
- Large amount display + **custom glass keypad** (supports simple maths such as `120+45`), selection haptic per tap.
- **Recent categories** as capsules, then "All categories" grid.
- Account and date as native menu/picker rows (compact date picker: Today / Yesterday / pick).
- Glass **Cancel (✕)** and **Save (✓)** buttons in the sheet toolbar, as in iOS 26 system sheets.
- **Save in 2 taps** for the common case: amount → category → Save.

### 5.6 Activity
- Large title with a **native search bar** (also reachable from the search tab) and a glass filter button.
- Grouped by day with sticky headers showing the daily total.
- Row: category SF Symbol in a coloured circle, payee/note, account, amount (red expense / green income).
- **Native swipe actions:** swipe left → Delete (destructive, full swipe), swipe right → Duplicate.
- **Long-press → context menu with preview:** Edit, Duplicate, Change Category, Delete.
- Tab bar minimises as you scroll down; tap the Activity tab again to scroll to top.

### 5.7 Transaction Detail
- **Zoom transition** from the tapped row.
- Large amount, category, account, date/time, note, created/edited timestamps in an inset grouped list.
- Toolbar glass buttons: Edit, Share (native share sheet), and a "…" menu with Duplicate / Delete.

### 5.8 Accounts
- Wallet-style stacked cards per account (solid content cards, not glass), balance on each.
- Net worth total at the top; tap a card for its own transactions and details.
- Edit mode with drag-to-reorder.

### 5.9 Settings & Categories Manager
- Standard iOS Settings-style inset grouped lists with native switches and pickers.
- Categories: drag-to-reorder, tap to edit (name, SF Symbol, colour, parent), swipe to archive, "Merge into…" action.

## 5A. "Feels like Apple's own apps" checklist
Everything major iOS apps provide, grouped by when we build it.

### v1 (manual core)
- [ ] Liquid Glass native tab bar with separate search tab; minimise on scroll
- [ ] Large collapsing titles, glass toolbar buttons, native back-swipe
- [ ] Native sheets with detents and grabber; sheet morphs from its button
- [ ] Context menus with previews on long-press; pull-down menus on buttons
- [ ] Native swipe actions on list rows
- [ ] Zoom transition from list row to detail
- [ ] Native search bar with live filtering
- [ ] Native controls: segmented control, date picker, switches, pickers
- [ ] SF Symbols throughout (with symbol effects such as bounce on save)
- [ ] Haptics (selection, success, warning, impact)
- [ ] Light, dark, and automatic appearance; accent colour choice
- [ ] Face ID / Touch ID lock; privacy blur in the app switcher
- [ ] Dynamic Type, VoiceOver labels, Reduce Transparency/Motion, Increase Contrast
- [ ] Native share sheet (share a transaction or export file)
- [ ] Undo via toast and shake-to-undo
- [ ] Pull-to-refresh style interactions where relevant; tap tab to scroll to top
- [ ] App icon in iOS 26 variants: default, dark, tinted, clear (Liquid Glass icon made in Apple's Icon Composer)

### v1.x (polish)
- [ ] Home Screen widgets (small/medium/large) and Lock Screen widgets: month spend, budget progress
- [ ] Interactive widget button: "Add expense"
- [ ] Control Center control and Action Button shortcut for Quick Add
- [ ] Siri / Shortcuts / Spotlight via App Intents ("Log ₹250 for lunch")
- [ ] Home-screen quick actions (long-press app icon → Add Expense / Add Income)
- [ ] Alternate app icons chosen in Settings
- [ ] iPad layout with sidebar; Mac via Catalyst/iPad app (optional)

### Later
- [ ] Live Activity / Dynamic Island for a daily budget or a trip-spend tracker
- [ ] Apple Watch quick-add complication
- [ ] iCloud backup (encrypted) as an option

## 6. Data Model

SQLite via **Drizzle ORM** (TypeScript schema). IDs are UUIDv7 strings (sortable and sync-friendly later). Money is integer paise.

```ts
// accounts
id: text PK
name: text
type: 'bank' | 'card' | 'cash' | 'wallet'
institution: text | null
last4: text | null
openingBalance: integer   // paise
currency: text            // 'INR'
creditLimit: integer | null
statementDay: integer | null
dueDay: integer | null
color: text
icon: text
sortOrder: integer
archivedAt: integer | null
createdAt: integer
updatedAt: integer

// categories
id: text PK
parentId: text | null → categories.id
kind: 'expense' | 'income'
name: text
icon: text
color: text
sortOrder: integer
archivedAt: integer | null

// transactions
id: text PK
type: 'expense' | 'income' | 'transfer'
amount: integer           // paise, always positive
accountId: text → accounts.id
toAccountId: text | null  // transfers only
categoryId: text | null → categories.id
payee: text | null
note: text | null
occurredAt: integer       // epoch ms
source: 'manual'          // later: 'notification' | 'sms' | 'shortcut' | 'import'
deletedAt: integer | null // soft delete
createdAt: integer
updatedAt: integer

// settings
key: text PK
value: text               // JSON
```

**Indexes:** `transactions(occurredAt)`, `transactions(accountId, occurredAt)`, `transactions(categoryId)`.

**Why `source` exists now:** auto-capture in later phases writes into the same table, so no migration pain later.

## 7. Tech Stack (React Native)

| Layer | Choice | Why |
|---|---|---|
| Framework | **Expo** (latest stable SDK), TypeScript | Run on your phone via Expo Go; EAS for store builds |
| Navigation | **Expo Router** with **Native Tabs** | Real system tab bar: Liquid Glass on iOS 26, Material 3 on Android. Import path is `expo-router/unstable-native-tabs` on older SDKs and `expo-router/native-tabs` on newer ones |
| Liquid Glass surfaces | **expo-glass-effect** (`GlassView`, `GlassContainer`, `isLiquidGlassAvailable`) | Native `UIGlassEffect` on iOS 26+, works in Expo Go; falls back to a plain view elsewhere |
| Glass fallback | **expo-blur** | Frosted blur on iOS < 26 and Android |
| Icons | **expo-symbols** / expo-image `sf:` source | SF Symbols with animations; Material Symbols on Android |
| Menus & native controls | Expo Router stack header menus/toolbar + **@expo/ui** (SwiftUI/Jetpack Compose controls) | Native context menus, pull-down menus, segmented controls, pickers |
| Transitions | Expo Router Apple zoom transition (iOS 18+) | Row → detail zoom |
| Database | **expo-sqlite** + **Drizzle ORM** | Typed schema, migrations, live queries |
| Encryption | SQLCipher option of expo-sqlite (needs a dev build, not Expo Go) | Encrypted at rest; turn on once past prototyping |
| State | Drizzle live queries for data; **Zustand** for UI state | Minimal boilerplate |
| Lists | **@shopify/flash-list** | Smooth long transaction lists |
| Animation | **react-native-reanimated** + **react-native-gesture-handler** | 60/120fps springs, swipe actions |
| Sheets | Native **form sheets** via Expo Router Stack (`presentation: 'formSheet'` with detents) | System sheet gets Liquid Glass automatically on iOS 26 |
| Charts (later) | **@shopify/react-native-skia** / Victory Native | Custom, high-performance charts |
| Haptics | expo-haptics | |
| App lock | expo-local-authentication + expo-secure-store | Biometrics + PIN storage |
| Export | expo-file-system + expo-sharing | CSV/JSON out |
| Dates | date-fns | Month/period maths |
| IDs | uuidv7 | |
| Forms | react-hook-form + zod | Validation |
| Testing | Jest + React Native Testing Library; Maestro for E2E | |

> **Expo Go caveat:** Expo Go runs most of the above, including `expo-glass-effect` and native tabs, but not SQLCipher encryption or widgets. Build and test the UI in Expo Go first, then switch to a **development build** when adding encryption, widgets and, later, native capture modules.
>
> **Liquid Glass requirements:** you only see real Liquid Glass on an iPhone running **iOS 26+**, and store builds must be compiled with **Xcode 26+** (EAS Build handles this). Always check `isLiquidGlassAvailable()` and design the fallback, not just the glass version.
>
> **Widgets, Control Center controls, App Intents:** these need small Swift targets alongside the React Native app (e.g. via Expo config plugins such as `@bacons/apple-targets`). Planned for v1.x.

## 8. Project Structure

```
app/
  (tabs)/
    index.tsx            # Home
    activity.tsx
    accounts.tsx
    settings.tsx
  transaction/[id].tsx   # Detail
  add.tsx                # Quick Add / Edit (modal)
  categories.tsx
  onboarding/
src/
  db/
    schema.ts
    client.ts
    migrations/
    seed.ts              # starter categories
  features/
    transactions/        # queries, mutations, hooks, components
    accounts/
    categories/
  ui/                    # design system: Button, Card, Keypad, AmountText, Sheet
  theme/                 # tokens, light/dark/amoled
  lib/                   # money.ts (paise ↔ ₹, lakh/crore format), dates.ts
```

**Money helpers:** `toPaise("1,250.50") → 125050`; `formatINR(125050) → "₹1,250.50"`; lakh/crore grouping via `Intl.NumberFormat('en-IN')`.

## 9. Privacy & Security
- No accounts, no servers, no analytics on financial data
- Database stays on the device (encrypted once on a dev build)
- Optional biometric/PIN lock; blur the screen in the app switcher; "hide amounts" toggle
- Backups are files the user exports themselves
- Open source recommended (AGPL-3.0 or MIT)

## 10. Definition of Done (v1)
- [ ] Create, edit, delete (with undo) and duplicate transactions for all three types
- [ ] Accounts and categories fully manageable; balances correct including transfers
- [ ] Median time to log an expense < 3 seconds
- [ ] Activity list scrolls smoothly with 10,000 transactions
- [ ] Works on Android and iOS, light and dark mode
- [ ] Liquid Glass on iOS 26+ with clean fallbacks on older iOS and Android; everything in the §5A v1 checklist done
- [ ] Legible with Reduce Transparency and Increase Contrast turned on
- [ ] Export to CSV and restore from JSON backup work round-trip
- [ ] Unit tests for money maths, balance calculation and transfer logic

## 11. Roadmap

| Phase | Timeline | Scope |
|---|---|---|
| **1 — Manual core (v1)** | Weeks 1–6 | Everything in §2–§10 |
| **2 — Polish** | Weeks 7–10 | Budgets, recurring transactions, insights charts, home-screen widgets, saved filters, custom month start |
| **3 — Import** | Weeks 11–14 | CSV/PDF statement import with column mapping (Axis, Bank of Baroda, HDFC, ICICI, SBI templates) |
| **4 — Auto-capture** | Months 4–6 | Android: notification-listener native module (Expo Modules API) with on-device parser + review inbox. iOS: App Intent for a Shortcuts "Message contains" automation. De-duplication. |
| **5 — Intelligence & sync** | Months 7+ | Rules engine, natural-language quick add, receipt OCR, encrypted device-to-device sync |

## 12. Costs
| Item | Cost |
|---|---|
| Development & testing via Expo Go | Free |
| Google Play developer account | $25 one-time |
| Apple Developer Program | $99/year (only needed to publish on iOS) |
| EAS Build | Free tier is enough to start |
| Backend | None |
