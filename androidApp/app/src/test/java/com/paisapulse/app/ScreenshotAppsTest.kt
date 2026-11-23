package com.paisapulse.app

import com.paisapulse.app.logic.*
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.TimeZone

/** More UPI apps' screenshots (same cases as iOS ScreenshotAppsTests). */
class ScreenshotAppsTest {
  @Before fun ist() { TimeZone.setDefault(TimeZone.getTimeZone("Asia/Kolkata")) }
  private fun ms(mo: Int, d: Int, h: Int, mi: Int = 0) = LocalDateTime.of(2026, mo, d, h, mi).atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
  private fun ctx() = CaptureContext(listOf(CaptureAccount("axis", "Axis Bank", "bank", "Axis Bank", "5678"), CaptureAccount("bob", "Bank of Baroda", "bank", "Bank of Baroda", "9012")),
    listOf(CaptureCategory("food", "Food & Dining", "expense", null), CaptureCategory("groceries", "Groceries", "expense", null)), emptyMap(), "axis", ms(10, 10, 18))
  private fun hm(v: Long) = Instant.ofEpochMilli(v).atZone(ZoneId.systemDefault()).let { listOf(it.monthValue, it.dayOfMonth, it.hour, it.minute) }

  @Test fun amazonPay() {
    val d = ScreenshotParser.parse(listOf("Payment successful", "₹ 199.00", "Paid to", "Airtel Prepaid", "Today, 10:15 AM", "Paid using Axis Bank ••5678", "Amazon Pay UPI"), ctx())!!
    assertEquals(19_900L, d.amount); assertEquals("axis", d.accountId); assertEquals(true, d.payee!!.startsWith("Airtel")); assertEquals(listOf(10, 10, 10, 15), hm(d.occurredAt))
    assertEquals(null, d.warning)
  }

  @Test fun whatsApp() {
    val d = ScreenshotParser.parse(listOf("Payment to Rohan Gupta", "₹250", "Completed", "9 Oct 2026, 8:30 pm", "Bank of Baroda ...9012", "UPI transaction ID: 428812345678"), ctx())!!
    assertEquals(25_000L, d.amount); assertEquals("Rohan Gupta", d.payee); assertEquals("bob", d.accountId); assertEquals(listOf(10, 9, 20, 30), hm(d.occurredAt))
  }

  @Test fun ocrRupeeAsZAndCashback() {
    val d = ScreenshotParser.parse(listOf("Cashback won ₹10", "Payment Successful", "Z349", "Paid to", "Swiggy", "Yesterday, 9:02 PM", "Axis Bank account ending 5678"), ctx())!!
    assertEquals(34_900L, d.amount); assertEquals("Swiggy", d.payee); assertEquals("food", d.categoryId); assertEquals("axis", d.accountId); assertEquals(listOf(10, 9, 21, 2), hm(d.occurredAt))
  }

  @Test fun paytmSkipsBalance() {
    val d = ScreenshotParser.parse(listOf("Paid Successfully to", "Chai Point", "Wallet Balance ₹1,250", "₹40", "10 Oct, 09:41 AM"), ctx())!!
    assertEquals(4_000L, d.amount); assertEquals("Chai Point", d.payee)
  }

  @Test fun bhimReceived() {
    val d = ScreenshotParser.parse(listOf("Money received from", "Amit Kumar", "₹1,000", "Credited to", "Axis Bank XX5678", "Yesterday 7:10 pm"), ctx())!!
    assertEquals("income", d.type); assertEquals("Amit Kumar", d.payee); assertEquals(100_000L, d.amount)
  }

  @Test fun pendingIsUnticked() {
    val d = ScreenshotParser.parse(listOf("Payment pending", "₹500", "Paid to", "Zepto"), ctx())!!
    assertEquals(false, d.include); assertEquals("Zepto", d.payee)
  }
}
