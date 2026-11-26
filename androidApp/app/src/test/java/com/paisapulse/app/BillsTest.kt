package com.paisapulse.app

import com.paisapulse.app.data.*
import com.paisapulse.app.logic.*
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import java.time.LocalDate
import java.util.TimeZone

/** Bills timeline (same cases as iOS BillsTests). */
class BillsTest {
  @Before fun ist() { TimeZone.setDefault(TimeZone.getTimeZone("Asia/Kolkata")) }
  private fun day(m: Int, d: Int) = LocalDate.of(2026, m, d).ms()
  private val now get() = day(11, 26) + 10 * 3_600_000L

  @Test fun cardDueAndRecurringSorted() {
    val card = Account(id = "c", name = "MyZone", type = "card", dueDay = 5)
    val bank = Account(id = "b", name = "Axis", type = "bank")
    val rent = RecurringRule(id = "r", amount = 2_000_000, accountId = "b", payee = "Rent", startAt = day(11, 1), nextAt = day(12, 1))
    val gym = RecurringRule(id = "g", amount = 150_000, accountId = "b", payee = "Gym", startAt = day(11, 1), nextAt = day(11, 28))
    val paused = gym.copy(id = "p", pausedAt = day(11, 2))
    val bills = Bills.upcoming(listOf(card, bank), emptyList(), listOf(rent, gym, paused), mapOf("c" to -640_000L, "b" to 100L), now)
    assertEquals(listOf("rule-g", "rule-r", "card-c"), bills.map { it.id })
    assertEquals(640_000L, bills.last().amount); assertEquals(day(12, 5), bills.last().due)
    assertEquals("Due in 2 days", Bills.dueText(bills.first(), now))
  }

  @Test fun nothingOwedNoCardBill() {
    val card = Account(id = "c", name = "MyZone", type = "card", dueDay = 5)
    assertEquals(0, Bills.upcoming(listOf(card), emptyList(), emptyList(), mapOf("c" to 0L), now).size)
  }

  @Test fun outsideWindowSkipped() {
    val rule = RecurringRule(id = "y", amount = 99_900, accountId = "b", payee = "Domain", frequency = "yearly", startAt = day(3, 1), nextAt = day(3, 1) + 365L * Bills.DAY)
    assertEquals(0, Bills.upcoming(emptyList(), emptyList(), listOf(rule), emptyMap(), now).size)
  }
}
