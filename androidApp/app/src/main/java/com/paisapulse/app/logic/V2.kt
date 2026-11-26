package com.paisapulse.app.logic

import com.paisapulse.app.data.*
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit

// Payment method, currencies (main currency, conversions, card forex markup) and trips.
// Same rules as the iPhone app (apple/Shared/V2.swift); tested in V2Test.

/** How a transaction was paid. Stored as `id` on Txn.paymentMethod. */
enum class PaymentMethod(val id: String, val label: String, val icon: String) {
  Upi("upi", "UPI", "qrcode"),
  DebitCard("debit_card", "Debit card", "creditcard"),
  CreditCard("credit_card", "Credit card", "creditcard.fill"),
  NetBanking("net_banking", "Net banking", "building.columns"),
  Neft("neft", "NEFT", "arrow.left.arrow.right"),
  Imps("imps", "IMPS", "bolt"),
  Rtgs("rtgs", "RTGS", "banknote"),
  Cash("cash", "Cash", "banknote.fill"),
  Cheque("cheque", "Cheque", "doc.text"),
  Wallet("wallet", "Wallet", "wallet.bifold.fill"),
  AutoDebit("auto_debit", "Auto-debit", "arrow.triangle.2.circlepath"),
  Other("other", "Other", "ellipsis.circle");

  companion object {
    fun of(id: String?) = entries.firstOrNull { it.id == id }

    /** From the account and card picked: cash → Cash, a credit card → Credit card, a debit card → Debit card. */
    fun guess(accountType: String?, cardKind: String?): PaymentMethod? = when {
      cardKind == "credit" -> CreditCard
      cardKind == "debit" -> DebitCard
      accountType == "cash" -> Cash
      accountType == "card" -> CreditCard
      accountType == "wallet" -> Wallet
      accountType == "bank" -> Upi
      else -> null
    }

    /** From statement narrations, screenshots and SMS: "UPI/DR/…", "NEFT-…", "POS 1234 …", "NACH". */
    fun fromText(text: String): PaymentMethod? {
      val t = text.lowercase()
      return when {
        Regex("\\b(nach|ecs|mandate|autopay|auto debit|auto-debit|standing instruction|\\bsi\\b|\\bumn\\b)").containsMatchIn(t) -> AutoDebit
        Regex("\\brtgs\\b").containsMatchIn(t) -> Rtgs
        Regex("\\bneft\\b").containsMatchIn(t) -> Neft
        Regex("\\bimps\\b").containsMatchIn(t) -> Imps
        Regex("\\bupi\\b|@[a-z]{2,}\\b|\\bvpa\\b").containsMatchIn(t) -> Upi
        Regex("\\b(chq|cheque|clg|clearing)\\b").containsMatchIn(t) -> Cheque
        Regex("\\b(net ?banking|inb|ib fund|internet banking)\\b").containsMatchIn(t) -> NetBanking
        Regex("\\b(atm|cash wdl|cash withdrawal)\\b").containsMatchIn(t) -> DebitCard
        Regex("\\b(pos|ecom|card \\d{4}|debit card)\\b").containsMatchIn(t) -> DebitCard
        else -> null
      }
    }
  }
}

/** Exchange rates are kept as rupees per unit (open.er-api.com, INR base); this converts between any two. */
object Fx {
  /** Units of `to` per 1 unit of `from`. INR is 1.0 when missing. */
  fun rate(from: String, to: String, inrPer: Map<String, Double>): Double? {
    if (from == to) return 1.0
    val f = if (from == "INR") 1.0 else inrPer[from] ?: return null
    val t = if (to == "INR") 1.0 else inrPer[to] ?: return null
    return f / t
  }

  /** Minor units (×100) of one currency → minor units of another at `rate` (to per from). */
  fun convert(minor: Long, rate: Double): Long = Math.round(minor * rate)
}

/** A card's foreign-currency markup, in basis points (413 = 4.13% = 3.5% + 18% GST on it). */
object ForexMarkup {
  const val DEFAULT_BPS = 413
  fun apply(baseMinor: Long, bps: Int?): Long = if (bps == null || bps <= 0) baseMinor else Math.round(baseMinor * (1 + bps / 10_000.0))
  fun fee(baseMinor: Long, bps: Int?): Long = apply(baseMinor, bps) - baseMinor
  /** "3.5% + GST" → 413. */
  fun bps(percent: Double, withGst: Boolean): Int = Math.round(percent * 100 * (if (withGst) 1.18 else 1.0)).toInt()
  fun label(bps: Int?): String = if (bps == null || bps <= 0) "No markup" else "%.2f%%".format(bps / 100.0)
}

/** Changing the main currency: convert every stored amount at one rate (or keep the numbers, rate = 1). */
object BaseCurrency {
  fun convert(db: Db, rate: Double, newCode: String): Db {
    fun c(v: Long) = Math.round(v * rate)
    fun co(v: Long?) = v?.let { c(it) }
    return db.copy(
      accounts = db.accounts.map { it.copy(openingBalance = c(it.openingBalance), creditLimit = co(it.creditLimit)) },
      transactions = db.transactions.map { t ->
        // A transaction already in the new currency gets its exact original back.
        if (t.currency == newCode && t.originalAmount != null) t.copy(amount = t.originalAmount, currency = null, originalAmount = null)
        else t.copy(amount = maxOf(1, c(t.amount)))
      },
      txnSplitShares = db.txnSplitShares.map { it.copy(share = c(it.share)) },
      recurringRules = db.recurringRules.map { it.copy(amount = maxOf(1, c(it.amount))) },
      budgets = db.budgets.map { it.copy(amount = c(it.amount)) },
      splitEntries = db.splitEntries.map { it.copy(amount = c(it.amount)) },
      loans = db.loans.map { it.copy(amount = c(it.amount)) },
      loanPayments = db.loanPayments.map { it.copy(amount = c(it.amount)) },
      goals = db.goals.map { it.copy(target = c(it.target), saved = c(it.saved)) },
      templates = db.templates.map { it.copy(amount = maxOf(1, c(it.amount))) },
      valuations = db.valuations.map { it.copy(value = c(it.value)) },
      tripItems = db.tripItems.map { it.copy(budget = co(it.budget)) },
      tripWallets = db.tripWallets.map { w -> if (w.currency == null) w.copy(amount = c(w.amount)) else w.copy(rate = w.rate * rate) },
    )
  }
}

// ---------------------------------------------------------------- Trips

/** Event types with their ready-made budget items (international trips add the extras). */
object TripKinds {
  data class Kind(val id: String, val label: String, val icon: String, val color: String, val dated: Boolean, val places: Boolean,
                  val items: List<String>, val intlItems: List<String> = emptyList())
  val all = listOf(
    Kind("trip", "Trip", "airplane", "#2563EB", true, true,
      listOf("Flights & tickets", "Stay", "Food", "Local travel", "Activities", "Shopping", "Miscellaneous"),
      listOf("Travel insurance", "Visa & documents", "SIM & roaming", "Forex fees")),
    Kind("vacation", "Vacation", "beach.umbrella.fill", "#0891B2", true, true,
      listOf("Travel", "Stay", "Food", "Activities", "Shopping", "Local travel", "Miscellaneous"), listOf("Travel insurance", "Visa & documents")),
    Kind("weekend", "Weekend getaway", "tent.fill", "#16A34A", true, true, listOf("Travel", "Stay", "Food", "Activities", "Miscellaneous")),
    Kind("business", "Business trip", "briefcase.fill", "#334155", true, true,
      listOf("Flights", "Stay", "Food", "Local travel", "Meetings", "Client entertainment", "Miscellaneous"), listOf("Visa", "Insurance")),
    Kind("event", "Event", "party.popper.fill", "#DB2777", true, false,
      listOf("Venue", "Food", "Decorations", "Entertainment", "Gifts", "Travel", "Miscellaneous")),
    Kind("outing", "Outing", "fork.knife", "#EA580C", false, false, listOf("Food", "Drinks", "Travel", "Tips", "Miscellaneous")),
    Kind("ride", "Ride", "car.fill", "#7C3AED", false, false, listOf("Fuel", "Toll", "Parking", "Food", "Miscellaneous")),
    Kind("custom", "Custom", "star.fill", "#6B7280", true, false, emptyList()),
  )
  fun of(id: String?) = all.firstOrNull { it.id == id } ?: all.last()
  fun items(kind: String, international: Boolean): List<String> = of(kind).let { k -> if (international) k.items.dropLast(1) + k.intlItems + k.items.takeLast(1) else k.items }
}

object TripMath {
  enum class Status { Upcoming, Ongoing, Completed }

  data class ItemSpend(val item: TripItem, val spent: Long) { val remaining get() = (item.budget ?: 0) - spent }
  data class WalletLeft(val wallet: TripWallet, val spent: Long) { val left get() = wallet.amount - spent }
  data class Summary(
    val trip: Trip, val status: Status, val items: List<ItemSpend>, val unassigned: Long,
    /** Your share of the trip (what it cost you). */ val spent: Long,
    /** Everything paid for the trip, whoever's share (split bills count in full). */ val groupCost: Long,
    val budget: Long, val wallets: List<WalletLeft>,
    /** Totals of foreign spending by currency (original amounts). */ val byCurrency: Map<String, Long>,
    val count: Int, val day: Int?, val days: Int?, val daysToGo: Int?,
  ) {
    val remaining get() = budget - spent
    val overBudget get() = budget > 0 && spent > budget
    val perPerson get() = if (trip.travellers > 1) groupCost / trip.travellers else groupCost
    val progress get() = if (budget > 0) spent.toDouble() / budget else 0.0
  }

  private fun day(ms: Long, zone: ZoneId) = Instant.ofEpochMilli(ms).atZone(zone).toLocalDate()

  fun status(trip: Trip, now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()): Status {
    val start = trip.startAt ?: return Status.Completed
    val today = day(now, zone)
    val end = day(trip.endAt ?: start, zone)
    return when { today < day(start, zone) -> Status.Upcoming; today > end -> Status.Completed; else -> Status.Ongoing }
  }

  /** The trip happening now (the most recently started one), for Quick Add's automatic link. */
  fun ongoing(trips: List<Trip>, now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()): Trip? =
    trips.filter { it.archivedAt == null && it.startAt != null && status(it, now, zone) == Status.Ongoing }.maxByOrNull { it.startAt!! }

  fun summary(trip: Trip, items: List<TripItem>, wallets: List<TripWallet>, txns: List<Txn>, shares: Map<String, Long> = emptyMap(),
              now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()): Summary {
    val mine = txns.filter { it.deletedAt == null && it.tripId == trip.id }
    val expenses = mine.filter { it.type == "expense" }
    fun share(t: Txn) = shares[t.id] ?: t.splitShare ?: t.amount
    val its = items.filter { it.tripId == trip.id }.sortedBy { it.sortOrder }
      .map { i -> ItemSpend(i, expenses.filter { it.tripItemId == i.id }.sumOf { share(it) }) }
    val known = its.map { it.item.id }.toSet()
    // A wallet in the main currency (currency null) counts the main amount; a foreign one counts the
    // original amount when the spend was in its currency, else the main amount at the wallet's rate.
    val ws = wallets.filter { it.tripId == trip.id }.map { w ->
      WalletLeft(w, expenses.filter { it.walletId == w.id }.sumOf { t ->
        when {
          w.currency == null -> t.amount
          t.currency == w.currency && t.originalAmount != null -> t.originalAmount
          else -> Math.round(t.amount / w.rate)
        }
      })
    }
    val byCurrency = expenses.filter { it.currency != null && it.originalAmount != null }.groupBy { it.currency!! }.mapValues { (_, v) -> v.sumOf { it.originalAmount!! } }
    val st = status(trip, now, zone)
    val start = trip.startAt?.let { day(it, zone) }
    val end = (trip.endAt ?: trip.startAt)?.let { day(it, zone) }
    val today = day(now, zone)
    val days = if (start != null && end != null) (ChronoUnit.DAYS.between(start, end) + 1).toInt() else null
    return Summary(
      trip = trip, status = st, items = its,
      unassigned = expenses.filter { it.tripItemId == null || it.tripItemId !in known }.sumOf { share(it) },
      spent = expenses.sumOf { share(it) }, groupCost = expenses.sumOf { it.amount },
      budget = if (trip.budgetEnabled != false) its.sumOf { it.item.budget ?: 0 } else 0,
      wallets = ws, byCurrency = byCurrency, count = mine.size,
      day = if (st == Status.Ongoing && start != null) (ChronoUnit.DAYS.between(start, today) + 1).toInt() else null,
      days = days,
      daysToGo = if (st == Status.Upcoming && start != null) ChronoUnit.DAYS.between(today, start).toInt() else null,
    )
  }

  /** Transactions that budgets should count: trips switched to "Don't count in budgets" are left out. */
  fun budgetTxns(txns: List<Txn>, trips: List<Trip>): List<Txn> {
    val excluded = trips.filter { it.countInBudgets == false }.map { it.id }.toSet()
    return if (excluded.isEmpty()) txns else txns.filter { it.tripId == null || it.tripId !in excluded }
  }

  data class Overview(val upcoming: Int, val ongoing: Int, val completed: Int, val planned: Long, val spent: Long, val overBudget: Int)
  fun overview(summaries: List<Summary>) = Overview(
    summaries.count { it.status == Status.Upcoming }, summaries.count { it.status == Status.Ongoing }, summaries.count { it.status == Status.Completed },
    summaries.sumOf { it.budget }, summaries.sumOf { it.spent }, summaries.count { it.overBudget },
  )
}
