package com.paisapulse.app

import com.paisapulse.app.logic.*
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Bank SMS / notification alerts (same cases as iOS BankAlertsTests). */
class BankAlertsTest {
  private val t0 = 1_795_600_000_000L
  private fun ctx() = CaptureContext(
    listOf(
      CaptureAccount("axis", "Axis Bank", "bank", "Axis Bank", "4321"),
      CaptureAccount("bob", "Bank of Baroda", "bank", "Bank of Baroda", "7556"),
      CaptureAccount("myzone", "Axis MyZone", "card", "Axis Bank", "1234"),
    ),
    listOf(CaptureCategory("food", "Food & Dining", "expense", null), CaptureCategory("salary", "Salary", "income", null)),
    emptyMap(), "axis", t0,
  )
  private fun p(text: String, sender: String? = null) = BankAlerts.parse(PendingAlert(text, sender, t0), ctx())

  @Test fun axisUpiDebit() {
    val d = p("INR 450.00 debited from A/c no. XX4321 on 25-11-26 at 10:15:30 IST. Info- UPI/P2M/533012345678/SWIGGY. Not you? SMS BLOCK 4321 to 919951860002 - Axis Bank")!!
    assertEquals(45_000L, d.amount); assertEquals("expense", d.type); assertEquals("axis", d.accountId); assertEquals("Swiggy", d.payee)
    assertEquals("alert:533012345678", d.key); assertEquals(t0, d.occurredAt)
  }

  @Test fun bobTransfer() {
    val d = p("Rs.199.00 transferred from A/c ...7556 to:UPI/533098765432. Total Bal:Rs.12,345.67CR. Avlbl Amt:Rs.12,345.67(25-11-2026 07:43:21) - Bank of Baroda")!!
    assertEquals(19_900L, d.amount); assertEquals("expense", d.type); assertEquals("bob", d.accountId); assertEquals("alert:533098765432", d.key)
  }

  @Test fun hdfcSent() {
    val d = p("Sent Rs.250.00 From HDFC Bank A/C *9999 To Rahul Sharma On 25/11/26 Ref 533011112222 Not You? Call 18002586161")!!
    assertEquals(25_000L, d.amount); assertEquals("Rahul Sharma", d.payee); assertEquals("expense", d.type)
  }

  @Test fun sbiUpi() {
    val d = p("Dear UPI user A/C X7556 debited by 80.0 on date 25Nov26 trf to CHAI POINT Refno 533055556666. If not u? call 1800111109. -SBI")!!
    assertEquals(8_000L, d.amount); assertEquals("bob", d.accountId); assertEquals("Chai Point", d.payee)
  }

  @Test fun iciciDebit() {
    val d = p("ICICI Bank Acct XX321 debited for Rs 1,299.00 on 25-Nov-26; AMAZON PAY credited. UPI:533077778888. Call 18002662 for dispute.")!!
    assertEquals(129_900L, d.amount); assertEquals("expense", d.type)
  }

  @Test fun cardSpend() {
    val d = p("Spent INR 2,499.00 Axis Bank Card no. XX1234 25-11-26 13:45:12 IST at MYNTRA DESIGNS. Avl Lmt INR 97,501.00. Not you? SMS BLOCK 1234")!!
    assertEquals(249_900L, d.amount); assertEquals("myzone", d.accountId); assertEquals("expense", d.type)
  }

  @Test fun salaryCredit() {
    val d = p("INR 90,000.00 credited to A/c no. XX4321 on 01-11-26 by NEFT from BOOMI SOFTWARE PVT LTD. Avl Bal INR 1,02,345.00 - Axis Bank")!!
    assertEquals(9_000_000L, d.amount); assertEquals("income", d.type); assertEquals("axis", d.accountId)
  }

  @Test fun balanceIsNotTheAmount() {
    val d = p("Avl Bal: Rs 5,000.00. Rs 120.00 debited from A/c XX4321 towards UPI/533000001111/ZEPTO")!!
    assertEquals(12_000L, d.amount)
  }

  @Test fun cardBillPayment() {
    val d = p("Payment of INR 6,400.00 has been received towards your Axis Bank Credit Card XX1234. Thank you.")!!
    assertEquals("transfer", d.type); assertEquals("myzone", d.toAccountId); assertEquals("axis", d.accountId)
  }

  @Test fun ignoresOtpsDuesAndRequests() {
    assertNull(p("123456 is your OTP for a transaction of INR 450.00 at SWIGGY. Do not share it."))
    assertNull(p("Your Axis Bank Credit Card XX1234 statement: Total due INR 6,400.00, minimum amount due INR 320. Due date 05-12-26."))
    assertNull(p("Rahul has requested money of Rs 200.00 on Google Pay. Pay or decline."))
    assertNull(p("Rs 499.00 will be debited from your A/c XX4321 on 28-11-26 for Netflix e-mandate."))
    assertNull(p("Transaction of Rs 450.00 failed. Amount will be refunded."))
  }

  @Test fun bobMandateDebit() {
    val d = p("Your A/c XX7556 is debited towards Mahanadi Coalfields for Rs. 14960.00 on 2026-11-26 06:13:43 AM UMN 01a2079d9c0470e2abf86e265b4a551c@yesg - Bank Of Baroda")!!
    assertEquals(1_496_000L, d.amount); assertEquals("expense", d.type); assertEquals("bob", d.accountId); assertEquals("Mahanadi Coalfields", d.payee)
    assertEquals(PaymentMethod.AutoDebit, PaymentMethod.fromText(d.source))
  }

  @Test fun idIsNotAPayee() {
    assertNull(BankAlerts.payee("Rs 50.00 debited from A/c XX4321 UMN 01a2079d9c0470e2abf86e265b4a551c@yesg"))
  }

  @Test fun sameAlertSameKey() {
    val a = "Rs 99.00 debited from A/c XX4321. Info: SPOTIFY"
    assertEquals(BankAlerts.key(a, 9_900), BankAlerts.key(a, 9_900))
  }
}
