# Changelog

Newest first. Every push to `main` becomes a GitHub Release `build-<number>` with
`PaisaPulse.apk` (Android) and `PaisaPulse.ipa` (iPhone, free Apple ID). See [docs/INSTALL.md](docs/INSTALL.md).

## [Unreleased]

- Both apps + website: bank messages that say "debited towards <name> for Rs …" (Bank of Baroda, UPI mandates) now get the right payee instead of the mandate ID, and UPI mandate debits (UMN) count as Auto-debit. Website: long payee names wrap instead of overlapping the amount, and tapping the SMS box on a phone keeps the box and keyboard both on screen.
- Website: **Try it live** (paste a bank SMS and see the transaction, read in the browser with the apps' own rules), real app screenshots in a 3D carousel, night mode, a download page that picks Android, iPhone or a QR code, link preview image, smoother motion (counters, buttons that follow the cursor, page transitions), and search/AI readiness (structured data, sitemap, robots.txt, llms.txt).
- Store readiness: privacy policy (website /privacy, linked from Settings on both apps) and an account deletion page (/delete-account); iOS privacy manifest and encryption declaration; App Store build switch (`PAISA_DISTRIBUTION=appstore`) and a Google Play build (`PaisaPulse-play.aab`) without self-update, SideStore links or the SMS permission; "why we ask" screens before contacts, SMS and notification access on Android; sign-in data left out of Android backups. Submission notes in `docs/STORE.md`.
- Both: **Net Worth** shows today's total and the change since last month, a 6M / 1Y / 2Y chart, and what you have vs owe by account type.
- Both: **Monthly Recap** adds "What changed" (categories that went up or down most vs last month) and **Full Report (PDF)**: totals, every category against last month, and the biggest expenses, ready to share or print.
- Both: **Bills** (Settings › Money › Bills): card bills and recurring bills due in the next month, soonest first, with the total; "Record Payment" adds the card payment from your bank in one tap (with Undo). Bill reminders now also cover recurring bills (2 days before).
- Both: **Auto-capture.** Bank SMS and payment alerts become drafts to confirm (Home › "N bank messages to review"). Android reads notifications (bank apps, SMS app, GPay, PhonePe, Paytm) and/or SMS; iPhone uses a Shortcuts "Message" automation with the new **Log Bank Message** action. Read on the phone; OTPs, requests and due reminders are ignored; each alert is added once.
- Both: CRED's payment details screen (₹ read as "₴", dates like "25th nov'26") is now read; your own UPI ID ("paid from UPI ID") is no longer taken as the payee.
- iPhone: the share sheet showed no accounts or categories when the installer (iloader) didn't tell the extension its App Group. The group is now read from the signing profile too, and an old database or settings kept outside the group are moved in once.
- Both: **Polish.** Big amounts roll when they change; animations are a snappy 0.2 s; buttons and cards shrink slightly when pressed; loading lists show skeleton rows.
- Both: **Celebrations.** Confetti and a success tap when you reach a goal, finish a month under budget, or settle up with everyone.
- Both: a slow, living colour shader on the Home balance card and progress bars (30 fps, paused in Low Power / Battery Saver and with Reduce Motion).
- Both: haptics match toasts (success / error), a soft tap while reordering.
- Both: an eye button on Home hides amounts in one tap; with App Lock or hidden amounts on, the app-switcher preview is covered by the logo.
- Both: launch screen matches the app's background (no white flash) and shows the ₹ logo; the same logo is used in onboarding, the lock screen and sign-in. Dark and tinted app icons (iOS), themed icon (Android 13+).
- CI: screenshots at the largest text size (iOS `*-ax5.png`, Android `*-fontx2.png`).
- Both: **Forgot password?** on the sign-in screen emails a 6-digit code (sent through Resend from nishitrk.tech) to set a new password.
- Both: CRED screenshots where the ₹ sign is read as a dot ("·1,000") now work.
- iPhone: back to the real iOS tab bar (Liquid Glass you can drag across), with + as its round button. Quick Add gained a "From Screenshots" button; templates stay in Quick Add.

- Both: accounts now use **email and password** (Create Account / Sign In), with no emails sent; change your password in Account. There's no password reset yet.

- Both: **Paisa Pulse accounts (optional).** Settings › Sign In: email a 6-digit code, pick a @username, add your name, UPI ID and (optionally) phone. Only shared things go to the server; your own accounts and transactions stay on the phone.
- Both: **People.** Find friends by @username, email or phone, match your contacts (numbers are hashed on the phone first), or share your invite QR / link / code. Link any friend in your splits to their account from their page.
- Both: **Shared splits.** Splitting with a linked friend sends it to their phone: they accept or decline their share, and it lands in their balance with you. "Friend paid", "they owe me" and settle-ups go across too (the other person confirms a settle-up). Groups and trips with linked friends are shared, so everyone sees the trip, its budget items and the group's spending.
- Both: **Inbox** with what's waiting for you and what happened, plus notifications when the app checks in the background (Android every ~15 minutes; iPhone when iOS allows). Real push needs the paid Apple account, later.
- Both: download your account data, and delete your account (removes everything you shared from the server).
- CI: a `cloud` job sets up the Supabase database from `supabase/migrations` and gives both apps the project URL and public key. Needs the `SUPABASE_ACCESS_TOKEN` repository secret. The committed `.env` was removed.

- Both: **Planning.** Plan trips, vacations, weekends, work trips, events, outings, rides or anything else. Each type comes with ready budget items (more for trips abroad), destinations set their currencies, track cash or forex you carry, add who's going (a split group with settle-up), see spent vs budget per item, per person and per currency, share a summary picture, archive or delete. While a trip is on, new expenses link to it and default to its currency. Choose per trip whether it counts in your monthly budgets. Home shows the trip that's on or coming up; also in Settings › Planning.
- Both: **Payment method** on every transaction (UPI, debit/credit card, net banking, NEFT, IMPS, RTGS, cash, cheque, wallet, auto debit), guessed from the account and card, read from statement narrations, and UPI for screenshots. Insights shows "How you paid".
- Both: **Foreign currencies everywhere.** The original amount shows on rows and the detail screen with its locked rate (fix it to match your statement). Each card has its own forex markup (percent, plus GST, editable); it's added when you pay in another currency. Insights has "Spent abroad".
- Both: **Main currency** (Settings › See › Main Currency): ₹ by default, any currency possible; convert everything at today's rate or just change the symbol (a backup is saved first).
- Both: the **converter** compares one amount across as many currencies as you like; tap a row to type in it.
- Both: **bank picker** with 68 Indian banks and wallets (sets the name and colour).
- Both: **accent colour** from presets or any colour (colour wheel on Android, system colour picker on iPhone); **app icon** picker shows real previews, with six new icons (Ocean, Rose, Forest, Gold, Sunset, Graphite).

- iPhone: Insights and Monthly Recap no longer crash (the share picture was drawn while the screen was being built; it's now drawn when you tap Share).
- iPhone share sheet: when no amount is found you can "Add It Myself" (date guessed from the picture), every card's amount is editable, and "What Paisa Pulse read" shows the text it saw.

- iPhone: screenshot reading works again. Vision rejected the "en-IN" language, so nothing was read (in the share sheet and in From Screenshots); large pictures are scaled down first.
- CRED receipts and payment screens: "<you> paid" + name, the name above the amount, "23rd nov'26" dates. The share sheet also opens pictures apps hand over as files, and says so when it can't.

- iPhone: the end of every list (pushed screens too) clears the floating tab bar again; forms no longer hide under the keyboard.
- Both: the month-end forecast shows whole rupees; card bills read "Due in 9 days" on both phones.
- Android: Activity's search text is no longer cut off; lists end above the navigation bar on 3-button phones.

- Both phones: slide your finger across the tab bar to switch tabs again; a glass lens follows your finger.
- iPhone: Activity's search field sits at the top, so it no longer collides with the tab bar.
- New README with every feature, and the iPhone install guide now covers iloader over USB.

- Both phones: **share a payment screenshot from any UPI app** (GPay, PhonePe, Paytm, BHIM…) to Paisa Pulse. It reads the amount, payee, date and account on the phone, you check them and tap Save. iPhone uses a share extension (the 3rd free-Apple-ID app slot); Android opens the review screen.
- Screenshot reading understands more apps and layouts: Amazon Pay, WhatsApp, Navi, super.money, MobiKwik, Freecharge, "Today/Yesterday" dates, "ending 1234" accounts, ₹ misread as Z, and it skips balance, cashback and fee amounts. GPay's "Completed" no longer shows a "couldn't tell" warning.

- Both phones: the **+ moved to a round button beside the tab bar**, where your thumb is, on every tab. Tap for an expense; long-press for income, transfer, your top templates and screenshots (and voice on Android). Search lives at the top of Activity (the separate Search button is gone). Tapping the current tab again goes back to its first screen (iPhone).
- iPhone: the "Add Expense" Shortcuts / Action Button action no longer fails with "URL scheme paisapulse is unsupported"; there's also "Add Income".

- New on both phones:
  - **Payee memory:** start typing a payee and pick one you've used before; its usual category and account fill in.
  - **Templates:** "Save as Template" on any transaction, then add it in one tap from Home or Quick Add (Settings › Templates to reorder or delete).
  - **Tags:** add tags like "goa trip, work" in Quick Add, search with `#goa-trip`, and see totals per tag (Settings › Tags).
  - **Receipt photos** on a transaction (kept on this phone, not in backups).
  - **Card bills:** each credit card shows last statement, what's paid, what's still to pay and the unbilled amount; Home lists bills due in the next 10 days.
  - **Month-end forecast** on Home and in Insights: today's money, coming income and bills, and your usual daily spending.
  - **Monthly recap** with a shareable picture (totals only), offered on Home in the first week of the month.
  - **Investments** account type (Groww, mutual funds): enter what it's worth now and then; net worth over time uses those values.
  - **Edit Home Screen:** reorder and hide Home's sections.
  - **Password-protected backups** (AES-256): turn it on in Backup & Restore; the same password opens the file on either phone.
- Android: a Quick Settings tile "Add Expense" (the iPhone already has the Control Center / Action Button control and Lock Screen widgets).

- Keyboards: a "hide keyboard" button floats above every keyboard on iPhone (number pads included),
  tapping outside a field puts it away, and fields have a Done key (both phones).
- Quick Add: the keypad sits on its own raised panel, the details fade into it instead of being cut
  off, and it steps aside while you type a payee.

- New on both phones: **Splits, version 2.** Pick people from your contacts (the ones you split with
  most come first), choose who paid, and split equally, by amounts or by shares, with or without you.
  Save groups (flatmates, a trip) and settle up a whole group at once. After saving, ask everyone to
  pay: a ready-made message with a link to a simple pay page (QR code + Pay button), or show a UPI
  QR code. When you owe someone, "Pay with…" opens your UPI app, and "Did it go through?" settles up.
  Add "They owe me" / "I owe them" amounts that aren't expenses.
- New on both phones: **Loans**: money you lent or borrowed, with due dates, part repayments and a
  reminder on the due date.
- New on both phones: **Clean Up Data**: automatically remove transactions older than 1, 3, 6 or 12
  months (or your own number); balances stay right and a backup is saved first. Plus Delete All Data.

- New on both phones: **Statement import**. Pick a PDF (password-protected is fine), CSV or Excel
  statement from Axis, Bank of Baroda, HDFC, ICICI, SBI or their cards. Check the columns, review
  every row (category, transfer, skip), import in one go, and undo the whole import later.
  Card bill payments, ATM withdrawals and moves between your accounts become transfers; rows you
  already added are left unticked.
- New on both phones: **Add from Screenshots**. Pick GPay, PhonePe, Paytm, CRED or bank payment
  screenshots; amount, payee, date and account are read on the phone.
- New on Android: **Say It**. Speak or type "250 lunch, 80 auto and 40 chai yesterday".
- New: **Subscriptions**: what your recurring bills cost a month and a year, and steady payments
  found in your history that you can track with one tap.
- New: **Merchant logos**: known shops show a letter in their brand colour, or their real logo when
  you turn on Settings › Merchant logos.
- New: **Saved filters** in Activity (bookmark chips), and **Select** to change the category or
  account of many transactions at once, or delete them, with one Undo.
- New: **Insights by week, month, quarter, year or your own dates**.
- New: **Reorder** accounts and categories by dragging.
- New: long-press the app icon for Add Expense, Add Income, From Screenshots (and Say It on Android).

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
