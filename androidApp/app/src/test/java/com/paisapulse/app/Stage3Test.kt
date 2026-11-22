package com.paisapulse.app

import com.paisapulse.app.data.Loan
import com.paisapulse.app.data.LoanPayment
import com.paisapulse.app.data.Txn
import com.paisapulse.app.logic.*
import org.junit.Assert.assertEquals
import org.junit.Test

class Stage3Test {
  @Test fun equalSplitYouPaid() {
    val r = SplitMath.compute(100_000, SplitSetup(listOf("a", "b")))
    assertEquals(33_334L, r.myShare)
    assertEquals(mapOf("a" to 33_333L, "b" to 33_333L), r.entries)
  }

  @Test fun friendPaidSoYouOweYourShare() {
    val r = SplitMath.compute(90_000, SplitSetup(listOf("a", "b"), payer = "a"))
    assertEquals(mapOf("a" to -30_000L), r.entries)
  }

  @Test fun sharesAndAmounts() {
    val s = SplitMath.compute(90_000, SplitSetup(listOf("a"), mode = SplitMode.Shares, values = mapOf("me" to 2L, "a" to 1L)))
    assertEquals(60_000L, s.myShare); assertEquals(mapOf("a" to 30_000L), s.entries)
    val a = SplitMath.compute(90_000, SplitSetup(listOf("a"), mode = SplitMode.Amount, values = mapOf("me" to 50_000L, "a" to 30_000L)))
    assertEquals(10_000L, a.unassigned)
    val notMe = SplitMath.compute(90_000, SplitSetup(listOf("a", "b"), includeMe = false))
    assertEquals(0L, notMe.myShare); assertEquals(mapOf("a" to 45_000L, "b" to 45_000L), notMe.entries)
  }

  @Test fun upiLinks() {
    assertEquals("upi://pay?pa=me%40okaxis&pn=Nishit%20K&am=500.00&cu=INR&tn=Dinner", SplitMath.upiUri("me@okaxis", "Nishit K", 50_000, "Dinner"))
    assertEquals("https://porifiro123.github.io/paisa-pulse/pay/#pa=me%40okaxis&pn=Nishit&am=12.50", SplitMath.payPageUrl("me@okaxis", "Nishit", 1_250, null))
  }

  @Test fun cleanupFoldsIntoOpeningBalances() {
    val txns = listOf(
      Txn(type = "expense", amount = 1_000, accountId = "a", occurredAt = 1_000),
      Txn(type = "income", amount = 5_000, accountId = "a", occurredAt = 2_000),
      Txn(type = "transfer", amount = 2_000, accountId = "a", toAccountId = "c", occurredAt = 3_000),
      Txn(type = "expense", amount = 700, accountId = "a", occurredAt = 3_500, deletedAt = 4_000),
      Txn(type = "expense", amount = 9_999, accountId = "a", occurredAt = 10_000),
    )
    val (delta, remove) = Cleanup.plan(txns, 5_000)
    assertEquals(mapOf("a" to 2_000L, "c" to 2_000L), delta)
    assertEquals(4, remove.size)
    assertEquals(3, Cleanup.months("quarterly", 0)); assertEquals(18, Cleanup.months("custom", 18)); assertEquals(null, Cleanup.months("off", 5))
  }

  @Test fun loans() {
    val l = Loan(person = "Ashwin", amount = 10_000)
    val p = listOf(LoanPayment(loanId = l.id, amount = 4_000), LoanPayment(loanId = "other", amount = 1))
    assertEquals(6_000L, LoanMath.outstanding(l, p))
  }
}
