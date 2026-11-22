package com.paisapulse.app.logic

import com.paisapulse.app.data.Account
import com.paisapulse.app.data.Budget
import com.paisapulse.app.data.Category
import com.paisapulse.app.data.RecurringRule
import com.paisapulse.app.data.SplitEntry
import com.paisapulse.app.data.Txn
import com.paisapulse.app.data.TxnType
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.temporal.TemporalAdjusters

/** Half-open [start, end) in epoch ms. */
data class Range(val start: Long, val end: Long) { operator fun contains(t: Long) = t >= start && t < end }

val zone: ZoneId get() = ZoneId.systemDefault()
fun Long.toDate(): LocalDate = Instant.ofEpochMilli(this).atZone(zone).toLocalDate()
fun LocalDate.ms(): Long = atStartOfDay(zone).toInstant().toEpochMilli()

/** Mirrors apple/Shared/Ledger.swift. */
object Ledger {
  fun balances(accounts: List<Account>, txns: List<Txn>): Map<String, Long> {
    val b = HashMap<String, Long>()
    accounts.forEach { b[it.id] = it.openingBalance }
    for (t in txns) {
      if (t.deletedAt != null) continue
      when (t.kind) {
        TxnType.Expense -> b[t.accountId] = (b[t.accountId] ?: 0) - t.amount
        TxnType.Income -> b[t.accountId] = (b[t.accountId] ?: 0) + t.amount
        TxnType.Transfer -> {
          b[t.accountId] = (b[t.accountId] ?: 0) - t.amount
          t.toAccountId?.let { b[it] = (b[it] ?: 0) + t.amount }
        }
      }
    }
    return b
  }

  fun netWorth(accounts: List<Account>, balances: Map<String, Long>) =
    accounts.filter { it.archivedAt == null && it.excludeFromTotals != true }.sumOf { balances[it.id] ?: 0 }

  data class Summary(val spent: Long = 0, val income: Long = 0) { val saved get() = income - spent }

  fun summary(txns: List<Txn>, range: Range): Summary {
    var s = 0L; var i = 0L
    for (t in txns) if (t.deletedAt == null && t.occurredAt in range) {
      if (t.kind == TxnType.Expense) s += t.effectiveAmount
      if (t.kind == TxnType.Income) i += t.amount
    }
    return Summary(s, i)
  }

  fun topLevel(id: String?, cats: Map<String, Category>): String {
    val c = id?.let { cats[it] } ?: return ""
    return c.parentId ?: c.id
  }

  fun byCategory(txns: List<Txn>, range: Range, cats: Map<String, Category>): List<Pair<String, Long>> {
    val m = HashMap<String, Long>()
    for (t in txns) if (t.deletedAt == null && t.kind == TxnType.Expense && t.occurredAt in range) {
      val k = topLevel(t.categoryId, cats); m[k] = (m[k] ?: 0) + t.effectiveAmount
    }
    return m.toList().sortedByDescending { it.second }
  }

  fun dailySpend(txns: List<Txn>, range: Range): Map<LocalDate, Long> {
    val m = HashMap<LocalDate, Long>()
    for (t in txns) if (t.deletedAt == null && t.kind == TxnType.Expense && t.occurredAt in range) {
      val d = t.occurredAt.toDate(); m[d] = (m[d] ?: 0) + t.effectiveAmount
    }
    return m
  }
}

object Periods {
  fun month(containing: LocalDate, startDay: Int): Range {
    val day = startDay.coerceIn(1, 28)
    var start = containing.withDayOfMonth(day)
    if (start.isAfter(containing)) start = start.minusMonths(1)
    return Range(start.ms(), start.plusMonths(1).ms())
  }
  fun month(offset: Int, startDay: Int, from: LocalDate = LocalDate.now()): Range {
    val base = month(from, startDay).start.toDate().plusMonths(offset.toLong())
    return month(base, startDay)
  }
  fun week(containing: LocalDate, firstWeekday: Int): Range {
    val dow = if (firstWeekday == 1) DayOfWeek.SUNDAY else DayOfWeek.MONDAY
    val start = containing.with(TemporalAdjusters.previousOrSame(dow))
    return Range(start.ms(), start.plusWeeks(1).ms())
  }
  fun label(r: Range, startDay: Int): String {
    val s = r.start.toDate()
    if (startDay == 1) return s.month.getDisplayName(java.time.format.TextStyle.FULL, java.util.Locale.ENGLISH) + " " + s.year
    val e = r.end.toDate().minusDays(1)
    val f = java.time.format.DateTimeFormatter.ofPattern("d MMM", java.util.Locale.ENGLISH)
    return "${f.format(s)} – ${f.format(e)}"
  }
}

object Budgets {
  data class Progress(val budget: Budget, val spent: Long) {
    val ratio get() = if (budget.amount > 0) spent.toDouble() / budget.amount else 0.0
    val left get() = budget.amount - spent
    val over get() = spent > budget.amount
  }
  fun progress(budgets: List<Budget>, txns: List<Txn>, cats: Map<String, Category>, month: Range, week: Range): List<Progress> =
    budgets.map { b ->
      val r = if (b.period == "weekly") week else month
      val spent = txns.filter { it.deletedAt == null && it.kind == TxnType.Expense && it.occurredAt in r &&
        (b.categoryId == null || it.categoryId == b.categoryId || Ledger.topLevel(it.categoryId, cats) == b.categoryId) }
        .sumOf { it.effectiveAmount }
      Progress(b, spent)
    }.sortedWith(compareBy({ if (it.budget.categoryId == null) 0 else 1 }, { if (it.budget.period == "weekly") 1 else 0 }))
}

object Recurrence {
  private fun step(r: RecurringRule, n: Int): Long {
    val s = Instant.ofEpochMilli(r.startAt).atZone(zone)
    val k = (r.interval * n).toLong()
    val d: ZonedDateTime = when (r.freq) {
      com.paisapulse.app.data.Frequency.Daily -> s.plusDays(k)
      com.paisapulse.app.data.Frequency.Weekly -> s.plusWeeks(k)
      com.paisapulse.app.data.Frequency.Monthly -> s.plusMonths(k)
      com.paisapulse.app.data.Frequency.Yearly -> s.plusYears(k)
    }
    return d.toInstant().toEpochMilli()
  }
  fun next(after: Long, r: RecurringRule): Long {
    var n = 1
    while (n < 100_000) { val d = step(r, n); if (d > after) return d; n++ }
    return after + 86_400_000
  }
  /** Due occurrences up to now (cap 60 per rule) and each rule's new nextAt. */
  fun due(rules: List<RecurringRule>, now: Long): Pair<List<Pair<RecurringRule, Long>>, Map<String, Long>> {
    val out = mutableListOf<Pair<RecurringRule, Long>>(); val next = HashMap<String, Long>()
    for (r in rules) {
      if (r.pausedAt != null) continue
      var at = r.nextAt; var c = 0
      while (at <= now && c < 60) {
        if (r.endAt != null && at > r.endAt) break
        out.add(r to at); at = next(at, r); c++
      }
      next[r.id] = at
    }
    return out to next
  }
}

object Splits {
  fun balances(entries: List<SplitEntry>): Map<String, Long> = entries.groupBy { it.friendId }.mapValues { (_, v) -> v.sumOf { it.amount } }
  /** Equal split among you + friends; remainder is yours. */
  fun equalShares(total: Long, friends: Int): Pair<Long, Long> {
    val each = total / (friends + 1)
    return (total - each * friends) to each
  }
}

object Cards {
  fun nextDue(dueDay: Int, from: LocalDate = LocalDate.now()): LocalDate {
    for (o in 0..1) {
      val m = from.plusMonths(o.toLong())
      val d = m.withDayOfMonth(minOf(dueDay, m.lengthOfMonth()))
      if (!d.isBefore(from)) return d
    }
    return from
  }
  fun cycle(statementDay: Int, containing: LocalDate = LocalDate.now()): Range {
    var start = containing.withDayOfMonth(minOf(statementDay, 28) + 1)
    if (start.isAfter(containing)) start = start.minusMonths(1)
    return Range(start.ms(), start.plusMonths(1).ms())
  }
}
