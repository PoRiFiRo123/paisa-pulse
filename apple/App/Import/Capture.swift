import Foundation
import Vision

// Screenshot capture, the same rules as Android Capture.kt (checked against the RN app's output).

/// A transaction read from a screenshot, waiting for the user to confirm it.
struct CaptureDraft: Identifiable, Hashable {
  var id: String { key }
  let key: String
  var type: TxnType
  var amount: Int
  var accountId: String?
  var toAccountId: String?
  var categoryId: String?
  var payee: String?
  var note: String?
  var occurredAt: Date
  let source: String
  var include: Bool
  var warning: String?
}

struct CaptureAccount { let id, name: String; let type: AccountType; let institution, last4: String? }
struct CaptureCategory { let id, name: String; let kind: CategoryKind; let parentId: String? }
struct CaptureContext {
  var accounts: [CaptureAccount]
  var categories: [CaptureCategory]
  var learned: [String: String] = [:]
  var defaultAccountId: String?
  var now: Date = .now
}

enum CaptureDrafts {
  private static let generic: Set<String> = ["bank", "card", "credit", "debit", "account", "acct", "savings", "saving", "current", "salary", "my", "the", "of", "ac", "a/c"]

  private static func phrases(_ a: CaptureAccount) -> [String] {
    var p: [String] = []
    func add(_ s: String) { if !p.contains(s) { p.append(s) } }
    let name = a.name.lowercased().trimmingCharacters(in: .whitespaces)
    add(name)
    for w in name.split(whereSeparator: \.isWhitespace).map(String.init) where w.count >= 3 && !generic.contains(w) { add(w) }
    if let inst = a.institution?.lowercased() {
      add(inst)
      for w in inst.split(whereSeparator: \.isWhitespace).map(String.init) where w.count >= 3 && !generic.contains(w) { add(w) }
    }
    let both = "\(name) \(a.institution ?? "")".lowercased()
    if Rx("baroda|\\bbob\\b").test(both) { ["bob", "baroda", "bank of baroda"].forEach(add) }
    if Rx("\\bsbi\\b|state bank").test(both) { ["sbi", "state bank"].forEach(add) }
    if let l4 = a.last4 { add(l4) }
    // Longest first; stable for equal lengths (like the JS sort).
    return p.enumerated().sorted { ($1.element.count, $0.offset) < ($0.element.count, $1.offset) }.map(\.element)
  }

  private static let prep = "(?:(?:from|on|using|with|via|by|through|in|thru|frm)\\s+)?(?:(?:my|the)\\s+)?"
  private static let tail = "(?:\\s+(?:bank|account|acct|a/c|card|credit card|debit card|wallet))?"

  static func findAccount(_ text: String, _ accounts: [CaptureAccount]) -> (account: CaptureAccount, phrase: String)? {
    let lower = text.lowercased()
    var best: (CaptureAccount, String, Int)?
    for a in accounts {
      for p in phrases(a) {
        if let m = Rx("(?:^|\\s)(\(prep)\(NSRegularExpression.escapedPattern(for: p))\(tail))(?=$|[\\s,.;!?])", caseInsensitive: false).first(lower),
           best == nil || p.count > best!.2 {
          best = (a, m[1], p.count)
        }
      }
    }
    if let best { return (best.0, best.1) }
    let byType: [(String, AccountType)] = [("(?:^|\\s)(\(prep)cash)(?=$|[\\s,.;!?])", .cash), ("(?:^|\\s)(\(prep)(?:credit\\s+)?card)(?=$|[\\s,.;!?])", .card),
                                           ("(?:^|\\s)(\(prep)wallet)(?=$|[\\s,.;!?])", .wallet)]
    for (pattern, type) in byType {
      let ofType = accounts.filter { $0.type == type }
      if let m = Rx(pattern, caseInsensitive: false).first(lower), ofType.count == 1 { return (ofType[0], m[1]) }
    }
    return nil
  }

  private static let spoken: [(Rx, String)] = [
    (Rx("\\b(lunch|dinner|breakfast|brunch|snacks?|chai|tea|coffee|juice|food|meal|biryani|pizza|burger|dosa|idli|samosa|momos?|restaurant|cafe|canteen|tiffin|swiggy|zomato)\\b"), "Food & Dining"),
    (Rx("\\b(groceries|grocery|vegetables?|veggies|sabzi|fruits?|milk|eggs|bread|atta|rice|dal|kirana|ration)\\b"), "Groceries"),
    (Rx("\\b(petrol|diesel|fuel|cng)\\b"), "Fuel"),
    (Rx("\\b(auto|rickshaw|cab|taxi|uber|ola|rapido|metro|bus|train ticket|local train|toll|parking|fastag)\\b"), "Metro/Auto/Cab"),
    (Rx("\\b(rent)\\b"), "Rent"),
    (Rx("\\b(electricity|power bill|light bill)\\b"), "Electricity"),
    (Rx("\\b(recharge|mobile bill|phone bill|wifi|internet|broadband)\\b"), "Mobile/Internet"),
    (Rx("\\b(medicines?|medical|doctor|pharmacy|hospital|clinic|tablets?|chemist)\\b"), "Health"),
    (Rx("\\b(movie|movies|cinema|concert|game|netflix)\\b"), "Entertainment"),
    (Rx("\\b(clothes|shirt|shoes|jeans|dress|kurta|shopping|amazon|flipkart|myntra)\\b"), "Shopping"),
    (Rx("\\b(flight|hotel|trip|travel|holiday)\\b"), "Travel"),
    (Rx("\\b(haircut|salon|spa|gym|parlour)\\b"), "Personal Care"),
    (Rx("\\b(gift|donation|temple|church|mosque|gurudwara)\\b"), "Gifts & Donations"),
    (Rx("\\b(fees|tuition|books?|course)\\b"), "Education"),
    (Rx("\\b(salary|paycheck)\\b"), "Salary"),
    (Rx("\\b(freelance|client|invoice)\\b"), "Freelance"),
    (Rx("\\b(refund|returned)\\b"), "Refund"),
    (Rx("\\b(cashback)\\b"), "Cashback"),
    (Rx("\\b(interest)\\b"), "Interest"),
  ]

  static func guessCategory(_ text: String, payee: String?, type: TxnType, ctx: CaptureContext) -> String? {
    if type == .transfer { return nil }
    let kind: CategoryKind = type == .income ? .income : .expense
    let ofKind = ctx.categories.filter { $0.kind == kind }
    if let p = payee, let id = ctx.learned[p.lowercased()], ofKind.contains(where: { $0.id == id }) { return id }
    func byName(_ n: String) -> String? { ofKind.first { $0.name.lowercased() == n.lowercased() }?.id }
    let hay = "\(payee ?? "") \(text)"
    for c in ofKind where c.name.count >= 3 && Rx("\\b\(NSRegularExpression.escapedPattern(for: c.name.lowercased()))\\b", caseInsensitive: false).test(hay.lowercased()) {
      return c.id
    }
    for (re, n) in spoken where re.test(hay) { if let id = byName(n) { return id } }
    return Narrations.suggestCategory(text, payee: payee, out: kind != .income).flatMap(byName)
  }

  static func displayName(_ text: String) -> String {
    if let b = Brands.match(text) { return b.name }
    let t = text.trimmingCharacters(in: .whitespaces)
    return t.isEmpty ? t : t.prefix(1).uppercased() + t.dropFirst()
  }

  @MainActor static func context(accounts: [Account], categories: [Category], txns: [Txn], defaultAccountId: String?, now: Date = .now) -> CaptureContext {
    var counts: [String: [String: Int]] = [:]
    for t in txns where t.deletedAt == nil { if let p = t.payee?.lowercased(), let c = t.categoryId { counts[p, default: [:]][c, default: 0] += 1 } }
    let learned = counts.mapValues { byCat in byCat.max { a, b in a.value < b.value }!.key }
    return CaptureContext(
      accounts: accounts.filter { $0.archivedAt == nil }.sorted { $0.sortOrder < $1.sortOrder }
        .map { CaptureAccount(id: $0.id, name: $0.name, type: $0.type, institution: $0.institution, last4: $0.last4) },
      categories: categories.filter { $0.archivedAt == nil }.map { CaptureCategory(id: $0.id, name: $0.name, kind: $0.kind, parentId: $0.parentId) },
      learned: learned, defaultAccountId: defaultAccountId, now: now)
  }
}

enum ScreenshotParser {
  private static let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6, "jul": 7, "aug": 8, "sep": 9, "sept": 9, "oct": 10, "nov": 11, "dec": 12]

  static func toLines(_ texts: [String]) -> [String] {
    texts.flatMap { Rx("\\r?\\n").split($0) }
      .map { Rx("\\s+").replace($0, with: " ").trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }

  private static let idLine = Rx("\\b(utr|upi ref|ref(erence)?\\s*(no|number|id)?|transaction id|txn id|order id|google transaction|upi transaction|rrn)\\b")
  /// Lines with other amounts: balances, rewards, fees and limits (Paytm, PhonePe, bank apps).
  private static let otherAmount = Rx("\\b(balance|bal\\b|cashback|reward|coins?|scratch|won|offer|fee|charges?|limit|points?|save|saved|discount)\\b")

  private static func paise(_ s: String) -> Int? {
    guard let d = Decimal(string: s.replacingOccurrences(of: ",", with: "")) else { return nil }
    var v = d * 100, r = Decimal()
    NSDecimalRound(&r, &v, 0, .plain)
    let p = NSDecimalNumber(decimal: r).intValue
    return p > 0 ? p : nil
  }

  static func findPaidAmount(_ lines: [String]) -> Int? {
    let money = Rx("(?:₹|rs\\.?|inr|amount\\s*(?:paid|sent|received)?\\s*:?\\s*₹?)\\s*([\\d,]+(?:\\.\\d{1,2})?)\\b")
    for line in lines where !idLine.test(line) && !otherAmount.test(line) {
      if let m = money.first(line), let p = paise(m[1]) { return p }
    }
    // OCR often reads the ₹ sign as Z, %, ? or 2 on a line of its own amount ("Z349", "% 1,245.00").
    for line in lines { if let m = Rx("^[z%?]\\s?(\\d[\\d,]*(?:\\.\\d{1,2})?)$").first(line), let p = paise(m[1]) { return p } }
    for line in lines {
      guard let m = Rx("^([\\d,]{1,9}(?:\\.\\d{2})?)$").first(line) else { continue }
      if !Rx("^\\d{10,}$").test(m[1].replacingOccurrences(of: ",", with: "")), let p = paise(m[1]) { return p }
    }
    return nil
  }

  static func findReceiptDate(_ lines: [String], now: Date, calendar: Calendar = .current) -> Date? {
    let text = lines.joined(separator: " \n ")
    var day: Int?, month: Int?, year: Int?
    if let a = Rx("\\b(\\d{1,2})(?:st|nd|rd|th)?[\\s-]+(jan|feb|mar|apr|may|jun|jul|aug|sept?|oct|nov|dec)[a-z]*[\\s,-]*(\\d{4})?").first(text) {
      day = Int(a[1]); month = months[a[2].lowercased()]; year = Int(a[3])
    } else if let b = Rx("\\b(jan|feb|mar|apr|may|jun|jul|aug|sept?|oct|nov|dec)[a-z]*\\s+(\\d{1,2}),?\\s*(\\d{4})?").first(text) {
      month = months[b[1].lowercased()]; day = Int(b[2]); year = Int(b[3])
    } else if let c = Rx("\\b(\\d{1,2})[/.-](\\d{1,2})[/.-](\\d{2,4})\\b").first(text) {
      day = Int(c[1]); month = Int(c[2]); let y = Int(c[3]) ?? 0; year = y < 100 ? 2000 + y : y
    }
    // "Today, 10:15 AM" / "Yesterday 9:02 pm" (Paytm, PhonePe, Navi, bank apps).
    if day == nil, let r = Rx("\\b(today|yesterday)\\b").first(text),
       let base = calendar.date(byAdding: .day, value: r[1].lowercased() == "yesterday" ? -1 : 0, to: now) {
      let c = calendar.dateComponents([.year, .month, .day], from: base)
      day = c.day; month = c.month; year = c.year
    }
    guard let d = day, let m = month else { return nil }
    var hours = 12, minutes = 0
    if let t = Rx("\\b(\\d{1,2}):(\\d{2})(?::\\d{2})?\\s*(am|pm)?\\b").first(text) {
      hours = (Int(t[1]) ?? 12) % 24; minutes = Int(t[2]) ?? 0
      let ap = t[3].lowercased()
      if ap == "pm" && hours < 12 { hours += 12 }
      if ap == "am" && hours == 12 { hours = 0 }
    }
    let thisYear = calendar.component(.year, from: now)
    func at(_ y: Int) -> Date? {
      guard let date = calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hours, minute: minutes)),
            calendar.component(.day, from: date) == d else { return nil }
      return date
    }
    guard var result = at(year ?? thisYear) else { return nil }
    if year == nil && result > now.addingTimeInterval(86_400) { result = at(thisYear - 1) ?? result }
    return result
  }

  private static let received = Rx("\\b(received from|money received|you received|credited to your|received)\\b")
  private static let sent = Rx("\\b(paid to|paid successfully|payment successful|payment success|money sent|sent to|debited from|you paid|transaction successful|completed|payment of|payment to|sent successfully|transfer successful|transferred|paid|debited|payment done|payment complete|success)\\b")
  private static let failed = Rx("\\b(failed|declined|unsuccessful|pending|processing|reversed|cancelled|canceled|in progress|awaiting|will be refunded)\\b")
  private static let payeeLabel = Rx("^(paid to|paid successfully to|money sent to|sent to|sent money to|payment to|transferred to|received from|payment from|money received from|sender( name)?|to|from|beneficiary( name)?|payee( name)?|merchant( name)?|recipient( name)?|receiver( name)?|to account|paying)\\s*:?$")
  private static let notAName = Rx("(@|\\d{6,}|successful|completed|transaction|upi|banking name|share|split|pay again|view|details|debited|credited|xx|\\*\\*|•|powered by|phonepe|google pay|\\bgpay\\b|paytm|\\bbhim\\b|whatsapp|mobikwik|freecharge|super\\.money|receipt|download|help|support|again|\\?)")
  private static let letter = Rx("[a-z]")

  private static func payeeFrom(_ lines: [String], received: Bool) -> (name: String?, upi: String?) {
    let upi = lines.lazy.compactMap { Rx("\\b[\\w.-]{2,}@[a-z]{2,}\\b").first($0)?[0] }.first
    let want = received ? Rx("^(received from|from|money received from|payment from|sender)\\b") : Rx("^(paid to|paid successfully to|money sent to|sent to|sent money to|payment to|transferred to|to|beneficiary|payee|merchant|recipient|receiver|paying)\\b")
    for (i, line) in lines.enumerated() {
      if payeeLabel.test(line) && want.test(line) {
        if let next = lines.dropFirst(i + 1).prefix(2).first(where: { !notAName.test($0) && letter.test($0) && !$0.hasPrefix("₹") }) { return (next, upi) }
        continue
      }
      let inline = (received ? Rx("^(?:received from|money received from|payment from|from|sender name)\\s*:?\\s+(.+)$") : Rx("^(?:paid to|paid successfully to|money sent to|sent to|sent money to|payment to|transferred to|paying|to|beneficiary name|payee name|recipient name|merchant name)\\s*:?\\s+(.+)$")).first(line)
      if let inline, !notAName.test(inline[1]), letter.test(inline[1]) {
        return (Rx("\\s*\\(.*\\)\\s*$").replace(inline[1], with: ""), upi)
      }
    }
    if !received {
      // "Nishit Kirani paid" / "You paid" on one line, the payee on the next (CRED receipts).
      for (i, line) in lines.enumerated() where Rx("\\bpaid$").test(line) {
        if let next = lines.dropFirst(i + 1).prefix(2).first(where: nameLike) { return (next, upi) }
      }
      // No label at all: the name just above the amount (CRED, bank apps).
      if let at = lines.firstIndex(where: { amountLine.test($0) }), at > 0,
         let name = lines[max(0, at - 3)..<at].reversed().first(where: nameLike) { return (name, upi) }
    }
    return (nil, upi)
  }

  private static let amountLine = Rx("^(?:₹|rs\\.?|inr|[z%?])?\\s?\\d[\\d,]*(?:\\.\\d{1,2})?$")
  private static func nameLike(_ s: String) -> Bool {
    Rx("^[a-z][a-z .'&-]{2,40}$").test(s) && !notAName.test(s) && !payeeLabel.test(s) &&
      !Rx("\\b(today|yesterday|payment|paid|bank|account|balance|amount|status|cred)\\b").test(s)
  }

  private static func accountFrom(_ lines: [String], _ ctx: CaptureContext) -> CaptureAccount? {
    let own = lines.filter { Rx("(debited|credited|from|account|a/c|bank|xx|\\*{2,}|•{2,})").test($0) }
    for line in own {
      if let l4 = Rx("(?:x{2,}|\\*{2,}|•{2,}|\\.{2,}|a/c\\s*(?:no\\.?)?\\s*|ending\\s*(?:in|with)?\\s*)\\s*(\\d{4})\\b").first(line)?[1], let hit = ctx.accounts.first(where: { $0.last4 == l4 }) { return hit }
    }
    for line in own { if let hit = CaptureDrafts.findAccount(line, ctx.accounts) { return hit.account } }
    return nil
  }

  /// One payment screenshot → a draft, or nil with no amount. Tested with GPay, PhonePe, Paytm, BHIM, CRED, Amazon Pay,
  /// WhatsApp, Navi, super.money, MobiKwik, Freecharge, Fi/Jupiter-style and bank apps (Axis, BoB, SBI YONO, HDFC, ICICI).
  static func parse(_ texts: [String], ctx: CaptureContext, key: String = "shot") -> CaptureDraft? {
    let lines = toLines(texts)
    guard let amount = findPaidAmount(lines) else { return nil }
    let text = lines.joined(separator: "\n")
    let isReceived = received.test(text) && !Rx("\\bpaid to\\b|\\bdebited from\\b").test(text)
    let (name, upi) = payeeFrom(lines, received: isReceived)
    let account = accountFrom(lines, ctx)
    let brand = Brands.match(name) ?? Brands.match(upi)
    let titled = name.map { Rx("\\b\\w", caseInsensitive: false).replace($0.lowercased()) { $0[0].uppercased() } }
    let payee = brand?.name ?? titled.map(CaptureDrafts.displayName) ?? upi.map { String($0.split(separator: "@")[0]) }
    var type: TxnType = isReceived ? .income : .expense
    var toAccountId: String?
    var accountId = account?.id ?? ctx.defaultAccountId ?? ctx.accounts.first?.id
    if !isReceived && Rx("credit card|card bill|cc bill|card payment").test(text) {
      let cards = ctx.accounts.filter { $0.type == .card }
      let last4s = Set(Rx("(\\d{4})\\b").all(text).map { $0[1] })
      if let card = cards.first(where: { $0.last4.map(last4s.contains) ?? false }) ?? (cards.count == 1 ? cards[0] : nil) {
        type = .transfer; toAccountId = card.id
        if accountId == card.id { accountId = ctx.accounts.first { $0.type == .bank }?.id }
      }
    }
    let isFailed = failed.test(text) && !Rx("\\bsuccess").test(text)
    let warning: String? = !(sent.test(text) || isReceived) ? "Couldn’t tell if this was a payment. Check the details."
      : isFailed ? "This payment may have failed or be pending." : nil
    return CaptureDraft(key: key, type: type, amount: amount, accountId: accountId, toAccountId: toAccountId,
                        categoryId: CaptureDrafts.guessCategory("\(name ?? "") \(upi ?? "")", payee: payee, type: type, ctx: ctx),
                        payee: type == .transfer ? nil : payee, note: type == .transfer ? "Card bill payment" : nil,
                        occurredAt: findReceiptDate(lines, now: ctx.now) ?? ctx.now, source: lines.prefix(12).joined(separator: " · "),
                        include: !isFailed, warning: warning)
  }
}

/// On-device text recognition (Vision) for payment screenshots: the app's capture screen and the share extension.
enum ScreenText {
  static func read(_ image: CGImage) async -> [String] {
    await Task.detached(priority: .userInitiated) {
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = false
      // Only languages Vision supports: an unsupported one ("en-IN") makes the request fail and read nothing.
      let supported = (try? request.supportedRecognitionLanguages()) ?? ["en-US"]
      request.recognitionLanguages = ["en-GB", "en-US"].filter { supported.contains($0) }
      if request.recognitionLanguages.isEmpty { request.recognitionLanguages = ["en-US"] }
      do { try VNImageRequestHandler(cgImage: downscaled(image), options: [:]).perform([request]) } catch { return [] }
      return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }.value
  }

  /// Screenshots are up to ~3000 px tall; 2000 px reads just as well and keeps the share extension within its memory limit.
  static func downscaled(_ image: CGImage, maxSide: Int = 2000) -> CGImage {
    let side = max(image.width, image.height)
    guard side > maxSide else { return image }
    let scale = Double(maxSide) / Double(side)
    let w = Int(Double(image.width) * scale), h = Int(Double(image.height) * scale)
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return image }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage() ?? image
  }
}
