import Foundation

/// Split v2 maths: who paid, equal / amounts / shares, with or without you. Same as Android SplitMath.
enum SplitMode: String, CaseIterable, Identifiable {
  case equal, amount, shares
  var id: String { rawValue }
  var label: String { switch self { case .equal: "Equally"; case .amount: "Amounts"; case .shares: "Shares" } }
}

struct SplitSetup: Equatable {
  /// Friend ids (you are "me").
  var people: [String] = []
  var includeMe = true
  /// nil = you paid; else the friend who paid.
  var payer: String?
  var mode: SplitMode = .equal
  /// Paise (amounts) or weights (shares), keyed by "me" or a friend id.
  var values: [String: Int] = [:]
  var groupId: String?
  var isEmpty: Bool { people.isEmpty }
}

struct SplitResult: Equatable {
  var myShare: Int
  var shares: [String: Int]
  /// Split entries: + they owe you, − you owe them.
  var entries: [String: Int]
  /// For amounts: how far the amounts are from the total (0 = balanced).
  var unassigned: Int
  var valid: Bool { unassigned == 0 }
}

enum SplitMath {
  static func compute(total: Int, _ s: SplitSetup) -> SplitResult {
    let keys = (s.includeMe ? ["me"] : []) + s.people
    var shares: [String: Int] = [:]
    var unassigned = 0
    guard !keys.isEmpty, total > 0 else { return SplitResult(myShare: total, shares: [:], entries: [:], unassigned: 0) }
    switch s.mode {
    case .equal:
      let each = total / keys.count
      keys.forEach { shares[$0] = each }
      shares[keys[0], default: 0] += total - each * keys.count
    case .amount:
      keys.forEach { shares[$0] = max(0, s.values[$0] ?? 0) }
      unassigned = total - shares.values.reduce(0, +)
    case .shares:
      let weights = keys.map { max(0, s.values[$0] ?? 1) }
      let sum = max(1, weights.reduce(0, +))
      for (k, w) in zip(keys, weights) { shares[k] = total * w / sum }
      shares[keys[0], default: 0] += total - shares.values.reduce(0, +)
    }
    let mine = s.includeMe ? shares["me"] ?? 0 : 0
    var entries: [String: Int] = [:]
    if let payer = s.payer {
      if mine > 0 { entries[payer] = -mine }
    } else {
      for f in s.people where (shares[f] ?? 0) > 0 { entries[f] = shares[f] }
    }
    return SplitResult(myShare: mine, shares: shares, entries: entries, unassigned: unassigned)
  }

  /// A UPI payment link (any UPI app pays it; also what the QR code holds).
  static func upiURL(to upiId: String, name: String, amount: Int, note: String?) -> URL? {
    var c = URLComponents()
    c.scheme = "upi"; c.host = "pay"
    c.queryItems = [URLQueryItem(name: "pa", value: upiId), URLQueryItem(name: "pn", value: name),
                    URLQueryItem(name: "am", value: String(format: "%.2f", Double(amount) / 100)), URLQueryItem(name: "cu", value: "INR")]
      + (note.map { [URLQueryItem(name: "tn", value: String($0.prefix(50)))] } ?? [])
    return c.url
  }

  /// The static pay page (GitHub Pages): the details travel only in the link's #fragment, never to a server.
  static func payPageURL(to upiId: String, name: String, amount: Int, note: String?) -> URL? {
    var c = URLComponents()
    c.queryItems = [URLQueryItem(name: "pa", value: upiId), URLQueryItem(name: "pn", value: name),
                    URLQueryItem(name: "am", value: String(format: "%.2f", Double(amount) / 100))]
      + (note.map { [URLQueryItem(name: "tn", value: String($0.prefix(50)))] } ?? [])
    return URL(string: "https://porifiro123.github.io/paisa-pulse/pay/#" + (c.percentEncodedQuery ?? ""))
  }

  static func requestMessage(friend: String, amount: Int, note: String?, upiId: String, myName: String) -> String {
    let what = note.map { " for \($0)" } ?? ""
    let link = payPageURL(to: upiId, name: myName, amount: amount, note: note)?.absoluteString ?? ""
    return "Hi \(friend), your share\(what) is \(Money.format(amount)). Pay me on UPI: \(link)"
  }
}

/// Data clean-up: transactions older than the kept period are removed and folded into opening balances.
enum Cleanup {
  static let options: [(key: String, label: String, months: Int)] = [
    ("off", "Off", 0), ("monthly", "Keep 1 month", 1), ("quarterly", "Keep 3 months", 3),
    ("halfyearly", "Keep 6 months", 6), ("yearly", "Keep 1 year", 12), ("custom", "Custom", 0),
  ]

  static func months(key: String, custom: Int) -> Int? {
    if key == "custom" { return custom > 0 ? custom : nil }
    let m = options.first { $0.key == key }?.months ?? 0
    return m > 0 ? m : nil
  }

  static func cutoff(months: Int, now: Date = .now, calendar: Calendar = .current) -> Date {
    calendar.startOfDay(for: calendar.date(byAdding: .month, value: -months, to: now)!)
  }

  /// Opening-balance changes per account and the transactions to remove (live and deleted) before `cutoff`.
  static func plan(_ txns: [Txn], before cutoff: Date) -> (delta: [String: Int], remove: Set<String>) {
    var delta: [String: Int] = [:]
    var remove = Set<String>()
    for t in txns where t.occurredAt < cutoff {
      remove.insert(t.id)
      guard t.deletedAt == nil else { continue }
      switch t.type {
      case .expense: delta[t.accountId, default: 0] -= t.amount
      case .income: delta[t.accountId, default: 0] += t.amount
      case .transfer:
        delta[t.accountId, default: 0] -= t.amount
        if let to = t.toAccountId { delta[to, default: 0] += t.amount }
      }
    }
    return (delta, remove)
  }
}

enum LoanMath {
  static func repaid(_ loan: Loan, _ payments: [LoanPayment]) -> Int { payments.filter { $0.loanId == loan.id }.reduce(0) { $0 + $1.amount } }
  static func outstanding(_ loan: Loan, _ payments: [LoanPayment]) -> Int { max(0, loan.amount - repaid(loan, payments)) }
}

extension String {
  var nilIfEmpty: String? { let t = trimmingCharacters(in: .whitespaces); return t.isEmpty ? nil : t }
}
