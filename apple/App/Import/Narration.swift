import Foundation

/// What a bank narration says: channel, a clean payee, the UPI id and any remark. Same rules as Android Narration.kt.
struct Narration: Hashable {
  let channel: String
  let payee: String?
  let upiId: String?
  let note: String?
}

enum Narrations {
  private static let stop: Set<String> = [
    "upi", "p2m", "p2a", "dr", "cr", "neft", "imps", "rtgs", "ach", "nach", "pos", "ecom", "mob", "mb", "ib", "inb", "net",
    "to transfer", "by transfer", "transfer", "payment", "pay", "paid", "paid via", "sent using", "upi payment", "collect",
    "request", "purchase", "txn", "ref", "na", "null", "others", "other", "self", "fund transfer", "fund trf", "trf", "ft",
    "credit", "debit", "cash", "from", "to", "by", "via", "ok", "upiintent", "intent", "no remarks",
  ]
  private static let bankCode = Rx("^[a-z]{4}(0[a-z0-9]{6})?$")
  private static let banks = Rx("^(icic|hdfc|sbin|utib|barb|yesb|kkbk|punb|cnrb|ubin|idib|indb|idfb|pytm|airp|fdrl|bkid|ioba|maha|cbin|jaka|scbl|citi|hsbc|rbl|au|axis|icici|sbi|bob|kotak|paytm|ybl|ibl|axl|okaxis|oksbi|okhdfcbank|okicici|apl|jupiteraxis|fam)$")

  private static let categoryRules: [(Rx, String)] = [
    (Rx("salary|\\bsal\\b|payroll|wages"), "Salary"),
    (Rx("interest|int\\.?\\s?pd|int\\.?\\s?cr|\\bsb int"), "Interest"),
    (Rx("cashback|cash back"), "Cashback"),
    (Rx("refund|reversal|\\brev\\b|chargeback"), "Refund"),
    (Rx("swiggy|zomato|starbucks|mcdonald|domino|kfc|restaurant|cafe|hotel|dhaba|food|eatery|bakery|chai|pizza|biryani"), "Food & Dining"),
    (Rx("blinkit|zepto|bigbasket|instamart|dmart|grocery|kirana|supermarket|more retail|reliance fresh|nature'?s basket|milk|dairy"), "Groceries"),
    (Rx("hpcl|bpcl|indian oil|shell|petrol|fuel|filling station"), "Fuel"),
    (Rx("uber|\\bola\\b|rapido|metro|namma|bmtc|auto|cab|fastag|parking"), "Metro/Auto/Cab"),
    (Rx("bescom|tata power|adani electricity|msedcl|electricity|power|kseb|tneb|bses"), "Electricity"),
    (Rx("airtel|\\bjio\\b|\\bvi\\b|vodafone|act fibernet|broadband|recharge|postpaid|prepaid|hathway"), "Mobile/Internet"),
    (Rx("tata play|dish ?tv|d2h|sun direct|\\bdth\\b"), "DTH"),
    (Rx("\\brent\\b|nobroker|housing\\.com|landlord"), "Rent"),
    (Rx("\\bemi\\b|loan|bajaj fin|home credit|nach.*fin"), "EMI/Loans"),
    (Rx("netflix|spotify|prime|hotstar|youtube|apple|google play|subscription|jiocinema"), "Subscriptions"),
    (Rx("bookmyshow|pvr|inox|cinema|movie|steam|playstation"), "Entertainment"),
    (Rx("irctc|makemytrip|goibibo|indigo|air india|vistara|cleartrip|yatra|oyo|airbnb|redbus|flight|railway"), "Travel"),
    (Rx("apollo|pharm|1mg|practo|hospital|clinic|medical|diagnostic|lab\\b|dental"), "Health"),
    (Rx("zerodha|groww|sip|mutual fund|iccl|nse|bse|smallcase|kuvera|ppf|nps"), "Investments"),
    (Rx("\\blic\\b|insurance|policy"), "Bills & Utilities"),
    (Rx("amazon|flipkart|myntra|nykaa|ajio|meesho|decathlon|ikea|croma|reliance digital|mall|store|shop"), "Shopping"),
    (Rx("school|college|university|course|udemy|coursera|byju|unacademy|tuition|fees"), "Education"),
    (Rx("salon|spa|parlour|barber|urban company|cult\\.?fit|gym"), "Personal Care"),
    (Rx("donation|temple|charity|gift"), "Gifts & Donations"),
  ]
  private static let incomeOnly: Set<String> = ["Salary", "Interest", "Cashback", "Refund"]

  private static let cardPayment = Rx("credit card|cc payment|card payment|cc bill|card bill|autopay.*card|billdesk.*card|bbps.*card|cred club|\\bcred\\b|payment received|payment - thank|thank you for (your )?payment|bbps payment received")
  private static let atm = Rx("\\batm\\b|atm-wdl|atw-|nwd-|nfs/cash|cash wdl|cash withdrawal|cardless cash")
  private static let charges = Rx("charges?|chrgs|\\bgst\\b|annual fee|amc|sms alert|debit card fee|penalty|min bal|late fee|finance charge")
  private static let ws = Rx("\\s+")

  private static func titleCase(_ s: String) -> String {
    let t = Rx("\\b([a-z])", caseInsensitive: false).replace(s.lowercased()) { $0[0].uppercased() }
    return Rx("\\b(Upi|Neft|Imps|Atm|Emi|Lic|Llp)\\b", caseInsensitive: false).replace(t) { $0[0].uppercased() }
  }

  static func cleanPayee(_ raw: String) -> String {
    if let b = Brands.match(raw) { return b.name }
    var cleaned = Rx("\\b(private|pvt|limited|ltd|llp|india|p ltd|pvt ltd|co|inc)\\b\\.?").replace(raw, with: " ")
    cleaned = Rx("[^a-z0-9&'. ]").replace(cleaned, with: " ")
    cleaned = ws.replace(cleaned, with: " ").trimmingCharacters(in: .whitespaces)
    return titleCase(cleaned.isEmpty ? raw.trimmingCharacters(in: .whitespaces) : cleaned)
  }

  private static func isName(_ t: String) -> Bool {
    let s = t.trimmingCharacters(in: .whitespaces)
    return s.count >= 3 && Rx("[a-z]").test(s) && !s.contains("@") && !stop.contains(s.lowercased()) && !bankCode.test(s) &&
      !banks.test(s) && !Rx("^[a-z]{0,4}\\d{5,}$").test(s) && !Rx("^x+\\d+$").test(s) && !Rx("^\\d").test(s) &&
      !Rx("^(neft|imps|rtgs|ach|nach|ecs|upi|mmt|bil|onl|trf|pos)\\b").test(s) &&
      !Rx("^(payment|paid|pay|sent|collect|received|transfer)\\b").test(s)
  }

  static func parse(_ text: String) -> Narration {
    let raw = ws.replace(text, with: " ").trimmingCharacters(in: .whitespaces)
    let tokens = Rx("[/|\\\\]|(?<=\\S)-(?=\\S)|\\s-\\s|:").split(raw).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    let upiId = Rx("[a-z0-9._-]+@[a-z]{2,}").first(raw)?[0]
    let channel: String
    if cardPayment.test(raw) { channel = "CARD_PAYMENT" }
    else if Rx("\\bupi\\b").test(raw) || upiId != nil { channel = "UPI" }
    else if atm.test(raw) { channel = "ATM" }
    else if Rx("\\bneft\\b").test(raw) { channel = "NEFT" }
    else if Rx("\\bimps\\b|mmt/imps").test(raw) { channel = "IMPS" }
    else if Rx("\\brtgs\\b").test(raw) { channel = "RTGS" }
    else if Rx("\\b(nach|ach|ecs)\\b").test(raw) { channel = "NACH" }
    else if Rx("^pos\\b|\\bpos\\s|ecom|card txn|\\bvps\\b|\\bvin\\b").test(raw) { channel = "POS" }
    else if Rx("interest|int\\.?\\s?pd|int\\.?\\s?cr").test(raw) { channel = "INTEREST" }
    else if Rx("refund|reversal|\\brev\\b").test(raw) { channel = "REFUND" }
    else if charges.test(raw) { channel = "CHARGES" }
    else { channel = "OTHER" }
    let fixed = ["ATM": "ATM withdrawal", "INTEREST": "Interest", "CHARGES": "Bank charges", "CARD_PAYMENT": "Credit card payment"]
    if let f = fixed[channel] { return Narration(channel: channel, payee: f, upiId: upiId, note: nil) }
    let brand = Brands.match(raw)?.name
    var payee: String?
    var note: String?
    switch channel {
    case "UPI":
      let at = tokens.firstIndex { $0.contains("@") }
      let before = (at ?? 0) > 0 ? tokens[..<at!].reversed().first(where: isName) : nil
      let names = tokens.filter(isName)
      let longest = names.enumerated().max { a, b in a.element.count != b.element.count ? a.element.count < b.element.count : a.offset > b.offset }?.element
      payee = brand ?? before ?? longest ?? upiId.map { Rx("[._-]?\\d+$").replace(String($0.split(separator: "@")[0]), with: "") }
      let after = at.map { tokens[($0 + 1)...].filter { isName($0) && !banks.test(Rx("\\s*bank$").replace($0, with: "")) } } ?? []
      note = after.isEmpty ? nil : after.joined(separator: " ")
    case "POS":
      let m = Rx("(?:pos|ecom|vps|vin)[\\s/]*(?:[x\\d*]{6,}\\s*)?(.+)$").first(raw)
      payee = brand ?? m.map { String($0[1].split(separator: "/", omittingEmptySubsequences: false).first ?? "") } ?? tokens.first(where: isName)
    default:
      let names = tokens.filter(isName)
      payee = brand ?? names.first
      note = names.count > 1 ? names.dropFirst().joined(separator: " ") : nil
    }
    let clean = payee.map(cleanPayee) ?? (raw.isEmpty ? nil : cleanPayee(String(raw.prefix(40))))
    return Narration(channel: channel, payee: clean, upiId: upiId, note: note)
  }

  static func suggestCategory(_ narration: String, payee: String?, out: Bool) -> String? {
    let text = "\(payee ?? "") \(narration)"
    for (re, name) in categoryRules where re.test(text) {
      if incomeOnly.contains(name) == !out { return name }
    }
    return nil
  }
}
