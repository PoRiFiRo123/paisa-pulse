package com.paisapulse.app

import com.paisapulse.app.data.*
import com.paisapulse.app.logic.*
import org.junit.Assert.assertEquals
import org.junit.Test

/** Same case as iOS ReportTests. */
class ReportTest {
  private val month = Range(1_000, 2_000)
  private val prev = Range(0, 1_000)
  private fun e(cat: String, amt: Long, at: Long) = Txn(type = "expense", amount = amt, accountId = "a", categoryId = cat, occurredAt = at)

  @Test fun rowsAndMovers() {
    val cats = listOf(Category(id = "food", name = "Food"), Category(id = "fun", name = "Fun"), Category(id = "rent", name = "Rent")).associateBy { it.id }
    val txns = listOf(e("food", 500, 1_100), e("food", 300, 100), e("fun", 100, 1_200), e("fun", 400, 200), e("rent", 2_000, 1_300), e("rent", 2_000, 300))
    val rows = Report.rows(txns, cats, month, prev)
    assertEquals(listOf("rent", "food", "fun"), rows.map { it.categoryId })
    val (up, down) = Report.movers(rows)
    assertEquals(listOf("food"), up.map { it.categoryId }); assertEquals(200L, up[0].diff)
    assertEquals(listOf("fun"), down.map { it.categoryId }); assertEquals(-300L, down[0].diff)
    assertEquals(listOf(2_000L, 500L, 100L), Report.biggest(txns, month).map { it.amount })
  }
}
