package com.paisapulse.app.work

import com.paisapulse.app.data.*

/** Starter categories for India: the same pack as the iPhone app (apple/App/Core/Seed.swift). */
object Seed {
  private data class S(val name: String, val icon: String, val color: String, val children: List<Pair<String, String>> = emptyList())
  private val expense = listOf(
    S("Food & Dining", "fork.knife", "#FF9500"), S("Groceries", "cart.fill", "#34C759"),
    S("Transport", "car.fill", "#007AFF", listOf("Fuel" to "fuelpump.fill", "Metro/Auto/Cab" to "tram.fill")),
    S("Shopping", "bag.fill", "#FF2D55"),
    S("Bills & Utilities", "doc.text.fill", "#FFB800", listOf("Electricity" to "bolt.fill", "Mobile/Internet" to "wifi", "DTH" to "tv.fill")),
    S("Rent", "house.fill", "#AF52DE"), S("EMI/Loans", "building.columns.fill", "#8E8E93"), S("Health", "cross.case.fill", "#FF3B30"),
    S("Entertainment", "popcorn.fill", "#5856D6"), S("Subscriptions", "repeat.circle.fill", "#32ADE6"), S("Travel", "airplane", "#00C7BE"),
    S("Education", "graduationcap.fill", "#A2845E"), S("Gifts & Donations", "gift.fill", "#E0457B"),
    S("Investments", "chart.line.uptrend.xyaxis", "#1E9E5A"), S("Personal Care", "sparkles", "#C969E0"),
    S("Family", "figure.2.and.child.holdinghands", "#FF8C69"),
  )
  private val income = listOf(
    S("Salary", "banknote.fill", "#30B0C7"), S("Freelance", "laptopcomputer", "#5E5CE6"), S("Interest", "percent", "#34C759"),
    S("Refund", "arrow.uturn.backward.circle.fill", "#007AFF"), S("Cashback", "indianrupeesign.circle.fill", "#FF9500"),
    S("Other", "ellipsis.circle.fill", "#8E8E93"),
  )
  fun categories(): List<Category> = buildList {
    for ((kind, list) in listOf("expense" to expense, "income" to income)) list.forEachIndexed { i, s ->
      val p = Category(kind = kind, name = s.name, icon = s.icon, color = s.color, sortOrder = i); add(p)
      s.children.forEachIndexed { j, (n, ic) -> add(Category(parentId = p.id, kind = kind, name = n, icon = ic, color = s.color, sortOrder = j)) }
    }
  }
  fun ensureCategories() { if (Store.value.categories.isEmpty()) Store.update { it.copy(categories = categories()) } }
}

/** Sample data for emulator screenshots (launch extra PaisaDemo=true). Same data as the iPhone DemoData. */
object Demo {
  fun seed() {
    val cats = Seed.categories(); fun cat(n: String) = cats.firstOrNull { it.name == n }?.id
    val axis = Account(name = "Axis Salary", institution = "Axis Bank", last4 = "4417", openingBalance = 18_450_000, color = "#97144D")
    val bob = Account(name = "BoB Savings", institution = "Bank of Baroda", openingBalance = 6_200_000, color = "#F26522", sortOrder = 1)
    val card = Account(name = "MyZone", type = "card", institution = "Axis Bank", last4 = "9021", creditLimit = 15_000_000, statementDay = 12, dueDay = 2,
      color = "#2C2C2E", icon = "creditcard.fill", sortOrder = 2)
    val cash = Account(name = "Cash", type = "cash", openingBalance = 320_000, color = "#34C759", icon = "banknote.fill", sortOrder = 3)
    val n = now(); val day = 86_400_000L
    val items = listOf(Triple(0, "Swiggy", "Food & Dining") to (42_800L to card), Triple(0, "Namma Metro", "Metro/Auto/Cab") to (4_500L to axis),
      Triple(1, "BigBasket", "Groceries") to (186_400L to axis), Triple(1, "Starbucks", "Food & Dining") to (38_000L to card),
      Triple(2, "Netflix", "Subscriptions") to (64_900L to card), Triple(2, "Uber", "Metro/Auto/Cab") to (21_800L to axis),
      Triple(3, "Zepto", "Groceries") to (54_300L to axis), Triple(4, "Amazon", "Shopping") to (249_900L to card),
      Triple(5, "BESCOM", "Electricity") to (142_000L to axis), Triple(6, "PVR INOX", "Entertainment") to (78_000L to card),
      Triple(7, "Shell", "Fuel") to (150_000L to card), Triple(8, "Zomato", "Food & Dining") to (31_200L to card),
      Triple(9, "Apollo Pharmacy", "Health") to (46_500L to axis), Triple(10, "Airtel", "Mobile/Internet") to (59_900L to axis),
      Triple(12, "Rent", "Rent") to (2_200_000L to axis), Triple(14, "Blinkit", "Groceries") to (38_900L to axis),
      Triple(17, "Spotify", "Subscriptions") to (11_900L to card), Triple(20, "IndiGo", "Travel") to (684_000L to card),
      Triple(35, "Rent", "Rent") to (2_200_000L to axis), Triple(38, "Amazon", "Shopping") to (412_000L to card),
      Triple(45, "Swiggy", "Food & Dining") to (95_000L to card), Triple(66, "Rent", "Rent") to (2_200_000L to axis), Triple(70, "Croma", "Shopping") to (899_000L to card))
    val txns = items.map { (t, v) -> Txn(amount = v.first, accountId = v.second.id, categoryId = cat(t.third), payee = t.second, occurredAt = n - t.first * day - (t.first % 5 + 1) * 3_600_000L) }.toMutableList()
    val ritwik = Friend(name = "Ritwik", upiId = "ritwik@okaxis")
    val dinner = Txn(amount = 240_000, accountId = card.id, categoryId = cat("Food & Dining"), payee = "Toit", occurredAt = n - 2 * day - 7_200_000, splitShare = 120_000)
    txns += dinner
    (0..2).forEach { m -> txns += Txn(type = "income", amount = 9_000_000, accountId = axis.id, categoryId = cat("Salary"), payee = "Boomi", occurredAt = n - (21 + 30 * m) * day) }
    txns += Txn(type = "transfer", amount = 1_200_000, accountId = axis.id, toAccountId = card.id, payee = "Card bill", occurredAt = n - 11 * day)
    Store.replace(Db(accounts = listOf(axis, bob, card, cash), categories = cats, transactions = txns, friends = listOf(ritwik),
      splitEntries = listOf(SplitEntry(friendId = ritwik.id, txnId = dinner.id, amount = 120_000, note = "Toit", occurredAt = dinner.occurredAt)),
      budgets = listOf(Budget(amount = 5_000_000), Budget(categoryId = cat("Food & Dining"), amount = 800_000)),
      cards = listOf(
        PaymentCard(accountId = axis.id, kind = "debit", network = "visa", last4 = "4417", expiryMonth = 8, expiryYear = 2029, nameOnCard = "NISHIT KIRANI", label = "Axis Debit"),
        PaymentCard(accountId = axis.id, kind = "debit", network = "rupay", last4 = "7302", expiryMonth = 3, expiryYear = 2028, nameOnCard = "NISHIT KIRANI", color = "#1E9E5A"),
        PaymentCard(accountId = card.id, kind = "credit", network = "mastercard", last4 = "9021", expiryMonth = 9, expiryYear = 2031, nameOnCard = "NISHIT KIRANI")),
      goals = listOf(Goal(name = "Germany fund", icon = "airplane", color = "#007AFF", target = 50_000_000, saved = 12_500_000, deadline = n + 240 * day))))
    Prefs.set("onboarded", true)
  }
}
