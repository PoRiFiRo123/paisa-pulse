import Foundation

/// What you own vs what you owe, by account type. Same rules as Android NetWorth.kt.
enum NetWorth {
  struct Breakdown: Equatable {
    var assets = 0
    var owed = 0
    /// Account type label → its total (owed amounts are positive here), largest first.
    var byType: [(label: String, amount: Int, owed: Bool)] = []
    var total: Int { assets - owed }
    static func == (a: Breakdown, b: Breakdown) -> Bool { a.assets == b.assets && a.owed == b.owed && a.byType.map { $0.label } == b.byType.map { $0.label } }
  }

  static func breakdown(accounts: [Account], balances: [String: Int]) -> Breakdown {
    var b = Breakdown()
    var groups: [String: (Int, Bool)] = [:]
    for a in accounts where a.archivedAt == nil && !a.excludeFromTotals {
      let v = balances[a.id] ?? 0
      if v >= 0 { b.assets += v } else { b.owed += -v }
      let owed = v < 0
      let key = owed ? "\(a.type.plural) (owed)" : a.type.plural
      groups[key] = ((groups[key]?.0 ?? 0) + abs(v), owed)
    }
    b.byType = groups.filter { $0.value.0 > 0 }.map { (label: $0.key, amount: $0.value.0, owed: $0.value.1) }.sorted { $0.amount > $1.amount }
    return b
  }
}
