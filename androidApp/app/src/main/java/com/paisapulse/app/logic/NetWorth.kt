package com.paisapulse.app.logic

import com.paisapulse.app.data.Account

/** What you own vs what you owe, by account type. Same rules as iOS NetWorth.swift. */
object NetWorth {
  data class Group(val label: String, val amount: Long, val owed: Boolean)
  data class Breakdown(val assets: Long, val owed: Long, val byType: List<Group>) { val total get() = assets - owed }

  fun breakdown(accounts: List<Account>, balances: Map<String, Long>): Breakdown {
    var assets = 0L; var owed = 0L
    val groups = LinkedHashMap<String, Group>()
    accounts.filter { it.archivedAt == null && it.excludeFromTotals != true }.forEach { a ->
      val v = balances[a.id] ?: 0
      if (v >= 0) assets += v else owed += -v
      val key = if (v < 0) "${a.kind.plural} (owed)" else a.kind.plural
      groups[key] = Group(key, (groups[key]?.amount ?: 0) + kotlin.math.abs(v), v < 0)
    }
    return Breakdown(assets, owed, groups.values.filter { it.amount > 0 }.sortedByDescending { it.amount })
  }
}
