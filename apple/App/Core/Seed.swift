import SwiftData
import SwiftUI

/// Starter categories for India (same pack as the Android app, src/db/seed.ts).
enum Seed {
  struct Starter { let name: String; let icon: String; let color: String; var children: [(String, String)] = [] }

  static let expense: [Starter] = [
    .init(name: "Food & Dining", icon: "fork.knife", color: "#FF9500"),
    .init(name: "Groceries", icon: "cart.fill", color: "#34C759"),
    .init(name: "Transport", icon: "car.fill", color: "#007AFF", children: [("Fuel", "fuelpump.fill"), ("Metro/Auto/Cab", "tram.fill")]),
    .init(name: "Shopping", icon: "bag.fill", color: "#FF2D55"),
    .init(name: "Bills & Utilities", icon: "doc.text.fill", color: "#FFB800", children: [("Electricity", "bolt.fill"), ("Mobile/Internet", "wifi"), ("DTH", "tv.fill")]),
    .init(name: "Rent", icon: "house.fill", color: "#AF52DE"),
    .init(name: "EMI/Loans", icon: "building.columns.fill", color: "#8E8E93"),
    .init(name: "Health", icon: "cross.case.fill", color: "#FF3B30"),
    .init(name: "Entertainment", icon: "popcorn.fill", color: "#5856D6"),
    .init(name: "Subscriptions", icon: "repeat.circle.fill", color: "#32ADE6"),
    .init(name: "Travel", icon: "airplane", color: "#00C7BE"),
    .init(name: "Education", icon: "graduationcap.fill", color: "#A2845E"),
    .init(name: "Gifts & Donations", icon: "gift.fill", color: "#E0457B"),
    .init(name: "Investments", icon: "chart.line.uptrend.xyaxis", color: "#1E9E5A"),
    .init(name: "Personal Care", icon: "sparkles", color: "#C969E0"),
    .init(name: "Family", icon: "figure.2.and.child.holdinghands", color: "#FF8C69"),
  ]
  static let income: [Starter] = [
    .init(name: "Salary", icon: "banknote.fill", color: "#30B0C7"),
    .init(name: "Freelance", icon: "laptopcomputer", color: "#5E5CE6"),
    .init(name: "Interest", icon: "percent", color: "#34C759"),
    .init(name: "Refund", icon: "arrow.uturn.backward.circle.fill", color: "#007AFF"),
    .init(name: "Cashback", icon: "indianrupeesign.circle.fill", color: "#FF9500"),
    .init(name: "Other", icon: "ellipsis.circle.fill", color: "#8E8E93"),
  ]

  /// Once per install; safe on every launch.
  static func ensureCategories(_ context: ModelContext) {
    let count = (try? context.fetchCount(FetchDescriptor<Category>())) ?? 0
    guard count == 0 else { return }
    for (kind, list) in [(CategoryKind.expense, expense), (.income, income)] {
      for (i, s) in list.enumerated() {
        let parent = Category(kind: kind, name: s.name, icon: s.icon, color: s.color, sortOrder: i)
        context.insert(parent)
        for (j, child) in s.children.enumerated() {
          context.insert(Category(parentId: parent.id, kind: kind, name: child.0, icon: child.1, color: s.color, sortOrder: j))
        }
      }
    }
    try? context.save()
  }
}

/// Launch/foreground chores: due recurring transactions, purge old soft deletes, notifications, backups.
enum Maintenance {
  @MainActor static func run(_ context: ModelContext) {
    let rules = (try? context.fetch(FetchDescriptor<RecurringRule>())) ?? []
    for (rule, at) in Recurrence.due(rules) {
      context.insert(Txn(type: rule.type, amount: rule.amount, accountId: rule.accountId, toAccountId: rule.toAccountId,
                         categoryId: rule.categoryId, payee: rule.payee, note: rule.note, occurredAt: at,
                         source: "recurring", recurringId: rule.id))
    }
    let cutoff = Date.now.addingTimeInterval(-30 * 86_400)
    let old = (try? context.fetch(FetchDescriptor<Txn>(predicate: #Predicate { $0.deletedAt != nil }))) ?? []
    for t in old where (t.deletedAt ?? .now) < cutoff { context.delete(t) }
    try? context.save()
    Notifier.refresh(context)
    AutoBackup.runIfDue(context)
    DataCleanup.runIfDue(context)
    WidgetRefresh.now()
  }
}
