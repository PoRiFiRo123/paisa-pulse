import Foundation

/// The monthly report: every category this month vs last, and the biggest movers. Same rules as Android Report.kt.
enum Report {
  struct Row: Equatable { let categoryId: String; let amount: Int; let before: Int; var diff: Int { amount - before } }

  static func rows(txns: [Txn], categories: [String: Category], month: DateInterval, previous: DateInterval) -> [Row] {
    let now = Dictionary(uniqueKeysWithValues: Ledger.byCategory(txns, in: month, categories: categories).map { ($0.id, $0.amount) })
    let before = Dictionary(uniqueKeysWithValues: Ledger.byCategory(txns, in: previous, categories: categories).map { ($0.id, $0.amount) })
    var seen = Set<String>()
    let ids = (Array(now.keys) + Array(before.keys)).filter { seen.insert($0).inserted }
    return ids.map { Row(categoryId: $0, amount: now[$0] ?? 0, before: before[$0] ?? 0) }
      .sorted { ($0.amount, $0.before) > ($1.amount, $1.before) }
  }

  /// Categories that went up the most and down the most (by amount), up to `limit` each.
  static func movers(_ rows: [Row], limit: Int = 3) -> (up: [Row], down: [Row]) {
    (Array(rows.filter { $0.diff > 0 }.sorted { $0.diff > $1.diff }.prefix(limit)),
     Array(rows.filter { $0.diff < 0 }.sorted { $0.diff < $1.diff }.prefix(limit)))
  }

  /// The biggest expenses of the month, largest first.
  static func biggest(txns: [Txn], month: DateInterval, limit: Int = 5) -> [Txn] {
    Array(txns.filter { $0.deletedAt == nil && $0.type == .expense && month.contains($0.occurredAt) }
      .sorted { $0.effectiveAmount > $1.effectiveAmount }.prefix(limit))
  }
}
