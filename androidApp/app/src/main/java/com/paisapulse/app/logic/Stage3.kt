package com.paisapulse.app.logic

import com.paisapulse.app.data.Loan
import com.paisapulse.app.data.LoanPayment
import com.paisapulse.app.data.Txn
import com.paisapulse.app.data.TxnType
import java.net.URLEncoder
import java.time.Instant

/** Split v2 maths, same as iOS SplitMath (Stage3.swift). */
enum class SplitMode(val key: String, val label: String) { Equal("equal", "Equally"), Amount("amount", "Amounts"), Shares("shares", "Shares") }

data class SplitSetup(
  /** Friend ids; you are "me". */
  val people: List<String> = emptyList(),
  val includeMe: Boolean = true,
  /** null = you paid. */
  val payer: String? = null,
  val mode: SplitMode = SplitMode.Equal,
  /** Paise (amounts) or weights (shares) keyed by "me" or a friend id. */
  val values: Map<String, Long> = emptyMap(),
  val groupId: String? = null,
) { val isEmpty get() = people.isEmpty() }

data class SplitResult(val myShare: Long, val shares: Map<String, Long>, val entries: Map<String, Long>, val unassigned: Long) {
  val valid get() = unassigned == 0L
}

object SplitMath {
  fun compute(total: Long, s: SplitSetup): SplitResult {
    val keys = (if (s.includeMe) listOf("me") else emptyList()) + s.people
    if (keys.isEmpty() || total <= 0) return SplitResult(total, emptyMap(), emptyMap(), 0)
    val shares = LinkedHashMap<String, Long>()
    var unassigned = 0L
    when (s.mode) {
      SplitMode.Equal -> {
        val each = total / keys.size
        keys.forEach { shares[it] = each }
        shares[keys[0]] = shares[keys[0]]!! + total - each * keys.size
      }
      SplitMode.Amount -> {
        keys.forEach { shares[it] = maxOf(0L, s.values[it] ?: 0L) }
        unassigned = total - shares.values.sum()
      }
      SplitMode.Shares -> {
        val weights = keys.map { maxOf(0L, s.values[it] ?: 1L) }
        val sum = maxOf(1L, weights.sum())
        keys.zip(weights).forEach { (k, w) -> shares[k] = total * w / sum }
        shares[keys[0]] = shares[keys[0]]!! + total - shares.values.sum()
      }
    }
    val mine = if (s.includeMe) shares["me"] ?: 0L else 0L
    val entries = LinkedHashMap<String, Long>()
    if (s.payer != null) { if (mine > 0) entries[s.payer] = -mine }
    else s.people.forEach { f -> val v = shares[f] ?: 0L; if (v > 0) entries[f] = v }
    return SplitResult(mine, shares, entries, unassigned)
  }

  private fun enc(s: String) = URLEncoder.encode(s, "UTF-8").replace("+", "%20")
  private fun rupees(p: Long) = "%d.%02d".format(p / 100, p % 100)

  fun upiUri(upiId: String, name: String, amount: Long, note: String?): String =
    "upi://pay?pa=${enc(upiId)}&pn=${enc(name)}&am=${rupees(amount)}&cu=INR" + (note?.let { "&tn=${enc(it.take(50))}" } ?: "")

  /** Static pay page on GitHub Pages; the details are only in the #fragment. */
  fun payPageUrl(upiId: String, name: String, amount: Long, note: String?): String =
    "https://porifiro123.github.io/paisa-pulse/pay/#pa=${enc(upiId)}&pn=${enc(name)}&am=${rupees(amount)}" + (note?.let { "&tn=${enc(it.take(50))}" } ?: "")

  fun requestMessage(friend: String, amount: Long, note: String?, upiId: String, myName: String): String =
    "Hi $friend, your share${note?.let { " for $it" } ?: ""} is ${Money.format(amount)}. Pay me on UPI: ${payPageUrl(upiId, myName, amount, note)}"
}

/** Data clean-up, same as iOS Cleanup. */
object Cleanup {
  val options = listOf(Triple("off", "Off", 0), Triple("monthly", "Keep 1 month", 1), Triple("quarterly", "Keep 3 months", 3),
    Triple("halfyearly", "Keep 6 months", 6), Triple("yearly", "Keep 1 year", 12), Triple("custom", "Custom", 0))

  fun months(key: String, custom: Int): Int? =
    if (key == "custom") custom.takeIf { it > 0 } else options.firstOrNull { it.first == key }?.third?.takeIf { it > 0 }

  fun cutoff(months: Int, now: Long = System.currentTimeMillis()): Long =
    Instant.ofEpochMilli(now).atZone(zone).toLocalDate().minusMonths(months.toLong()).atStartOfDay(zone).toInstant().toEpochMilli()

  /** Opening-balance changes per account and the ids to remove (live and deleted) before `cutoff`. */
  fun plan(txns: List<Txn>, cutoff: Long): Pair<Map<String, Long>, Set<String>> {
    val delta = HashMap<String, Long>(); val remove = HashSet<String>()
    for (t in txns) {
      if (t.occurredAt >= cutoff) continue
      remove.add(t.id)
      if (t.deletedAt != null) continue
      when (t.kind) {
        TxnType.Expense -> delta[t.accountId] = (delta[t.accountId] ?: 0) - t.amount
        TxnType.Income -> delta[t.accountId] = (delta[t.accountId] ?: 0) + t.amount
        TxnType.Transfer -> {
          delta[t.accountId] = (delta[t.accountId] ?: 0) - t.amount
          t.toAccountId?.let { delta[it] = (delta[it] ?: 0) + t.amount }
        }
      }
    }
    return delta to remove
  }
}

object LoanMath {
  fun repaid(l: Loan, payments: List<LoanPayment>) = payments.filter { it.loanId == l.id }.sumOf { it.amount }
  fun outstanding(l: Loan, payments: List<LoanPayment>) = maxOf(0L, l.amount - repaid(l, payments))
}
