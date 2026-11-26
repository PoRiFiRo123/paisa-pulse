package com.paisapulse.app.logic

import com.paisapulse.app.data.*

/** The monthly report: every category this month vs last, and the biggest movers. Same rules as iOS Report.swift. */
object Report {
  data class Row(val categoryId: String, val amount: Long, val before: Long) { val diff get() = amount - before }

  fun rows(txns: List<Txn>, cats: Map<String, Category>, month: Range, previous: Range): List<Row> {
    val now = Ledger.byCategory(txns, month, cats).toMap()
    val before = Ledger.byCategory(txns, previous, cats).toMap()
    return (now.keys + before.keys).distinct().map { Row(it, now[it] ?: 0, before[it] ?: 0) }
      .sortedWith(compareByDescending<Row> { it.amount }.thenByDescending { it.before })
  }

  /** Categories that went up the most and down the most (by amount), up to [limit] each. */
  fun movers(rows: List<Row>, limit: Int = 3): Pair<List<Row>, List<Row>> =
    rows.filter { it.diff > 0 }.sortedByDescending { it.diff }.take(limit) to rows.filter { it.diff < 0 }.sortedBy { it.diff }.take(limit)

  /** The biggest expenses of the month, largest first. */
  fun biggest(txns: List<Txn>, month: Range, limit: Int = 5): List<Txn> =
    txns.filter { it.deletedAt == null && it.kind == TxnType.Expense && it.occurredAt in month }.sortedByDescending { it.effectiveAmount }.take(limit)
}
