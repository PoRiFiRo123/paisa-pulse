package com.paisapulse.app.logic

import com.paisapulse.app.data.*

// Card dues and recurring bills on one timeline (Bills screen, Home, reminders). Same rules as iOS Bills.swift.

data class Bill(
  val id: String, val title: String, val icon: String, val color: String, val amount: Long, val due: Long,
  val accountId: String, val ruleId: String? = null, val isCard: Boolean = false,
)

object Bills {
  const val DAY = 86_400_000L

  /**
   * Bills due in the next [days] days: each credit card with a due day and something to pay (the last statement's unpaid
   * amount when it has a statement day, else what's owed), and each active recurring expense.
   */
  fun upcoming(accounts: List<Account>, txns: List<Txn>, rules: List<RecurringRule>, balances: Map<String, Long>,
               now: Long = System.currentTimeMillis(), days: Int = 31): List<Bill> {
    val until = now + days * DAY
    val cards = accounts.filter { it.kind == AccountType.Card && it.archivedAt == null && it.dueDay != null }.mapNotNull { a ->
      val owed = CardStatement.last(a, txns, now)?.due ?: maxOf(0L, -(balances[a.id] ?: 0))
      if (owed <= 0) return@mapNotNull null
      val due = Cards.nextDue(a.dueDay!!, now.toDate()).ms()
      Bill("card-${a.id}", "${a.name} bill", a.icon, a.color, owed, due, a.id, isCard = true)
    }
    val recurring = rules.filter { it.type == "expense" && it.pausedAt == null && it.nextAt <= until && (it.endAt == null || it.nextAt <= it.endAt) }
      .map { r -> Bill("rule-${r.id}", r.payee ?: r.note ?: "Recurring bill", "repeat", "#30B0C7", r.amount, r.nextAt, r.accountId, ruleId = r.id) }
    return (cards + recurring).filter { it.due <= until }.sortedBy { it.due }
  }

  /** Whole days from today to the due date (0 = today, negative = overdue). */
  fun daysLeft(bill: Bill, now: Long = System.currentTimeMillis()): Long =
    java.time.temporal.ChronoUnit.DAYS.between(now.toDate(), bill.due.toDate())

  fun dueText(bill: Bill, now: Long = System.currentTimeMillis()): String = when (val d = daysLeft(bill, now)) {
    in Long.MIN_VALUE..-1 -> "Overdue"
    0L -> "Due today"
    1L -> "Due tomorrow"
    else -> "Due in $d days"
  }
}
