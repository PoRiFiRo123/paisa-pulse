package com.paisapulse.app

import com.paisapulse.app.data.Account
import com.paisapulse.app.data.Db
import com.paisapulse.app.data.RecurringRule
import com.paisapulse.app.data.Store
import com.paisapulse.app.data.Txn
import com.paisapulse.app.logic.Cards
import com.paisapulse.app.logic.KeypadMath
import com.paisapulse.app.logic.Ledger
import com.paisapulse.app.logic.Money
import com.paisapulse.app.logic.Periods
import com.paisapulse.app.logic.Range
import com.paisapulse.app.logic.Recurrence
import com.paisapulse.app.logic.Splits
import com.paisapulse.app.logic.ms
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.math.BigDecimal
import java.time.LocalDate

class LogicTest {
  @Test fun formatHasNoMinusAndLakhGrouping() {
    assertEquals("₹1,23,456", Money.format(12_345_600))
    assertEquals("₹1,23,456.50", Money.format(-12_345_650))
    assertEquals("₹0", Money.format(0))
    assertEquals("₹1,00,00,000", Money.format(1_000_000_000))
  }
  @Test fun compact() {
    assertEquals("₹950", Money.compact(95_000)); assertEquals("₹38K", Money.compact(3_845_000))
    assertEquals("₹1.2L", Money.compact(12_000_000)); assertEquals("₹2.3Cr", Money.compact(2_300_000_000))
  }
  @Test fun parse() {
    assertEquals(125_050L, Money.parse("1,250.5")); assertNull(Money.parse("0")); assertNull(Money.parse("x"))
  }
  @Test fun keypad() {
    assertEquals(0, BigDecimal(410).compareTo(KeypadMath.evaluate("250+80×2")))
    assertEquals(333L, Money.paise(KeypadMath.evaluate("10÷3")!!))
    assertNull(KeypadMath.evaluate("5÷0"))
  }
  @Test fun balances() {
    val accts = listOf(Account(id = "b", name = "B", openingBalance = 100_000), Account(id = "c", name = "C", type = "card"))
    val t = listOf(Txn(amount = 30_000, accountId = "c"), Txn(type = "transfer", amount = 20_000, accountId = "b", toAccountId = "c"),
      Txn(type = "income", amount = 5_000, accountId = "b"), Txn(amount = 99_999, accountId = "b", deletedAt = 1))
    val b = Ledger.balances(accts, t)
    assertEquals(85_000L, b["b"]); assertEquals(-10_000L, b["c"]); assertEquals(75_000L, Ledger.netWorth(accts, b))
  }
  @Test fun splitShareCounts() {
    val now = System.currentTimeMillis()
    val s = Ledger.summary(listOf(Txn(amount = 90_000, accountId = "a", splitShare = 30_000)), Range(now - 3_600_000, now + 3_600_000))
    assertEquals(30_000L, s.spent)
    assertEquals(33_334L to 33_333L, Splits.equalShares(100_000, 2))
  }
  @Test fun salaryMonthAndCards() {
    val m = Periods.month(LocalDate.of(2026, 11, 3), 25)
    assertEquals(LocalDate.of(2026, 10, 25).ms(), m.start)
    assertEquals(LocalDate.of(2026, 2, 28), Cards.nextDue(31, LocalDate.of(2026, 2, 20)))
  }
  @Test fun recurrenceAnchors() {
    val r = RecurringRule(amount = 100, accountId = "a", startAt = LocalDate.of(2026, 1, 31).ms(), nextAt = LocalDate.of(2026, 1, 31).ms())
    val (due, _) = Recurrence.due(listOf(r), LocalDate.of(2026, 4, 1).ms())
    assertEquals(3, due.size)
  }
  @Test fun storeRoundTripKeepsSplitShares() {
    val db = Db(accounts = listOf(Account(id = "a", name = "Axis")), transactions = listOf(Txn(id = "t", amount = 42_800, accountId = "a", splitShare = 21_400)))
    val back = Store.decode(Store.encode(db))
    assertEquals(21_400L, back.transactions[0].splitShare)
    assertEquals(4, back.version)
  }
}
