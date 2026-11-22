import CommonCrypto
import CryptoKit
import Foundation

// Batch 4 logic, the same rules as Android's logic/Batch4.kt.

/// Payee memory: what you typed before, with the category and account you used for it.
enum PayeeMemory {
  struct Suggestion: Hashable { let payee: String; let categoryId: String?; let accountId: String; let count: Int }

  static func suggestions(_ prefix: String, txns: [Txn], type: TxnType, limit: Int = 4) -> [Suggestion] {
    let q = prefix.trimmingCharacters(in: .whitespaces).lowercased()
    guard !q.isEmpty else { return [] }
    var groups: [String: (payee: String, latest: Txn, count: Int)] = [:]
    for t in txns where t.deletedAt == nil && t.type == type {
      guard let p = t.payee?.trimmingCharacters(in: .whitespaces), !p.isEmpty else { continue }
      let key = p.lowercased()
      guard key.hasPrefix(q) || key.contains(" " + q), key != q else { continue }
      if let g = groups[key] {
        groups[key] = (g.payee, t.occurredAt > g.latest.occurredAt ? t : g.latest, g.count + 1)
      } else { groups[key] = (p, t, 1) }
    }
    return groups.values
      .sorted { ($0.count, $0.latest.occurredAt) > ($1.count, $1.latest.occurredAt) }
      .prefix(limit)
      .map { Suggestion(payee: $0.payee, categoryId: $0.latest.categoryId, accountId: $0.latest.accountId, count: $0.count) }
  }
}

/// Tags: "goa trip, work" → ["goa-trip", "work"].
enum Tags {
  static func parse(_ text: String) -> [String] {
    var seen = Set<String>()
    return text.split(whereSeparator: { $0 == "," || $0 == "#" }).compactMap { raw -> String? in
      let t = raw.trimmingCharacters(in: .whitespaces).lowercased().split(whereSeparator: \.isWhitespace).joined(separator: "-")
      guard !t.isEmpty, seen.insert(t).inserted else { return nil }
      return t
    }
  }
  static func text(_ tags: [String]) -> String { tags.joined(separator: ", ") }
}

/// Month-end forecast for the money you can spend (bank, cash, wallets).
enum Forecast {
  struct Result: Equatable { let now: Int; let incoming: Int; let outgoing: Int; let dailySpend: Int; let daysLeft: Int; let projected: Int }

  static func monthEnd(accounts: [Account], txns: [Txn], valuations: [Valuation] = [], rules: [RecurringRule], month: DateInterval,
                       now: Date = .now, calendar: Calendar = .current) -> Result {
    let liquid = accounts.filter { $0.archivedAt == nil && !$0.excludeFromTotals && [.bank, .cash, .wallet].contains($0.type) }
    let ids = Set(liquid.map(\.id))
    let b = Ledger.balances(accounts: accounts, txns: txns, valuations: valuations)
    let current = liquid.reduce(0) { $0 + (b[$1.id] ?? 0) }
    var incoming = 0, outgoing = 0
    for r in rules where r.pausedAt == nil {
      var next = r.nextAt
      var guardCount = 0
      while next < month.end && next >= now && guardCount < 40 {
        if let end = r.endAt, next > end { break }
        if r.type == .income && ids.contains(r.accountId) { incoming += r.amount }
        if r.type == .expense && ids.contains(r.accountId) { outgoing += r.amount }
        if r.type == .transfer, let to = r.toAccountId {
          if ids.contains(r.accountId) && !ids.contains(to) { outgoing += r.amount }
          if !ids.contains(r.accountId) && ids.contains(to) { incoming += r.amount }
        }
        next = Recurrence.next(after: next, rule: r); guardCount += 1
      }
    }
    // Everyday spending: your non-recurring expenses over the last 90 days.
    let since = calendar.date(byAdding: .day, value: -90, to: now)!
    let everyday = txns.filter { $0.deletedAt == nil && $0.type == .expense && $0.recurringId == nil && $0.occurredAt >= since && $0.occurredAt <= now }
      .reduce(0) { $0 + $1.effectiveAmount }
    let daily = everyday / 90
    let daysLeft = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: month.end).day ?? 0)
    return Result(now: current, incoming: incoming, outgoing: outgoing, dailySpend: daily, daysLeft: daysLeft,
                  projected: current + incoming - outgoing - daily * daysLeft)
  }
}

/// "Your November": a month in a few numbers.
enum Recap {
  struct Result: Equatable {
    let spent: Int, income: Int, previousSpent: Int, count: Int
    let topCategoryId: String?, topCategoryAmount: Int
    let biggestId: String?, topPayee: String?, topPayeeCount: Int
    let noSpendDays: Int, longestNoSpendStreak: Int, days: Int
    var change: Double? { previousSpent > 0 ? Double(spent - previousSpent) / Double(previousSpent) : nil }
    var saved: Int { income - spent }
  }

  static func make(txns: [Txn], categories: [String: Category], month: DateInterval, previous: DateInterval, now: Date = .now,
                   calendar: Calendar = .current) -> Result {
    let s = Ledger.summary(txns, in: month)
    let p = Ledger.summary(txns, in: previous)
    let inMonth = txns.filter { $0.deletedAt == nil && month.contains($0.occurredAt) }
    let expenses = inMonth.filter { $0.type == .expense }
    let top = Ledger.byCategory(txns, in: month, categories: categories).first
    let biggest = expenses.max { $0.effectiveAmount < $1.effectiveAmount }
    let payees = Dictionary(grouping: expenses.compactMap { $0.payee?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }, by: { $0.lowercased() })
    let topPayee = payees.values.max { $0.count < $1.count }
    let spendDays = Set(expenses.map { calendar.startOfDay(for: $0.occurredAt) })
    var day = calendar.startOfDay(for: month.start)
    let last = min(month.end, calendar.startOfDay(for: now).addingTimeInterval(86_400))
    var days = 0, free = 0, streak = 0, best = 0
    while day < last {
      days += 1
      if spendDays.contains(day) { streak = 0 } else { free += 1; streak += 1; best = max(best, streak) }
      day = calendar.date(byAdding: .day, value: 1, to: day)!
    }
    return Result(spent: s.spent, income: s.income, previousSpent: p.spent, count: inMonth.count,
                  topCategoryId: top?.id, topCategoryAmount: top?.amount ?? 0, biggestId: biggest?.id,
                  topPayee: topPayee?.first, topPayeeCount: topPayee?.count ?? 0, noSpendDays: free, longestNoSpendStreak: best, days: days)
  }
}

/// A credit card's last statement: what it came to and what's still to pay.
enum CardStatement {
  struct Result: Equatable { let cycle: DateInterval; let billed: Int; let paid: Int; var due: Int { max(0, billed - paid) } }

  static func last(account: Account, txns: [Txn], now: Date = .now, calendar: Calendar = .current) -> Result? {
    guard let s = account.statementDay else { return nil }
    let current = Cards.cycle(statementDay: s, containing: now, calendar: calendar)
    let previous = DateInterval(start: calendar.date(byAdding: .month, value: -1, to: current.start)!, end: current.start)
    let live = txns.filter { $0.deletedAt == nil }
    let billed = live.filter { $0.accountId == account.id && previous.contains($0.occurredAt) }.reduce(0) { sum, t in
      switch t.type {
      case .expense: sum + t.amount
      case .income: sum - t.amount
      case .transfer: t.toAccountId == nil ? sum : sum + t.amount
      }
    }
    let paid = live.filter { $0.type == .transfer && $0.toAccountId == account.id && $0.occurredAt >= current.start }.reduce(0) { $0 + $1.amount }
    return Result(cycle: previous, billed: max(0, billed), paid: paid)
  }
}

/// The Home screen's sections, in your order; hidden ones are kept in `hidden`.
enum HomeSections {
  static let all: [(key: String, label: String, icon: String)] = [
    ("hero", "This month", "indianrupeesign.circle.fill"), ("templates", "Quick add", "bolt.fill"),
    ("forecast", "Month-end forecast", "chart.line.uptrend.xyaxis"), ("cards", "Card bills", "creditcard.fill"),
    ("categories", "Where it went", "chart.pie.fill"), ("budgets", "Budgets", "gauge.with.dots.needle.67percent"),
    ("goals", "Goals", "target"), ("upcoming", "Next 7 days", "calendar"), ("recap", "Monthly recap", "sparkles"),
    ("recent", "Recent", "clock.fill"),
  ]

  /// Saved order first (unknown keys dropped), then any section added since.
  static func order(_ saved: String) -> [String] {
    let known = Set(all.map(\.key))
    let s = saved.split(separator: ",").map(String.init).filter { known.contains($0) }
    return s + all.map(\.key).filter { !s.contains($0) }
  }
  static func hidden(_ saved: String) -> Set<String> { Set(saved.split(separator: ",").map(String.init)) }
}

/// Password-protected backups: AES-256-GCM, key from PBKDF2-SHA256 (200,000 rounds). Same file on Android.
enum BackupCrypto {
  struct Envelope: Codable {
    var paisaEncrypted = 1
    var kdf = "pbkdf2-sha256"
    var iterations: Int
    var salt: String
    var iv: String
    /// Ciphertext followed by the 16-byte GCM tag, base64.
    var data: String
  }
  enum Failure: Error { case wrongPassword, notEncrypted }

  static func isEncrypted(_ data: Data) -> Bool { (try? JSONDecoder().decode(Envelope.self, from: data)) != nil }

  static func key(_ password: String, salt: Data, iterations: Int) -> SymmetricKey {
    var out = [UInt8](repeating: 0, count: 32)
    let pw = Array(password.utf8)
    _ = salt.withUnsafeBytes { s in
      CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pw.map { Int8(bitPattern: $0) }, pw.count,
                           s.bindMemory(to: UInt8.self).baseAddress, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                           UInt32(iterations), &out, out.count)
    }
    return SymmetricKey(data: out)
  }

  static func encrypt(_ plain: Data, password: String, iterations: Int = 200_000) throws -> Data {
    var salt = Data(count: 16); salt.withUnsafeMutableBytes { _ = SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
    let nonce = AES.GCM.Nonce()
    let box = try AES.GCM.seal(plain, using: key(password, salt: salt, iterations: iterations), nonce: nonce)
    let env = Envelope(iterations: iterations, salt: salt.base64EncodedString(), iv: Data(nonce).base64EncodedString(),
                       data: (box.ciphertext + box.tag).base64EncodedString())
    let enc = JSONEncoder(); enc.outputFormatting = [.withoutEscapingSlashes]
    return try enc.encode(env)
  }

  static func decrypt(_ file: Data, password: String) throws -> Data {
    guard let env = try? JSONDecoder().decode(Envelope.self, from: file), let salt = Data(base64Encoded: env.salt),
          let iv = Data(base64Encoded: env.iv), let all = Data(base64Encoded: env.data), all.count >= 16 else { throw Failure.notEncrypted }
    do {
      let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv), ciphertext: all.dropLast(16), tag: all.suffix(16))
      return try AES.GCM.open(box, using: key(password, salt: salt, iterations: env.iterations))
    } catch { throw Failure.wrongPassword }
  }
}

/// The backup password for automatic backups, in the Keychain (this device only).
enum BackupPassword {
  private static let account = "backup-password"
  static var value: String? {
    get {
      var out: AnyObject?
      let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account, kSecReturnData as String: true]
      guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
      return String(data: d, encoding: .utf8)
    }
    set {
      let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account]
      SecItemDelete(q as CFDictionary)
      guard let v = newValue, !v.isEmpty else { return }
      var add = q
      add[kSecValueData as String] = Data(v.utf8)
      add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      SecItemAdd(add as CFDictionary, nil)
    }
  }
}
