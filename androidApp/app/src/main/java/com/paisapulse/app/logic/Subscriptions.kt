package com.paisapulse.app.logic

import com.paisapulse.app.data.Frequency
import com.paisapulse.app.data.RecurringRule
import com.paisapulse.app.data.Txn
import java.time.Instant

/** Same rules as the iPhone app's Subscriptions.swift. */
object Subscriptions {
  data class Detected(
    val payee: String, val amount: Long, val frequency: Frequency, val accountId: String, val categoryId: String?,
    val lastAt: Long, val nextAt: Long, val txnIds: List<String>,
  ) { val id get() = payee.lowercase() }

  fun monthly(amount: Long, frequency: Frequency, interval: Int = 1): Long {
    val perYear = when (frequency) { Frequency.Daily -> 365.0; Frequency.Weekly -> 52.0; Frequency.Monthly -> 12.0; Frequency.Yearly -> 1.0 }
    return Math.round(amount * perYear / maxOf(1, interval) / 12)
  }
  fun monthly(r: RecurringRule) = monthly(r.amount, r.freq, r.interval)

  fun isActive(r: RecurringRule, now: Long = System.currentTimeMillis()): Boolean {
    if (r.pausedAt != null) return false
    if (r.endAt != null && (r.nextAt > r.endAt || r.endAt < now)) return false
    return true
  }

  private data class Cadence(val f: Frequency, val days: Double, val min: Double, val max: Double)
  private val cadences = listOf(Cadence(Frequency.Weekly, 7.0, 6.0, 8.0), Cadence(Frequency.Monthly, 30.4, 26.0, 35.0), Cadence(Frequency.Yearly, 365.0, 350.0, 380.0))
  private fun median(xs: List<Double>): Double { val s = xs.sorted(); val m = s.size / 2; return if (s.size % 2 == 1) s[m] else (s[m - 1] + s[m]) / 2 }

  fun detect(txns: List<Txn>, rules: List<RecurringRule>, now: Long = System.currentTimeMillis()): List<Detected> {
    val day = 86_400_000.0
    val since = now - (800 * day).toLong()
    val tracked = rules.mapNotNull { it.payee?.lowercase() }.toSet()
    val groups = txns.filter { it.deletedAt == null && it.type == "expense" && it.recurringId == null && it.occurredAt >= since }
      .mapNotNull { t -> t.payee?.trim()?.lowercase()?.takeIf { it.isNotEmpty() && it !in tracked }?.let { it to t } }
      .groupBy({ it.first }, { it.second })
    val found = mutableListOf<Detected>()
    for (raw in groups.values) {
      val list = raw.sortedBy { it.occurredAt }
      if (list.size < 2) continue
      val last = list.last()
      val run = mutableListOf<Txn>()
      for (t in list.asReversed()) { if (Math.abs(t.amount - last.amount) > last.amount * 0.1) break; run.add(0, t) }
      if (run.size < 2) continue
      val gaps = run.zipWithNext { a, b -> (b.occurredAt - a.occurredAt) / day }
      val gap = median(gaps)
      val c = cadences.firstOrNull { gap >= it.min && gap <= it.max } ?: continue
      if (run.size < if (c.f == Frequency.Yearly) 2 else 3) continue
      if (gaps.any { it < c.min * 0.7 || it > c.max * 2.1 }) continue
      if (now - last.occurredAt > c.days * 1.6 * day) continue
      val z = Instant.ofEpochMilli(last.occurredAt).atZone(zone)
      val next = when (c.f) { Frequency.Weekly -> z.plusWeeks(1); Frequency.Yearly -> z.plusYears(1); else -> z.plusMonths(1) }.toInstant().toEpochMilli()
      found += Detected(last.payee!!.trim(), last.amount, c.f, last.accountId, last.categoryId, last.occurredAt, next, run.map { it.id })
    }
    return found.sortedByDescending { monthly(it.amount, it.frequency) }
  }

  /** A rule anchored on the latest payment; an overdue payment is never invented. */
  fun rule(d: Detected, now: Long = System.currentTimeMillis()): RecurringRule {
    val r = RecurringRule(type = "expense", amount = d.amount, accountId = d.accountId, categoryId = d.categoryId, payee = d.payee,
      frequency = d.frequency.key, startAt = d.lastAt, nextAt = d.lastAt)
    return r.copy(nextAt = Recurrence.next(maxOf(d.lastAt, now), r))
  }
}
