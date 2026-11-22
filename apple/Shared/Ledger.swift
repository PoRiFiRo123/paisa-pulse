import Foundation

/// Pure money maths over plain arrays, shared by screens and the widget. No SwiftData queries here,
/// so it's easy to test.
enum Ledger {
  /// Current balance per account id (signed: cards you owe on are negative).
  /// Balances from opening balances and transactions. An account with valuations (investments) starts from
  /// its latest value on or before `asOf`; only transactions after that value count.
  static func balances(accounts: [Account], txns: [Txn], valuations: [Valuation] = [], asOf: Date? = nil) -> [String: Int] {
    var b: [String: Int] = [:]
    var anchor: [String: Date] = [:]
    for a in accounts { b[a.id] = a.openingBalance }
    for v in valuations where asOf.map({ v.at <= $0 }) ?? true {
      if anchor[v.accountId].map({ v.at > $0 }) ?? true { anchor[v.accountId] = v.at; b[v.accountId] = v.value }
    }
    func counts(_ id: String, _ t: Txn) -> Bool { anchor[id].map { t.occurredAt > $0 } ?? true }
    for t in txns where t.deletedAt == nil && (asOf.map { t.occurredAt <= $0 } ?? true) {
      switch t.type {
      case .expense: if counts(t.accountId, t) { b[t.accountId, default: 0] -= t.amount }
      case .income: if counts(t.accountId, t) { b[t.accountId, default: 0] += t.amount }
      case .transfer:
        if counts(t.accountId, t) { b[t.accountId, default: 0] -= t.amount }
        if let to = t.toAccountId, counts(to, t) { b[to, default: 0] += t.amount }
      }
    }
    return b
  }

  static func netWorth(accounts: [Account], balances: [String: Int]) -> Int {
    accounts.filter { $0.archivedAt == nil && !$0.excludeFromTotals }.reduce(0) { $0 + (balances[$1.id] ?? 0) }
  }

  struct Summary: Equatable { var spent = 0; var income = 0; var saved: Int { income - spent } }

  /// Spending counts your share of split expenses. Transfers (incl. card bills) are not spending.
  static func summary(_ txns: [Txn], in range: DateInterval) -> Summary {
    var s = Summary()
    for t in txns where t.deletedAt == nil && range.contains(t.occurredAt) {
      if t.type == .expense { s.spent += t.effectiveAmount }
      if t.type == .income { s.income += t.amount }
    }
    return s
  }

  /// Spending per top-level category id ("" = uncategorised), largest first.
  static func byCategory(_ txns: [Txn], in range: DateInterval, categories: [String: Category]) -> [(id: String, amount: Int)] {
    var totals: [String: Int] = [:]
    for t in txns where t.deletedAt == nil && t.type == .expense && range.contains(t.occurredAt) {
      totals[topLevel(t.categoryId, categories), default: 0] += t.effectiveAmount
    }
    return totals.map { ($0.key, $0.value) }.sorted { $0.amount > $1.amount }
  }

  static func topLevel(_ id: String?, _ categories: [String: Category]) -> String {
    guard let id, let c = categories[id] else { return "" }
    return c.parentId ?? c.id
  }

  /// Daily spending (expense minus nothing) keyed by start of day.
  static func dailySpend(_ txns: [Txn], in range: DateInterval, calendar: Calendar = .current) -> [Date: Int] {
    var d: [Date: Int] = [:]
    for t in txns where t.deletedAt == nil && t.type == .expense && range.contains(t.occurredAt) {
      d[calendar.startOfDay(for: t.occurredAt), default: 0] += t.effectiveAmount
    }
    return d
  }
}

/// Months that start on your salary day (Settings › Month starts on).
enum Periods {
  static func month(containing date: Date, startDay: Int, calendar: Calendar = .current) -> DateInterval {
    let day = min(max(startDay, 1), 28)
    var comps = calendar.dateComponents([.year, .month], from: date)
    comps.day = day
    var start = calendar.date(from: comps)!
    if start > date { start = calendar.date(byAdding: .month, value: -1, to: start)! }
    let end = calendar.date(byAdding: .month, value: 1, to: start)!
    return DateInterval(start: start, end: end)
  }

  static func month(offset: Int, from date: Date = .now, startDay: Int, calendar: Calendar = .current) -> DateInterval {
    let shifted = calendar.date(byAdding: .month, value: offset, to: month(containing: date, startDay: startDay, calendar: calendar).start)!
    return month(containing: shifted, startDay: startDay, calendar: calendar)
  }

  static func week(containing date: Date, firstWeekday: Int = 2, calendar: Calendar = .current) -> DateInterval {
    var cal = calendar
    cal.firstWeekday = firstWeekday
    return cal.dateInterval(of: .weekOfYear, for: date)!
  }

  static func label(_ range: DateInterval, startDay: Int) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_IN")
    if startDay == 1 { f.dateFormat = "MMMM yyyy"; return f.string(from: range.start) }
    f.dateFormat = "d MMM"
    let end = Calendar.current.date(byAdding: .day, value: -1, to: range.end)!
    return "\(f.string(from: range.start)) – \(f.string(from: end))"
  }
}

enum Budgets {
  struct Progress: Identifiable {
    var id: String { budget.id }
    let budget: Budget
    let spent: Int
    var ratio: Double { budget.amount > 0 ? Double(spent) / Double(budget.amount) : 0 }
    var left: Int { budget.amount - spent }
    var over: Bool { spent > budget.amount }
  }

  /// A category budget includes its subcategories.
  static func progress(_ budgets: [Budget], txns: [Txn], categories: [String: Category], month: DateInterval, week: DateInterval) -> [Progress] {
    budgets.map { b in
      let range = b.period == "weekly" ? week : month
      let spent = txns.reduce(0) { sum, t in
        guard t.deletedAt == nil, t.type == .expense, range.contains(t.occurredAt) else { return sum }
        if let cid = b.categoryId {
          return t.categoryId == cid || Ledger.topLevel(t.categoryId, categories) == cid ? sum + t.effectiveAmount : sum
        }
        return sum + t.effectiveAmount
      }
      return Progress(budget: b, spent: spent)
    }
    .sorted { ($0.budget.categoryId == nil ? 0 : 1, $0.budget.period == "weekly" ? 1 : 0) < ($1.budget.categoryId == nil ? 0 : 1, $1.budget.period == "weekly" ? 1 : 0) }
  }
}

enum Recurrence {
  /// The date after `date` for a rule, anchored to its start day (31st → 30th/28th in short months).
  static func next(after date: Date, rule: RecurringRule, calendar: Calendar = .current) -> Date {
    var n = 1
    while true {
      let d = calendar.date(byAdding: rule.frequency.unit, value: rule.interval * n, to: rule.startAt)!
      if d > date { return d }
      n += 1
      if n > 100_000 { return date.addingTimeInterval(86_400) }
    }
  }

  /// Transactions due up to `now` for active rules; advances each rule's nextAt. Caps catch-up at 60.
  static func due(_ rules: [RecurringRule], now: Date = .now) -> [(RecurringRule, Date)] {
    var out: [(RecurringRule, Date)] = []
    for r in rules where r.pausedAt == nil {
      var at = r.nextAt
      var count = 0
      while at <= now, count < 60 {
        if let end = r.endAt, at > end { break }
        out.append((r, at))
        at = next(after: at, rule: r)
        count += 1
      }
      r.nextAt = at
    }
    return out
  }
}

enum Splits {
  /// Balance per friend id: > 0 they owe you, < 0 you owe them.
  static func balances(_ entries: [SplitEntry]) -> [String: Int] {
    entries.reduce(into: [:]) { $0[$1.friendId, default: 0] += $1.amount }
  }

  /// Equal split of `total` paise among you + friends; the remainder goes to you.
  static func equalShares(total: Int, friends: Int) -> (yours: Int, each: Int) {
    let people = friends + 1
    let each = total / people
    return (total - each * friends, each)
  }
}

enum Cards {
  /// The next due date for a card with a due day (1–31), today included.
  static func nextDue(dueDay: Int, from date: Date = .now, calendar: Calendar = .current) -> Date {
    let today = calendar.startOfDay(for: date)
    for offset in 0...1 {
      let month = calendar.date(byAdding: .month, value: offset, to: today)!
      var comps = calendar.dateComponents([.year, .month], from: month)
      let days = calendar.range(of: .day, in: .month, for: month)!.count
      comps.day = min(dueDay, days)
      let d = calendar.date(from: comps)!
      if d >= today { return d }
    }
    return today
  }

  /// Statement cycle containing `date` for a statement day.
  static func cycle(statementDay: Int, containing date: Date = .now, calendar: Calendar = .current) -> DateInterval {
    var comps = calendar.dateComponents([.year, .month], from: date)
    comps.day = min(statementDay, 28) + 1
    var start = calendar.date(from: comps)!
    if start > date { start = calendar.date(byAdding: .month, value: -1, to: start)! }
    return DateInterval(start: start, end: calendar.date(byAdding: .month, value: 1, to: start)!)
  }
}
