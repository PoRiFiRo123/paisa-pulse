import Foundation

// Payment method, currencies (main currency, conversions, card forex markup) and trips.
// Same rules as Android (logic/V2.kt); tested in V2Tests.

/// How a transaction was paid. Stored as `rawValue` on Txn.paymentMethod.
enum PaymentMethod: String, CaseIterable, Identifiable {
  case upi, debitCard = "debit_card", creditCard = "credit_card", netBanking = "net_banking", neft, imps, rtgs, cash, cheque, wallet
  case autoDebit = "auto_debit", other
  var id: String { rawValue }

  var label: String {
    switch self {
    case .upi: "UPI"
    case .debitCard: "Debit card"
    case .creditCard: "Credit card"
    case .netBanking: "Net banking"
    case .neft: "NEFT"
    case .imps: "IMPS"
    case .rtgs: "RTGS"
    case .cash: "Cash"
    case .cheque: "Cheque"
    case .wallet: "Wallet"
    case .autoDebit: "Auto-debit"
    case .other: "Other"
    }
  }

  var icon: String {
    switch self {
    case .upi: "qrcode"
    case .debitCard: "creditcard"
    case .creditCard: "creditcard.fill"
    case .netBanking: "building.columns"
    case .neft: "arrow.left.arrow.right"
    case .imps: "bolt"
    case .rtgs: "banknote"
    case .cash: "banknote.fill"
    case .cheque: "doc.text"
    case .wallet: "wallet.bifold.fill"
    case .autoDebit: "arrow.triangle.2.circlepath"
    case .other: "ellipsis.circle"
    }
  }

  /// From the account and card picked: cash → Cash, a credit card → Credit card, a debit card → Debit card.
  static func guess(accountType: AccountType?, cardKind: String?) -> PaymentMethod? {
    if cardKind == "credit" { return .creditCard }
    if cardKind == "debit" { return .debitCard }
    switch accountType {
    case .cash: return .cash
    case .card: return .creditCard
    case .wallet: return .wallet
    case .bank: return .upi
    default: return nil
    }
  }

  /// From statement narrations, screenshots and SMS: "UPI/DR/…", "NEFT-…", "POS 1234 …", "NACH".
  static func fromText(_ text: String) -> PaymentMethod? {
    let t = text.lowercased()
    func has(_ p: String) -> Bool { t.range(of: p, options: .regularExpression) != nil }
    if has("\\b(nach|ecs|mandate|autopay|auto debit|auto-debit|standing instruction|\\bsi\\b)") { return .autoDebit }
    if has("\\brtgs\\b") { return .rtgs }
    if has("\\bneft\\b") { return .neft }
    if has("\\bimps\\b") { return .imps }
    if has("\\bupi\\b|@[a-z]{2,}\\b|\\bvpa\\b") { return .upi }
    if has("\\b(chq|cheque|clg|clearing)\\b") { return .cheque }
    if has("\\b(net ?banking|inb|ib fund|internet banking)\\b") { return .netBanking }
    if has("\\b(atm|cash wdl|cash withdrawal)\\b") { return .debitCard }
    if has("\\b(pos|ecom|card \\d{4}|debit card)\\b") { return .debitCard }
    return nil
  }
}

/// Exchange rates are kept as rupees per unit (open.er-api.com, INR base); this converts between any two.
enum Fx {
  /// Units of `to` per 1 unit of `from`. INR is 1.0 when missing.
  static func rate(from: String, to: String, inrPer: [String: Double]) -> Double? {
    if from == to { return 1 }
    guard let f = from == "INR" ? 1 : inrPer[from], let t = to == "INR" ? 1 : inrPer[to] else { return nil }
    return f / t
  }
  /// Minor units (×100) of one currency → minor units of another at `rate` (to per from).
  static func convert(_ minor: Int, rate: Double) -> Int { Int((Double(minor) * rate).rounded()) }
}

/// A card's foreign-currency markup, in basis points (413 = 4.13% = 3.5% + 18% GST on it).
enum ForexMarkup {
  static let defaultBps = 413
  static func apply(_ base: Int, bps: Int?) -> Int {
    guard let bps, bps > 0 else { return base }
    return Int((Double(base) * (1 + Double(bps) / 10_000)).rounded())
  }
  static func fee(_ base: Int, bps: Int?) -> Int { apply(base, bps: bps) - base }
  /// "3.5% + GST" → 413.
  static func bps(percent: Double, withGst: Bool) -> Int { Int((percent * 100 * (withGst ? 1.18 : 1)).rounded()) }
  static func label(_ bps: Int?) -> String {
    guard let bps, bps > 0 else { return "No markup" }
    return String(format: "%.2f%%", Double(bps) / 100)
  }
}

// MARK: - Trips

/// Event types with their ready-made budget items (international trips add the extras).
enum TripKinds {
  struct Kind: Identifiable, Hashable {
    let id, label, icon, color: String
    let dated, places: Bool
    let items: [String]
    var intlItems: [String] = []
  }
  static let all: [Kind] = [
    Kind(id: "trip", label: "Trip", icon: "airplane", color: "#2563EB", dated: true, places: true,
         items: ["Flights & tickets", "Stay", "Food", "Local travel", "Activities", "Shopping", "Miscellaneous"],
         intlItems: ["Travel insurance", "Visa & documents", "SIM & roaming", "Forex fees"]),
    Kind(id: "vacation", label: "Vacation", icon: "beach.umbrella.fill", color: "#0891B2", dated: true, places: true,
         items: ["Travel", "Stay", "Food", "Activities", "Shopping", "Local travel", "Miscellaneous"], intlItems: ["Travel insurance", "Visa & documents"]),
    Kind(id: "weekend", label: "Weekend getaway", icon: "tent.fill", color: "#16A34A", dated: true, places: true,
         items: ["Travel", "Stay", "Food", "Activities", "Miscellaneous"]),
    Kind(id: "business", label: "Business trip", icon: "briefcase.fill", color: "#334155", dated: true, places: true,
         items: ["Flights", "Stay", "Food", "Local travel", "Meetings", "Client entertainment", "Miscellaneous"], intlItems: ["Visa", "Insurance"]),
    Kind(id: "event", label: "Event", icon: "party.popper.fill", color: "#DB2777", dated: true, places: false,
         items: ["Venue", "Food", "Decorations", "Entertainment", "Gifts", "Travel", "Miscellaneous"]),
    Kind(id: "outing", label: "Outing", icon: "fork.knife", color: "#EA580C", dated: false, places: false,
         items: ["Food", "Drinks", "Travel", "Tips", "Miscellaneous"]),
    Kind(id: "ride", label: "Ride", icon: "car.fill", color: "#7C3AED", dated: false, places: false,
         items: ["Fuel", "Toll", "Parking", "Food", "Miscellaneous"]),
    Kind(id: "custom", label: "Custom", icon: "star.fill", color: "#6B7280", dated: true, places: false, items: []),
  ]
  static func of(_ id: String?) -> Kind { all.first { $0.id == id } ?? all[all.count - 1] }
  static func items(_ kind: String, international: Bool) -> [String] {
    let k = of(kind)
    guard international, !k.items.isEmpty else { return k.items }
    return Array(k.items.dropLast()) + k.intlItems + [k.items[k.items.count - 1]]
  }
}

enum TripMath {
  enum Status: String { case upcoming, ongoing, completed }

  struct ItemSpend: Identifiable { let item: TripItem; let spent: Int; var id: String { item.id }; var remaining: Int { (item.budget ?? 0) - spent } }
  struct WalletLeft: Identifiable { let wallet: TripWallet; let spent: Int; var id: String { wallet.id }; var left: Int { wallet.amount - spent } }
  struct Summary {
    let trip: Trip, status: Status, items: [ItemSpend], unassigned: Int
    /// Your share of the trip (what it cost you).
    let spent: Int
    /// Everything paid for the trip, whoever's share (split bills count in full).
    let groupCost: Int
    let budget: Int, wallets: [WalletLeft]
    /// Foreign spending by currency (original amounts).
    let byCurrency: [String: Int]
    let count: Int, day: Int?, days: Int?, daysToGo: Int?
    var remaining: Int { budget - spent }
    var overBudget: Bool { budget > 0 && spent > budget }
    var perPerson: Int { trip.travellers > 1 ? groupCost / trip.travellers : groupCost }
    var progress: Double { budget > 0 ? Double(spent) / Double(budget) : 0 }
  }

  static func status(_ trip: Trip, now: Date = .now, calendar: Calendar = .current) -> Status {
    guard let start = trip.startAt else { return .completed }
    let today = calendar.startOfDay(for: now)
    let end = calendar.startOfDay(for: trip.endAt ?? start)
    if today < calendar.startOfDay(for: start) { return .upcoming }
    if today > end { return .completed }
    return .ongoing
  }

  /// The trip happening now (the most recently started), for Quick Add's automatic link.
  static func ongoing(_ trips: [Trip], now: Date = .now, calendar: Calendar = .current) -> Trip? {
    trips.filter { $0.archivedAt == nil && $0.startAt != nil && status($0, now: now, calendar: calendar) == .ongoing }
      .max { ($0.startAt ?? .distantPast) < ($1.startAt ?? .distantPast) }
  }

  static func summary(_ trip: Trip, items: [TripItem], wallets: [TripWallet], txns: [Txn], now: Date = .now, calendar: Calendar = .current) -> Summary {
    let mine = txns.filter { $0.deletedAt == nil && $0.tripId == trip.id }
    let expenses = mine.filter { $0.type == .expense }
    let its = items.filter { $0.tripId == trip.id }.sorted { $0.sortOrder < $1.sortOrder }
      .map { i in ItemSpend(item: i, spent: expenses.filter { $0.tripItemId == i.id }.reduce(0) { $0 + $1.effectiveAmount }) }
    let known = Set(its.map(\.item.id))
    // A wallet in the main currency (currency nil) counts the main amount; a foreign one counts the original
    // amount when the spend was in its currency, else the main amount at the wallet's rate.
    let ws = wallets.filter { $0.tripId == trip.id }.map { w in
      WalletLeft(wallet: w, spent: expenses.filter { $0.walletId == w.id }.reduce(0) { sum, t in
        if w.currency == nil { return sum + t.amount }
        if t.currency == w.currency, let o = t.originalAmount { return sum + o }
        return sum + Int((Double(t.amount) / w.rate).rounded())
      })
    }
    var byCurrency: [String: Int] = [:]
    for t in expenses { if let c = t.currency, let o = t.originalAmount { byCurrency[c, default: 0] += o } }
    let st = status(trip, now: now, calendar: calendar)
    let start = trip.startAt.map { calendar.startOfDay(for: $0) }
    let end = (trip.endAt ?? trip.startAt).map { calendar.startOfDay(for: $0) }
    let today = calendar.startOfDay(for: now)
    func between(_ a: Date, _ b: Date) -> Int { calendar.dateComponents([.day], from: a, to: b).day ?? 0 }
    return Summary(
      trip: trip, status: st, items: its,
      unassigned: expenses.filter { $0.tripItemId == nil || !known.contains($0.tripItemId ?? "") }.reduce(0) { $0 + $1.effectiveAmount },
      spent: expenses.reduce(0) { $0 + $1.effectiveAmount }, groupCost: expenses.reduce(0) { $0 + $1.amount },
      budget: trip.budgetEnabled ? its.reduce(0) { $0 + ($1.item.budget ?? 0) } : 0,
      wallets: ws, byCurrency: byCurrency, count: mine.count,
      day: st == .ongoing ? start.map { between($0, today) + 1 } : nil,
      days: (start != nil && end != nil) ? between(start!, end!) + 1 : nil,
      daysToGo: st == .upcoming ? start.map { between(today, $0) } : nil)
  }

  /// Transactions budgets should count: trips switched to "Don't count in budgets" are left out.
  static func budgetTxns(_ txns: [Txn], trips: [Trip]) -> [Txn] {
    let excluded = Set(trips.filter { !$0.countInBudgets }.map(\.id))
    guard !excluded.isEmpty else { return txns }
    return txns.filter { $0.tripId == nil || !excluded.contains($0.tripId ?? "") }
  }

  struct Overview { let upcoming, ongoing, completed, planned, spent, overBudget: Int }
  static func overview(_ s: [Summary]) -> Overview {
    Overview(upcoming: s.filter { $0.status == .upcoming }.count, ongoing: s.filter { $0.status == .ongoing }.count,
             completed: s.filter { $0.status == .completed }.count, planned: s.reduce(0) { $0 + $1.budget },
             spent: s.reduce(0) { $0 + $1.spent }, overBudget: s.filter(\.overBudget).count)
  }
}
