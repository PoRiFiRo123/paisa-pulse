package com.paisapulse.app

import com.paisapulse.app.data.*
import com.paisapulse.app.logic.*
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.LocalDateTime
import java.time.ZoneId

/** Payment method, currencies and trips (same cases as iOS V2Tests). */
class V2Test {
  private val ist = ZoneId.of("Asia/Kolkata")
  private fun ms(mo: Int, d: Int, h: Int = 12) = LocalDateTime.of(2026, mo, d, h, 0).atZone(ist).toInstant().toEpochMilli()
  @After fun reset() { Money.base = "INR" }

  @Test fun paymentMethodFromText() {
    assertEquals(PaymentMethod.Upi, PaymentMethod.fromText("UPI/DR/123456/SWIGGY/YESB"))
    assertEquals(PaymentMethod.Neft, PaymentMethod.fromText("NEFT-HDFC0001234-ACME PVT LTD"))
    assertEquals(PaymentMethod.Imps, PaymentMethod.fromText("MMT/IMPS/123/Rohan"))
    assertEquals(PaymentMethod.AutoDebit, PaymentMethod.fromText("NACH-DR- BAJAJ FIN"))
    assertEquals(PaymentMethod.DebitCard, PaymentMethod.fromText("POS 1234 DMART"))
    assertEquals(PaymentMethod.Rtgs, PaymentMethod.fromText("RTGS/UTIBR52026/ABC"))
    assertNull(PaymentMethod.fromText("Salary"))
    assertEquals(PaymentMethod.CreditCard, PaymentMethod.guess("bank", "credit"))
    assertEquals(PaymentMethod.Cash, PaymentMethod.guess("cash", null))
  }

  @Test fun fxAndMarkup() {
    val inrPer = mapOf("USD" to 85.0, "EUR" to 92.0)
    assertEquals(85.0, Fx.rate("USD", "INR", inrPer)!!, 1e-9)
    assertEquals(85.0 / 92.0, Fx.rate("USD", "EUR", inrPer)!!, 1e-9)
    assertEquals(1.0 / 85.0, Fx.rate("INR", "USD", inrPer)!!, 1e-9)
    assertNull(Fx.rate("XYZ", "INR", inrPer))
    assertEquals(425_000L, Fx.convert(5_000, 85.0))
    assertEquals(413, ForexMarkup.bps(3.5, withGst = true))
    assertEquals(442_553L, ForexMarkup.apply(425_000, 413))
    assertEquals(425_000L, ForexMarkup.apply(425_000, null))
  }

  @Test fun moneyInOtherCurrencies() {
    assertEquals("₹1,23,456", Money.format(12_345_600))
    Money.base = "USD"
    assertEquals("$123,456.50", Money.format(12_345_650))
    assertEquals("$1.2M", Money.compact(120_000_000))
    assertEquals("AED 1,000", Money.format(100_000, "AED"))
    assertEquals("€90", Money.format(9_000, "EUR"))
  }

  @Test fun changingMainCurrency() {
    val db = Db(
      accounts = listOf(Account(id = "a", name = "Axis", type = "bank", openingBalance = 8_500_000)),
      transactions = listOf(
        Txn(id = "t1", amount = 850_000, accountId = "a"),
        Txn(id = "t2", amount = 425_000, accountId = "a", currency = "USD", originalAmount = 5_000),
      ),
      budgets = listOf(Budget(amount = 1_700_000)),
    )
    val usd = BaseCurrency.convert(db, 1 / 85.0, "USD")
    assertEquals(100_000L, usd.accounts[0].openingBalance)
    assertEquals(10_000L, usd.transactions[0].amount)
    // Already in dollars: the exact original comes back, no rounding.
    assertEquals(5_000L, usd.transactions[1].amount); assertNull(usd.transactions[1].currency)
    assertEquals(20_000L, usd.budgets[0].amount)
  }

  @Test fun banks() {
    assertEquals("axis", Banks.match("Axis Bank")?.id)
    assertEquals("bob", Banks.match("bank of baroda")?.id)
    assertEquals("sbi", Banks.match("State Bank of India")?.id)
    assertEquals("iob", Banks.match("Indian Overseas Bank")?.id)
    assertNull(Banks.match("My Local Bank"))
    assertEquals("$", World.symbol("USD")); assertEquals("THB", World.countries.first { it.name == "Thailand" }.currency)
  }

  @Test fun tripSummary() {
    val trip = Trip(id = "goa", name = "Goa", startAt = ms(12, 20), endAt = ms(12, 24), travellers = 4)
    val items = listOf(TripItem(id = "food", tripId = "goa", label = "Food", budget = 1_000_000, sortOrder = 0),
                       TripItem(id = "stay", tripId = "goa", label = "Stay", budget = 2_000_000, sortOrder = 1))
    val wallets = listOf(TripWallet(id = "cash", tripId = "goa", label = "Cash", amount = 500_000))
    val txns = listOf(
      Txn(id = "1", amount = 400_000, accountId = "a", tripId = "goa", tripItemId = "food"),           // shared dinner, my share below
      Txn(id = "2", amount = 2_400_000, accountId = "a", tripId = "goa", tripItemId = "stay"),
      Txn(id = "3", amount = 60_000, accountId = "c", tripId = "goa", tripItemId = "food", walletId = "cash"),
      Txn(id = "4", amount = 99_900, accountId = "a", tripId = "other"),
    )
    val s = TripMath.summary(trip, items, wallets, txns, shares = mapOf("1" to 100_000), now = ms(12, 22), zone = ist)
    assertEquals(TripMath.Status.Ongoing, s.status)
    assertEquals(3, s.day); assertEquals(5, s.days)
    assertEquals(160_000L, s.items[0].spent); assertEquals(840_000L, s.items[0].remaining)
    assertEquals(2_560_000L, s.spent)
    assertEquals(2_860_000L, s.groupCost); assertEquals(715_000L, s.perPerson)
    assertEquals(3_000_000L, s.budget)
    assertEquals(440_000L, s.wallets[0].left)
    assertEquals(TripMath.Status.Upcoming, TripMath.status(trip, ms(12, 10), ist))
    assertEquals(10, TripMath.summary(trip, items, wallets, txns, now = ms(12, 10), zone = ist).daysToGo)
    assertEquals(TripMath.Status.Completed, TripMath.status(trip, ms(12, 25), ist))
    assertEquals("goa", TripMath.ongoing(listOf(trip), ms(12, 21), ist)?.id)
  }

  @Test fun foreignWalletAndBudgets() {
    val trip = Trip(id = "bkk", name = "Bangkok", international = true, startAt = ms(12, 1), endAt = ms(12, 5), countInBudgets = false)
    val w = TripWallet(id = "thb", tripId = "bkk", label = "Baht cash", currency = "THB", amount = 1_000_000, rate = 2.5)
    val txns = listOf(
      Txn(id = "1", amount = 250_000, accountId = "a", tripId = "bkk", walletId = "thb", currency = "THB", originalAmount = 100_000),
      Txn(id = "2", amount = 50_000, accountId = "a", tripId = "bkk", walletId = "thb"),   // entered in ₹: ₹500 = ฿200
      Txn(id = "3", amount = 10_000, accountId = "a"),
    )
    val s = TripMath.summary(trip, emptyList(), listOf(w), txns, now = ms(12, 3), zone = ist)
    assertEquals(880_000L, s.wallets[0].left)
    assertEquals(mapOf("THB" to 100_000L), s.byCurrency)
    assertEquals(listOf("3"), TripMath.budgetTxns(txns, listOf(trip)).map { it.id })
    assertEquals(listOf("Flights & tickets", "Stay", "Food", "Local travel", "Activities", "Shopping", "Travel insurance", "Visa & documents", "SIM & roaming", "Forex fees", "Miscellaneous"),
      TripKinds.items("trip", international = true))
  }
}
