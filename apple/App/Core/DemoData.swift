import SwiftData
import SwiftUI

/// Sample data for simulator screenshots: launch with `-PaisaDemo YES`. Never runs otherwise.
enum DemoData {
  @MainActor static func seedIfRequested(_ context: ModelContext) {
    guard UserDefaults.standard.bool(forKey: "PaisaDemo") else { return }
    try? context.delete(model: Txn.self); try? context.delete(model: Account.self); try? context.delete(model: Budget.self)
    try? context.delete(model: Goal.self); try? context.delete(model: Friend.self); try? context.delete(model: SplitEntry.self)
    try? context.delete(model: PaymentCard.self)
    try? context.save()
    Seed.ensureCategories(context)
    let cats = (try? context.fetch(FetchDescriptor<Category>())) ?? []
    func cat(_ n: String) -> String? { cats.first { $0.name == n }?.id }
    let axis = Account(name: "Axis Salary", type: .bank, institution: "Axis Bank", last4: "4417", openingBalance: 18_450_000, color: "#97144D", icon: "building.columns.fill")
    let bob = Account(name: "BoB Savings", type: .bank, institution: "Bank of Baroda", openingBalance: 6_200_000, color: "#F26522", icon: "building.columns.fill", sortOrder: 1)
    let card = Account(name: "MyZone", type: .card, institution: "Axis Bank", last4: "9021", openingBalance: 0, creditLimit: 15_000_000, statementDay: 12, dueDay: 2, color: "#2C2C2E", icon: "creditcard.fill", sortOrder: 2)
    let cash = Account(name: "Cash", type: .cash, openingBalance: 320_000, color: "#34C759", icon: "banknote.fill", sortOrder: 3)
    [axis, bob, card, cash].forEach { context.insert($0) }
    context.insert(PaymentCard(accountId: axis.id, kind: "debit", network: "visa", last4: "4417", expiryMonth: 8, expiryYear: 2029, nameOnCard: "NISHIT KIRANI", label: "Axis Debit"))
    context.insert(PaymentCard(accountId: axis.id, kind: "debit", network: "rupay", last4: "7302", expiryMonth: 3, expiryYear: 2028, nameOnCard: "NISHIT KIRANI", color: "#1E9E5A"))
    context.insert(PaymentCard(accountId: card.id, kind: "credit", network: "mastercard", last4: "9021", expiryMonth: 9, expiryYear: 2031, nameOnCard: "NISHIT KIRANI"))
    let now = Date.now
    let items: [(Int, String, String, Int, Account)] = [
      (0, "Swiggy", "Food & Dining", 42_800, card), (0, "Namma Metro", "Metro/Auto/Cab", 4_500, axis),
      (1, "BigBasket", "Groceries", 186_400, axis), (1, "Starbucks", "Food & Dining", 38_000, card),
      (2, "Netflix", "Subscriptions", 64_900, card), (2, "Uber", "Metro/Auto/Cab", 21_800, axis),
      (3, "Zepto", "Groceries", 54_300, axis), (4, "Amazon", "Shopping", 249_900, card),
      (5, "BESCOM", "Electricity", 142_000, axis), (6, "PVR INOX", "Entertainment", 78_000, card),
      (7, "Shell", "Fuel", 150_000, card), (8, "Zomato", "Food & Dining", 31_200, card),
      (9, "Apollo Pharmacy", "Health", 46_500, axis), (10, "Airtel", "Mobile/Internet", 59_900, axis),
      (12, "Rent", "Rent", 2_200_000, axis), (14, "Blinkit", "Groceries", 38_900, axis),
      (17, "Spotify", "Subscriptions", 11_900, card), (20, "IndiGo", "Travel", 684_000, card),
      (35, "Rent", "Rent", 2_200_000, axis), (38, "Amazon", "Shopping", 412_000, card), (45, "Swiggy", "Food & Dining", 95_000, card),
      (66, "Rent", "Rent", 2_200_000, axis), (70, "Croma", "Shopping", 899_000, card),
    ]
    for (d, payee, c, amt, a) in items {
      context.insert(Txn(type: .expense, amount: amt, accountId: a.id, categoryId: cat(c), payee: payee,
                         occurredAt: now.addingTimeInterval(-Double(d) * 86_400 - Double(d % 5 + 1) * 3600)))
    }
    let ritwik = Friend(name: "Ritwik", upiId: "ritwik@okaxis")
    context.insert(ritwik)
    let dinner = Txn(type: .expense, amount: 240_000, accountId: card.id, categoryId: cat("Food & Dining"), payee: "Toit", occurredAt: now.addingTimeInterval(-2 * 86_400 - 7200), splitShare: 120_000)
    context.insert(dinner)
    context.insert(SplitEntry(friendId: ritwik.id, txnId: dinner.id, amount: 120_000, note: "Toit", occurredAt: dinner.occurredAt))
    for m in 0..<3 {
      context.insert(Txn(type: .income, amount: 9_000_000, accountId: axis.id, categoryId: cat("Salary"), payee: "Boomi", occurredAt: now.addingTimeInterval(-Double(21 + 30 * m) * 86_400)))
    }
    context.insert(Txn(type: .transfer, amount: 1_200_000, accountId: axis.id, toAccountId: card.id, payee: "Card bill", occurredAt: now.addingTimeInterval(-11 * 86_400)))
    context.insert(Budget(amount: 5_000_000))
    context.insert(Budget(categoryId: cat("Food & Dining"), amount: 800_000))
    context.insert(Goal(name: "Germany fund", icon: "airplane", color: "#007AFF", target: 50_000_000, saved: 12_500_000, deadline: now.addingTimeInterval(240 * 86_400)))
    try? context.save()
    AppGroup.defaults.set(true, forKey: PrefKey.onboarded)
  }
}
