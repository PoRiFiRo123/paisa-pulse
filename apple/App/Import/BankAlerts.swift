import AppIntents
import Foundation

// Bank SMS and payment notifications → a draft to confirm. Same rules and tests as Android BankAlerts.kt.
// iOS doesn't let apps read SMS, so a Shortcuts "Message" automation hands each bank message to the
// "Log Bank Message" action below, which queues it for review.

/// A bank alert waiting for review: the raw text and when it arrived.
struct PendingAlert: Codable, Hashable {
  var text: String
  var sender: String?
  var receivedAt: Date
}

enum BankAlerts {
  private static let ignore = Rx("\\b(otp|one[- ]time password|verification code|will be (auto[- ]?)?debited|is due|due (on|date|by)|minimum (amount )?due|" +
    "has requested|requested (money|rs|inr|₹)|collect request|request of|failed|declined|unsuccessful|reversal|reversed|" +
    "pre-?approved|apply now|offer|cashback of up to|e-?mandate (is )?(created|registered)|statement (is|has been) generated)\\b")
  private static let debit = Rx("\\b(debited|spent|sent|paid|withdrawn|purchase|deducted|transferred from|txn of|dr\\.?)\\b")
  private static let credit = Rx("\\b(credited|received|deposited|cr\\.?)\\b")
  private static let money = Rx("(?:rs\\.?|inr|₹)\\s*([\\d,]+(?:\\.\\d{1,2})?)")
  private static let bareAmount = Rx("\\b(?:debited|credited|spent|sent|paid)\\s+(?:by|with|for|of)?\\s*([\\d,]+(?:\\.\\d{1,2})?)\\b")
  private static let notTheAmount = Rx("(avl|avbl|available|total|a/c|acct)?\\.?\\s*(bal|balance|lmt|limit)\\s*:?\\s*$")
  private static let last4 = Rx("(?:x{2,}|\\*+|\\.{2,}|ending(?:\\s+(?:with|in))?\\s*|a/c\\s*(?:no\\.?)?\\s*[x*]*|acct\\s*[x*]*|card\\s*(?:no\\.?)?\\s*[x*]*)(\\d{3,4})\\b")
  private static let ref = Rx("(?:ref(?:erence)?(?:\\s*no\\.?)?|rrn|utr|upi(?:\\s*ref)?(?:\\s*no\\.?)?)[\\s:.#-]*(\\d{9,16})")
  private static let upiRef = Rx("upi/(?:p2[ma]/)?(\\d{9,16})")
  private static let vpa = Rx("\\b([\\w.-]{2,}@[a-z]{2,})\\b")
  private static let cardBill = Rx("(payment|amount) of .{0,40}(received|credited) (towards|to|on|for) your .{0,30}credit card|credit card .{0,40}payment .{0,20}(received|credited)")

  private static let payeePatterns = [
    Rx("info[-:\\s]+(?:upi/(?:p2[ma]/)?\\d+/)?([a-z0-9][a-z0-9 .&'_-]{1,40}?)(?:/|\\s+not you|\\.\\s|\\.$|$)"), // Axis
    Rx("trf to\\s+([a-z0-9][a-z0-9 .&'_-]{1,40}?)\\s+(?:ref\\w*|on)\\b"),                                    // SBI
    Rx(";\\s*([a-z0-9][a-z0-9 .&'_-]{1,40}?)\\s+credited\\b"),                                             // ICICI
    Rx("\\btowards\\s+([a-z][a-z0-9 .&'_-]{1,40}?)\\s+(?:for|on|ref\\w*|umn|via|vide|dt|date)\\b"),             // BoB, UPI mandates
    Rx("\\bto[:\\s]+(?:vpa\\s+)?([a-z0-9][a-z0-9 .&'@_-]{1,40}?)\\s+(?:on|ref\\w*|via|upi|from|dt|date)\\b"), // HDFC, Kotak
    Rx("\\bat\\s+([a-z0-9][a-z0-9 .&'*_-]{1,40}?)(?:\\s+on\\b|\\s+avl|\\.\\s|,|\\.$|$)"),                   // card spends
    Rx("\\b(?:from|by)\\s+(?:(?:neft|imps|rtgs|upi|transfer)\\s+(?:from\\s+)?)?([a-z][a-z0-9 .&'_-]{1,40}?)(?:\\s+on\\b|\\s+ref\\w*|\\s+upi|\\.\\s|\\.$|$)"),     // income
  ]
  private static let companySuffix = Rx("\\s+(?:(?:pvt|private)\\.?\\s*)?(?:ltd|limited)\\.?$|\\s+(?:pvt|private)\\.?$")
  private static let junkPayee = Rx("^(upi|neft|imps|rtgs|your|a/c|acct|account|card|bank|vpa|you|the|net ?banking|atm|pos)\\b|^\\d+$|^[0-9a-f]{12,}$|\\d{8,}")

  static func amount(_ text: String) -> Int? {
    let ns = text as NSString
    for m in money.re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
      let start = max(0, m.range.location - 28)
      let before = ns.substring(with: NSRange(location: start, length: m.range.location - start))
      if notTheAmount.test(before) { continue }
      if let p = paise(ns.substring(with: m.range(at: 1))) { return p }
    }
    return bareAmount.first(text).flatMap { paise($0[1]) }
  }

  private static func paise(_ s: String) -> Int? {
    guard let d = Decimal(string: s.replacingOccurrences(of: ",", with: "")) else { return nil }
    var v = d * 100, r = Decimal()
    NSDecimalRound(&r, &v, 0, .plain)
    let p = NSDecimalNumber(decimal: r).intValue
    return p > 0 ? p : nil
  }

  static func payee(_ text: String) -> String? {
    for p in payeePatterns {
      guard let g = p.first(text) else { continue }
      let raw = g[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: ".-/"))
      if raw.count < 2 || junkPayee.test(raw) { continue }
      let name = raw.contains("@") ? String(raw.split(separator: "@")[0]) : raw
      let short = companySuffix.replace(name, with: "")
      return short.isEmpty ? name : short
    }
    // A VPA's name part, unless it's an ID (UPI mandate numbers look like 01a2079d…@yesg).
    guard let name = vpa.first(text).map({ String($0[1].split(separator: "@")[0]) }), !junkPayee.test(name) else { return nil }
    return name
  }

  /// Java's String.hashCode, so a key looks the same on both apps.
  private static func javaHash(_ s: String) -> UInt32 {
    var h: Int32 = 0
    for u in s.utf16 { h = h &* 31 &+ Int32(u) }
    return UInt32(bitPattern: h)
  }

  /// Stable id for this alert, so the same message is only ever added once.
  static func key(_ text: String, amount: Int) -> String {
    if let r = upiRef.first(text)?[1] ?? ref.first(text)?[1] { return "alert:\(r)" }
    let norm = Rx("[^a-z0-9]").replace(text.lowercased(), with: "")
    return "alert:\(amount):\(String(javaHash(norm), radix: 16))"
  }

  static func isBankAlert(_ text: String) -> Bool {
    !ignore.test(text) && (debit.test(text) || credit.test(text)) && amount(text) != nil
  }

  static func parse(_ a: PendingAlert, ctx: CaptureContext) -> CaptureDraft? {
    let text = Rx("\\s+").replace(a.text, with: " ").trimmingCharacters(in: .whitespaces)
    if ignore.test(text) { return nil }
    guard let amt = amount(text) else { return nil }
    let isDebit = debit.test(text)
    let isCredit = !isDebit && credit.test(text)
    let bill = cardBill.test(text)
    if !isDebit && !isCredit && !bill { return nil }

    let l4 = last4.all(text).map { $0[1] }
    let account = ctx.accounts.first { acc in
      guard let mine = acc.last4 else { return false }
      return l4.contains { mine.hasSuffix($0) || $0.hasSuffix(mine) }
    } ?? CaptureDrafts.findAccount("\(text) \(a.sender ?? "")", ctx.accounts)?.account

    var type: TxnType = isCredit ? .income : .expense
    var toAccountId: String?
    var fromId = account?.id ?? ctx.defaultAccountId ?? ctx.accounts.first?.id
    if bill {
      let cards = ctx.accounts.filter { $0.type == .card }
      if let card = (account?.type == .card ? account : nil) ?? (cards.count == 1 ? cards[0] : nil) {
        type = .transfer; toAccountId = card.id
        fromId = ctx.defaultAccountId.flatMap { $0 == card.id ? nil : $0 } ?? ctx.accounts.first { $0.type == .bank }?.id
      }
    }
    let name = payee(text)
    let brand = Brands.match(name) ?? Brands.match(text)
    let titled = name.map { Rx("\\b\\w", caseInsensitive: false).replace($0.lowercased()) { $0[0].uppercased() } }
    let payeeName = type == .transfer ? nil : brand?.name ?? titled.map(CaptureDrafts.displayName)
    return CaptureDraft(
      key: key(text, amount: amt), type: type, amount: amt, accountId: fromId, toAccountId: toAccountId,
      categoryId: type == .transfer ? nil : CaptureDrafts.guessCategory("\(text) \(name ?? "")", payee: payeeName, type: type, ctx: ctx),
      payee: payeeName, note: type == .transfer ? "Card bill payment" : nil, occurredAt: a.receivedAt,
      source: String(text.prefix(200)), include: true,
      warning: account == nil ? "Couldn’t tell which account. Check it." : nil)
  }
}

/// Bank messages waiting for review, kept in the App Group so the Shortcuts action can add to it without opening the app.
enum PendingAlerts {
  private static let key = "pendingAlerts"
  static func all() -> [PendingAlert] {
    guard let d = AppGroup.defaults.data(forKey: key) else { return [] }
    return (try? JSONDecoder().decode([PendingAlert].self, from: d)) ?? []
  }
  static func save(_ list: [PendingAlert]) {
    AppGroup.defaults.set(try? JSONEncoder().encode(Array(list.suffix(200))), forKey: key)
  }
  static func add(_ a: PendingAlert) {
    var list = all()
    guard !list.contains(where: { $0.text == a.text }) else { return }
    list.append(a); save(list)
  }
}

/// For a Shortcuts automation: Message › "When I get a message containing debited" › Log Bank Message (Message content).
struct LogBankMessageIntent: AppIntent {
  static let title: LocalizedStringResource = "Log Bank Message"
  static let description = IntentDescription("Reads a bank SMS or payment alert and keeps it in Paisa Pulse for you to confirm.")
  static let openAppWhenRun = false

  @Parameter(title: "Message") var message: String

  func perform() async throws -> some IntentResult & ProvidesDialog {
    guard BankAlerts.isBankAlert(message), let amt = BankAlerts.amount(message) else {
      return .result(dialog: "That doesn’t look like a payment.")
    }
    PendingAlerts.add(PendingAlert(text: message, sender: nil, receivedAt: .now))
    let who = BankAlerts.payee(message).map { " · \($0)" } ?? ""
    return .result(dialog: "Saved \(Money.format(amt))\(who) to review in Paisa Pulse.")
  }
}
