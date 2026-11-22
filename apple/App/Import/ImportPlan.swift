import Foundation
import SwiftData

/// One statement row ready for review: everything the user can change before importing. Same as Android PlannedRow.
struct PlannedRow: Identifiable, Hashable {
  var id: String { key }
  let key: String
  let row: StatementRow
  let narration: Narration
  var type: TxnType
  var otherAccountId: String?
  var categoryId: String?
  var payee: String?
  var note: String?
  /// "new" | "duplicate" | "possible-duplicate"
  var status: String
  var duplicateOf: String?
  var include: Bool
  var hint: String?
}

enum ImportPlan {
  /// Same fingerprint as the RN and Android apps (so re-imports are recognised across apps). UTF-16 code units.
  static func fingerprint(_ text: String) -> String {
    var h1: UInt32 = 0x811c9dc5, h2: UInt32 = 0xcbf29ce4
    let p1: UInt32 = 0x01000193, p2: UInt32 = 0x01000193 ^ 0x5bd1e995
    for c in text.utf16 {
      h1 = (h1 ^ UInt32(c)) &* p1
      h2 = (h2 ^ UInt32(c)) &* p2
    }
    func hex(_ v: UInt32) -> String { let s = String(v, radix: 16); return String(repeating: "0", count: 8 - s.count) + s }
    return hex(h1) + hex(h2)
  }

  private static func ymd(_ d: Date, _ cal: Calendar) -> String {
    let c = cal.dateComponents([.year, .month, .day], from: d)
    return "\(c.year!)-\(c.month!)-\(c.day!)"
  }

  static func rowKeys(accountId: String, rows: [StatementRow], calendar: Calendar = .current) -> [String] {
    var seen: [String: Int] = [:]
    let ws = Rx("\\s+")
    return rows.map { r in
      let parts = [accountId, ymd(r.date, calendar), r.out ? "out" : "in", String(r.amount),
                   ws.replace(r.description.lowercased(), with: " "), r.reference, r.balance.map(String.init) ?? ""]
      let base = fingerprint(parts.joined(separator: "|"))
      let n = (seen[base] ?? 0) + 1
      seen[base] = n
      return n == 1 ? base : "\(base)#\(n)"
    }
  }

  private static func mentioned(_ text: String, _ account: Account, _ all: [Account]) -> Account? {
    let t = text.lowercased()
    return all.first { a in
      guard a.id != account.id else { return false }
      if let l4 = a.last4, Rx("(x|\\*|\\b)\(NSRegularExpression.escapedPattern(for: l4))\\b").test(text) { return true }
      return a.name.count > 5 && t.contains(a.name.lowercased())
    }
  }

  static func plan(accountId: String, rows: [StatementRow], accounts: [Account], categories: [Category], txns: [Txn],
                   calendar: Calendar = .current) -> [PlannedRow] {
    let all = accounts.filter { $0.archivedAt == nil }
    guard let account = accounts.first(where: { $0.id == accountId }) else { return [] }
    let cats = categories.filter { $0.archivedAt == nil }
    func byName(_ name: String, _ kind: CategoryKind) -> String? { cats.first { $0.kind == kind && $0.name == name }?.id }
    let cards = all.filter { $0.type == .card && $0.id != account.id }
    let banks = all.filter { $0.type == .bank && $0.id != account.id }
    let cash = all.first { $0.type == .cash && $0.id != account.id }
    let live = txns.filter { $0.deletedAt == nil }
    var counts: [String: [String: Int]] = [:]
    for t in live { if let p = t.payee?.lowercased(), let c = t.categoryId { counts[p, default: [:]][c, default: 0] += 1 } }
    let learned = counts.mapValues { byCat in byCat.max { a, b in a.value < b.value }!.key }
    let keys = rowKeys(accountId: account.id, rows: rows, calendar: calendar)

    var planned: [PlannedRow] = rows.enumerated().map { i, row in
      let n = Narrations.parse(row.description)
      var type: TxnType = row.out ? .expense : .income
      var other: Account?
      var hint: String?
      var include = true
      let m = mentioned(row.description, account, all)
      if n.channel == "CARD_PAYMENT" {
        if account.type == .card && !row.out {
          other = m ?? banks.first
          hint = other.map { "Card bill paid from \($0.name)" } ?? "Card bill payment: add your bank account to pair it"
          if other == nil { include = false }
        } else if row.out {
          other = cards.first { c in c.last4.map { row.description.contains($0) } ?? false } ?? m ?? cards.first
          hint = other.map { "Paid your \($0.name) bill" }
        }
      } else if n.channel == "ATM" && row.out, let cash {
        other = cash; hint = "Cash withdrawal → Cash"
      } else if let m, account.type != .card {
        other = m; hint = row.out ? "Moved to \(m.name)" : "Moved from \(m.name)"
      }
      if other != nil { type = .transfer }
      var categoryId: String?
      if type != .transfer {
        let kind: CategoryKind = type == .income ? .income : .expense
        let hist = n.payee.flatMap { learned[$0.lowercased()] }.flatMap { id in cats.first { $0.id == id && $0.kind == kind }?.id }
        categoryId = hist ?? Narrations.suggestCategory(row.description, payee: n.payee, out: row.out).flatMap { byName($0, kind) }
      }
      return PlannedRow(key: keys[i], row: row, narration: n, type: type, otherAccountId: other?.id, categoryId: categoryId,
                        payee: n.payee, note: n.note, status: "new", duplicateOf: nil, include: include, hint: hint)
    }

    let existing = Set(live.compactMap(\.externalId))
    for i in planned.indices where existing.contains(planned[i].key) {
      planned[i].status = "duplicate"; planned[i].include = false; planned[i].hint = "Already imported"
    }

    if let minDate = rows.map(\.date).min(), let maxDate = rows.map(\.date).max() {
      let from = minDate.addingTimeInterval(-2 * 86_400), to = maxDate.addingTimeInterval(2 * 86_400)
      let candidates = live.filter { $0.occurredAt >= from && $0.occurredAt <= to && ($0.accountId == account.id || $0.toAccountId == account.id) }
      func day(_ d: Date) -> Int { calendar.ordinality(of: .day, in: .era, for: d) ?? 0 }
      var used = Set<String>()
      for i in planned.indices where planned[i].status == "new" {
        let p = planned[i]
        var best: (id: String, d: Int)?
        for t in candidates where !used.contains(t.id) && t.amount == p.row.amount {
          let out = t.accountId == account.id && t.type != .income
          if out != p.row.out { continue }
          let d = abs(day(t.occurredAt) - day(p.row.date))
          if d <= 1 && (best == nil || d < best!.d) { best = (t.id, d) }
        }
        if let best {
          used.insert(best.id)
          planned[i].status = "possible-duplicate"; planned[i].duplicateOf = best.id; planned[i].include = false
          planned[i].hint = "Looks like one you already added"
        }
      }
    }
    return planned
  }

  /// Adds the included rows as one batch (so the whole import can be undone). Returns the batch.
  @MainActor @discardableResult
  static func commit(accountId: String, fileName: String, template: String?, rows: [PlannedRow], context: ModelContext, now: Date = .now) -> ImportBatch {
    let chosen = rows.filter(\.include)
    let batch = ImportBatch(accountId: accountId, fileName: fileName, template: template, count: chosen.count, createdAt: now)
    context.insert(batch)
    for r in chosen {
      let transfer = r.type == .transfer && r.otherAccountId != nil
      let intoThis = !r.row.out
      let type: TxnType = transfer ? .transfer : r.type == .transfer ? (intoThis ? .income : .expense) : r.type
      context.insert(Txn(type: type, amount: r.row.amount,
                         accountId: transfer && intoThis ? r.otherAccountId! : accountId,
                         toAccountId: transfer ? (intoThis ? accountId : r.otherAccountId) : nil,
                         categoryId: transfer ? nil : r.categoryId, payee: r.payee, note: r.note, occurredAt: r.row.date,
                         source: "import", importBatchId: batch.id, externalId: r.key, createdAt: now, updatedAt: now))
    }
    try? context.save()
    return batch
  }
}
