package com.paisapulse.app

import com.paisapulse.app.data.*
import com.paisapulse.app.logic.*
import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDate

class Batch4Test {
  private fun at(y: Int, m: Int, d: Int) = LocalDate.of(y, m, d).atTime(12, 0).atZone(zone).toInstant().toEpochMilli()

  @Test fun payeeMemory() {
    val txns = listOf(
      Txn(amount = 100, accountId = "a", payee = "Swiggy", categoryId = "food", occurredAt = 1),
      Txn(amount = 100, accountId = "b", payee = "Swiggy", categoryId = "food2", occurredAt = 5),
      Txn(amount = 100, accountId = "a", payee = "Swiss Beauty", occurredAt = 3),
      Txn(amount = 100, accountId = "a", payee = "Big Swim", occurredAt = 3),
    )
    val s = PayeeMemory.suggestions("swi", txns, TxnType.Expense)
    assertEquals(listOf("Swiggy", "Swiss Beauty", "Big Swim"), s.map { it.payee })
    assertEquals("food2", s[0].categoryId); assertEquals("b", s[0].accountId)
  }

  @Test fun tags() = assertEquals(listOf("goa-trip", "work"), Tags.parse("Goa Trip, #work, goa trip"))

  @Test fun valuationsAnchorInvestments() {
    val inv = Account(name = "Groww", type = "investment", color = "#000", icon = "x", openingBalance = 0)
    val txns = listOf(Txn(type = "transfer", amount = 1_000, accountId = "bank", toAccountId = inv.id, occurredAt = 10),
      Txn(type = "transfer", amount = 500, accountId = "bank", toAccountId = inv.id, occurredAt = 30))
    val b = Ledger.balances(listOf(inv), txns, listOf(Valuation(accountId = inv.id, value = 5_000, at = 20)))
    assertEquals(5_500L, b[inv.id])
    assertEquals(1_000L, Ledger.balances(listOf(inv), txns, listOf(Valuation(accountId = inv.id, value = 5_000, at = 20)), asOf = 15)[inv.id])
  }

  @Test fun cardStatement() {
    val card = Account(name = "MyZone", type = "card", color = "#000", icon = "x", statementDay = 15)
    val txns = listOf(
      Txn(amount = 3_000, accountId = card.id, occurredAt = at(2026, 10, 20)),
      Txn(amount = 2_000, accountId = card.id, occurredAt = at(2026, 11, 10)),
      Txn(amount = 9_999, accountId = card.id, occurredAt = at(2026, 11, 18)),
      Txn(type = "transfer", amount = 1_500, accountId = "bank", toAccountId = card.id, occurredAt = at(2026, 11, 19)),
    )
    val r = CardStatement.last(card, txns, at(2026, 11, 22))!!
    assertEquals(5_000L, r.billed); assertEquals(1_500L, r.paid); assertEquals(3_500L, r.due)
  }

  @Test fun recap() {
    val month = Range(at(2026, 10, 1) - 43_200_000, at(2026, 11, 1) - 43_200_000)
    val prev = Range(at(2026, 9, 1) - 43_200_000, month.start)
    val txns = listOf(Txn(amount = 1_000, accountId = "a", payee = "Zomato", occurredAt = at(2026, 10, 2)),
      Txn(amount = 4_000, accountId = "a", payee = "zomato", occurredAt = at(2026, 10, 3)),
      Txn(amount = 2_500, accountId = "a", occurredAt = at(2026, 9, 3)))
    val r = Recap.make(txns, emptyMap(), month, prev, at(2026, 11, 5))
    assertEquals(5_000L, r.spent); assertEquals(1.0, r.change); assertEquals(31, r.days); assertEquals(29, r.noSpendDays); assertEquals(28, r.longestNoSpendStreak)
    assertEquals(2, r.topPayeeCount)
  }

  @Test fun homeSections() {
    assertEquals("recent", HomeSections.order("recent,hero,bogus").first())
    assertEquals(HomeSections.all.size, HomeSections.order("recent,hero").size)
  }

  @Test fun backupCrypto() {
    val enc = BackupCrypto.encrypt("hello ₹".toByteArray(), "pw", iterations = 1_000)
    assertEquals("hello ₹", String(BackupCrypto.decrypt(enc, "pw")))
    assertEquals(true, BackupCrypto.isEncrypted(enc))
    assertEquals(true, runCatching { BackupCrypto.decrypt(enc, "nope") }.exceptionOrNull() is BackupCrypto.WrongPassword)
  }
}
