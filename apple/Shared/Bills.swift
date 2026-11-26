import Foundation

// Card dues and recurring bills on one timeline (Bills screen, Home, reminders). Same rules as Android Bills.kt.

struct Bill: Identifiable, Equatable {
  let id: String
  let title: String
  let icon: String
  let color: String
  let amount: Int
  let due: Date
  let accountId: String
  var ruleId: String? = nil
  var isCard = false
}

enum Bills {
  /// Bills due in the next `days` days: each credit card with a due day and something to pay (the last statement's unpaid
  /// amount when it has a statement day, else what's owed), and each active recurring expense.
  static func upcoming(accounts: [Account], txns: [Txn], rules: [RecurringRule], balances: [String: Int],
                       now: Date = .now, days: Int = 31, calendar: Calendar = .current) -> [Bill] {
    let until = now.addingTimeInterval(Double(days) * 86_400)
    let cards: [Bill] = accounts.filter { $0.type == .card && $0.archivedAt == nil && $0.dueDay != nil }.compactMap { a in
      let owed = CardStatement.last(account: a, txns: txns, now: now, calendar: calendar)?.due ?? max(0, -(balances[a.id] ?? 0))
      guard owed > 0 else { return nil }
      return Bill(id: "card-\(a.id)", title: "\(a.name) bill", icon: a.icon, color: a.color, amount: owed,
                  due: Cards.nextDue(dueDay: a.dueDay!, from: now, calendar: calendar), accountId: a.id, isCard: true)
    }
    let recurring: [Bill] = rules.filter { r in r.type == .expense && r.pausedAt == nil && r.nextAt <= until && (r.endAt.map { e in r.nextAt <= e } ?? true) }
      .map { r in Bill(id: "rule-\(r.id)", title: r.payee ?? r.note ?? "Recurring bill", icon: "repeat", color: "#30B0C7",
                       amount: r.amount, due: r.nextAt, accountId: r.accountId, ruleId: r.id) }
    return (cards + recurring).filter { $0.due <= until }.sorted { $0.due < $1.due }
  }

  /// Whole days from today to the due date (0 = today, negative = overdue).
  static func daysLeft(_ b: Bill, now: Date = .now, calendar: Calendar = .current) -> Int {
    calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: b.due)).day ?? 0
  }

  static func dueText(_ b: Bill, now: Date = .now, calendar: Calendar = .current) -> String {
    switch daysLeft(b, now: now, calendar: calendar) {
    case ..<0: "Overdue"
    case 0: "Due today"
    case 1: "Due tomorrow"
    case let d: "Due in \(d) days"
    }
  }
}
