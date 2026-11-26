package com.paisapulse.app

import com.paisapulse.app.data.Account
import com.paisapulse.app.logic.NetWorth
import org.junit.Assert.assertEquals
import org.junit.Test

/** Same case as iOS NetWorthTests. */
class NetWorthTest {
  @Test fun assetsOwedAndGroups() {
    val accs = listOf(Account(id = "a", name = "Axis", type = "bank"), Account(id = "b", name = "BoB", type = "bank"),
      Account(id = "c", name = "MyZone", type = "card"), Account(id = "x", name = "Old", type = "bank", archivedAt = 1L))
    val b = NetWorth.breakdown(accs, mapOf("a" to 100_000L, "b" to 50_000L, "c" to -30_000L, "x" to 999L))
    assertEquals(150_000L, b.assets); assertEquals(30_000L, b.owed); assertEquals(120_000L, b.total)
    assertEquals(listOf("Bank accounts", "Credit cards (owed)"), b.byType.map { it.label })
  }
}
