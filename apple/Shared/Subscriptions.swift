import Foundation

/// Subscriptions = recurring expenses, plus payees you pay on a steady cadence that aren't tracked yet.
/// Same rules as the Android app (logic/Subscriptions.kt) and the RN app's subscriptions.ts.
enum Subscriptions {
  struct Detected: Identifiable, Hashable {
    var id: String { payee.lowercased() }
    let payee: String
    let amount: Int
    let frequency: Frequency
    let accountId: String
    let categoryId: String?
    let lastAt: Date
    let nextAt: Date
    let txnIds: [String]
  }

  /// Average cost per month in paise (a yearly ₹1,499 plan is ₹125/month).
  static func monthly(amount: Int, frequency: Frequency, interval: Int = 1) -> Int {
    let perYear: Double = switch frequency { case .daily: 365; case .weekly: 52; case .monthly: 12; case .yearly: 1 }
    return Int((Double(amount) * perYear / Double(max(1, interval)) / 12).rounded())
  }

  static func monthly(_ r: RecurringRule) -> Int { monthly(amount: r.amount, frequency: r.frequency, interval: r.interval) }

  static func isActive(_ r: RecurringRule, now: Date = .now) -> Bool {
    if r.pausedAt != nil { return false }
    if let end = r.endAt, r.nextAt > end || end < now { return false }
    return true
  }

  private static let cadences: [(Frequency, Double, Double, Double)] = [
    (.weekly, 7, 6, 8), (.monthly, 30.4, 26, 35), (.yearly, 365, 350, 380),
  ]

  private static func median(_ xs: [Double]) -> Double {
    let s = xs.sorted(); let m = s.count / 2
    return s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2
  }

  /// Needs 3 payments (2 for yearly), amounts within 10%, every gap close to the cadence (one skip is fine),
  /// and a recent last payment (no more than 1.6 cycles ago).
  static func detect(_ txns: [Txn], rules: [RecurringRule], now: Date = .now, calendar: Calendar = .current) -> [Detected] {
    let day = 86_400.0
    let since = now.addingTimeInterval(-800 * day)
    let tracked = Set(rules.compactMap { $0.payee?.lowercased() })
    var groups: [String: [Txn]] = [:]
    for t in txns where t.deletedAt == nil && t.type == .expense && t.recurringId == nil && t.occurredAt >= since {
      guard let key = t.payee?.trimmingCharacters(in: .whitespaces).lowercased(), !key.isEmpty, !tracked.contains(key) else { continue }
      groups[key, default: []].append(t)
    }
    var found: [Detected] = []
    for var list in groups.values {
      list.sort { $0.occurredAt < $1.occurredAt }
      guard let last = list.last, list.count >= 2 else { continue }
      var run: [Txn] = []
      for t in list.reversed() {
        if Double(abs(t.amount - last.amount)) > Double(last.amount) * 0.1 { break }
        run.insert(t, at: 0)
      }
      guard run.count >= 2 else { continue }
      let gaps = zip(run.dropFirst(), run).map { $0.occurredAt.timeIntervalSince($1.occurredAt) / day }
      let gap = median(gaps)
      guard let c = cadences.first(where: { gap >= $0.2 && gap <= $0.3 }) else { continue }
      if run.count < (c.0 == .yearly ? 2 : 3) { continue }
      if gaps.contains(where: { $0 < c.2 * 0.7 || $0 > c.3 * 2.1 }) { continue }
      if now.timeIntervalSince(last.occurredAt) > c.1 * 1.6 * day { continue }
      let next = calendar.date(byAdding: c.0.unit, value: 1, to: last.occurredAt)!
      found.append(Detected(payee: last.payee!.trimmingCharacters(in: .whitespaces), amount: last.amount, frequency: c.0,
                            accountId: last.accountId, categoryId: last.categoryId, lastAt: last.occurredAt, nextAt: next,
                            txnIds: run.map(\.id)))
    }
    return found.sorted { monthly(amount: $0.amount, frequency: $0.frequency) > monthly(amount: $1.amount, frequency: $1.frequency) }
  }

  /// A rule anchored on the latest payment; an overdue next payment is never invented (it starts from now).
  static func rule(for d: Detected, now: Date = .now) -> RecurringRule {
    let r = RecurringRule(type: .expense, amount: d.amount, accountId: d.accountId, categoryId: d.categoryId, payee: d.payee,
                          frequency: d.frequency, startAt: d.lastAt)
    r.nextAt = Recurrence.next(after: max(d.lastAt, now), rule: r)
    return r
  }
}
