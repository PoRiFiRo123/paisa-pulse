import Foundation

/// Reads card details out of scanned text. Keeps only what the app stores: network, last 4, expiry,
/// name. The full number is used once to check it and then dropped. Mirrors CardNumber.kt.
enum CardNumber {
  struct Scan: Equatable { var network: String; var last4: String; var month: Int?; var year: Int?; var name: String? }

  static func luhn(_ digits: String) -> Bool {
    var sum = 0
    for (i, ch) in digits.reversed().enumerated() {
      guard var d = ch.wholeNumberValue else { return false }
      if i % 2 == 1 { d *= 2; if d > 9 { d -= 9 } }
      sum += d
    }
    return sum % 10 == 0
  }

  /// Network from the first digits (BIN). In India 60/65/81/82/508 are RuPay.
  static func network(_ digits: String) -> String {
    func p(_ n: Int) -> Int { Int(digits.prefix(n)) ?? -1 }
    if digits.hasPrefix("4") { return "visa" }
    if digits.hasPrefix("34") || digits.hasPrefix("37") { return "amex" }
    if (51...55).contains(p(2)) || (2221...2720).contains(p(4)) { return "mastercard" }
    if [60, 65, 81, 82].contains(p(2)) || p(3) == 508 || p(3) == 353 || p(3) == 356 { return "rupay" }
    if digits.hasPrefix("36") || digits.hasPrefix("38") || (300...305).contains(p(3)) { return "diners" }
    if digits.hasPrefix("6011") || (644...649).contains(p(3)) { return "discover" }
    return "other"
  }

  static func networkName(_ n: String) -> String {
    switch n {
    case "visa": "Visa"
    case "mastercard": "Mastercard"
    case "rupay": "RuPay"
    case "amex": "Amex"
    case "diners": "Diners"
    case "discover": "Discover"
    default: "Card"
    }
  }

  /// Words printed on cards that are never the cardholder's name.
  static let cardWords = ["BANK", "CARD", "DEBIT", "CREDIT", "VALID", "THRU", "FROM", "PLATINUM", "SIGNATURE", "CLASSIC", "GOLD",
                          "WORLD", "SELECT", "INFINITE", "RUPAY", "VISA", "MASTERCARD", "AMEX", "INTERNATIONAL", "ELECTRONIC", "ONLY",
                          "MEMBER", "SINCE", "BUSINESS", "PREPAID", "CONTACTLESS"]

  static let networks = ["visa", "mastercard", "rupay", "amex", "diners", "discover", "other"]

  /// Text lines from the camera → card details, or nil until a valid number is seen.
  static func parse(_ lines: [String]) -> Scan? {
    var found: String?
    for line in lines {
      let digits = line.filter(\.isNumber)
      let groups = line.split(whereSeparator: { $0 == " " || $0 == "-" })
      // A card number is printed in groups of 4 (or 4-6-5 for Amex); avoid phone numbers and dates.
      if (13...19).contains(digits.count), groups.count >= 3 || digits.count == line.filter({ !$0.isWhitespace }).count, luhn(digits) {
        found = digits; break
      }
    }
    if found == nil {
      let all = lines.joined(separator: " ").filter(\.isNumber)
      for len in [16, 15, 19, 14, 13] where all.count >= len {
        for start in 0...(all.count - len) {
          let s = String(Array(all)[start..<(start + len)])
          if luhn(s), network(s) != "other" { found = s; break }
        }
        if found != nil { break }
      }
    }
    guard let number = found else { return nil }
    var month: Int?, year: Int?
    let text = lines.joined(separator: " ")
    if let r = text.range(of: #"(0[1-9]|1[0-2])\s?/\s?(\d{2,4})"#, options: .regularExpression) {
      let parts = text[r].replacingOccurrences(of: " ", with: "").split(separator: "/")
      month = Int(parts[0]); if let y = Int(parts[1]) { year = y < 100 ? 2000 + y : y }
    }
    let name = lines.first { l in
      let t = l.trimmingCharacters(in: .whitespaces)
      return t.count >= 5 && t.count <= 26 && t == t.uppercased() && t.allSatisfy { $0.isLetter || $0 == " " || $0 == "." }
        && !cardWords.contains { t.contains($0) }
    }?.trimmingCharacters(in: .whitespaces)
    return Scan(network: network(number), last4: String(number.suffix(4)), month: month, year: year, name: name)
  }
}

/// Foreign currency: rates from open.er-api.com (only currency codes are requested), cached 12 hours,
/// used offline from the cache, or a rate you type. Mirrors Currency.kt.
enum Currency {
  static let common: [(code: String, name: String, symbol: String)] = [
    ("INR", "Indian Rupee", "₹"), ("USD", "US Dollar", "$"), ("EUR", "Euro", "€"), ("GBP", "British Pound", "£"),
    ("AED", "UAE Dirham", "AED"), ("SGD", "Singapore Dollar", "S$"), ("JPY", "Japanese Yen", "¥"), ("AUD", "Australian Dollar", "A$"),
    ("CAD", "Canadian Dollar", "C$"), ("CHF", "Swiss Franc", "CHF"), ("THB", "Thai Baht", "฿"), ("MYR", "Malaysian Ringgit", "RM"),
    ("SAR", "Saudi Riyal", "SAR"), ("CNY", "Chinese Yuan", "CN¥"), ("HKD", "Hong Kong Dollar", "HK$"), ("NZD", "NZ Dollar", "NZ$"),
    ("LKR", "Sri Lankan Rupee", "Rs"), ("NPR", "Nepalese Rupee", "Rs"), ("BDT", "Bangladeshi Taka", "৳"), ("IDR", "Indonesian Rupiah", "Rp"),
  ]
  static func symbol(_ code: String) -> String { common.first { $0.code == code }?.symbol ?? World.symbol(code) }

  struct Rates: Codable { var at: Double; var inrPer: [String: Double] }
  private static let key = "fx.rates"
  static let maxAge: Double = 12 * 3600

  static var cached: Rates? {
    guard let d = AppGroup.defaults.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(Rates.self, from: d)
  }

  /// Rupees per 1 unit of each currency. Refreshes when older than 12 h; falls back to the cache offline.
  static func rates(force: Bool = false) async -> Rates? {
    if !force, let c = cached, Date.now.timeIntervalSince1970 - c.at < maxAge { return c }
    guard let url = URL(string: "https://open.er-api.com/v6/latest/INR"),
          let (data, _) = try? await URLSession.shared.data(from: url),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let perInr = obj["rates"] as? [String: Double] else { return cached }
    var inrPer: [String: Double] = [:]
    for (k, v) in perInr where v > 0 { inrPer[k] = 1 / v }
    let r = Rates(at: Date.now.timeIntervalSince1970, inrPer: inrPer)
    if let d = try? JSONEncoder().encode(r) { AppGroup.defaults.set(d, forKey: key) }
    return r
  }

  /// Foreign minor units (×100) at `rate` rupees per unit → INR paise.
  static func toPaise(_ minor: Int, rate: Double) -> Int { Int((Double(minor) * rate).rounded()) }
}
