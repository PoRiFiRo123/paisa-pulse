import Foundation

/// Rupee formatting. Amounts are always shown without a minus sign: colour (and words like
/// "due") carry the direction.
enum Money {
  private static func formatter(fraction: Bool) -> NumberFormatter {
    let f = NumberFormatter()
    f.locale = Locale(identifier: "en_IN")
    f.numberStyle = .decimal
    f.minimumFractionDigits = fraction ? 2 : 0
    f.maximumFractionDigits = fraction ? 2 : 0
    return f
  }
  private static let whole = formatter(fraction: false)
  private static let withPaise = formatter(fraction: true)

  /// ₹1,23,456 or ₹1,23,456.50 (lakh/crore grouping). Never negative.
  static func format(_ paise: Int, hidden: Bool = false) -> String {
    if hidden { return "₹••••" }
    let p = abs(paise)
    let rupees = NSNumber(value: Double(p) / 100)
    let f = p % 100 == 0 ? whole : withPaise
    return "₹" + (f.string(from: rupees) ?? "\(p / 100)")
  }

  /// ₹950, ₹38K, ₹1.2L, ₹2.3Cr. Never negative.
  static func compact(_ paise: Int, hidden: Bool = false) -> String {
    if hidden { return "₹••" }
    let r = Double(abs(paise)) / 100
    func trim(_ v: Double) -> String {
      let s = String(format: v < 10 ? "%.1f" : "%.0f", v)
      return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }
    switch r {
    case 1_00_00_000...: return "₹" + trim(r / 1_00_00_000) + "Cr"
    case 1_00_000...: return "₹" + trim(r / 1_00_000) + "L"
    case 1_000...: return "₹" + trim(r / 1_000) + "K"
    default: return "₹" + trim(r)
    }
  }

  /// Keypad text → paise. "1,250.5" → 125050. nil when empty or invalid.
  static func parse(_ text: String) -> Int? {
    let cleaned = text.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "₹", with: "")
      .trimmingCharacters(in: .whitespaces)
    guard !cleaned.isEmpty, let d = Decimal(string: cleaned, locale: Locale(identifier: "en_US")) else { return nil }
    var v = d * 100
    var rounded = Decimal()
    NSDecimalRound(&rounded, &v, 0, .plain)
    let n = NSDecimalNumber(decimal: rounded).intValue
    return n > 0 ? n : nil
  }
}

/// Evaluates the Quick Add keypad's sums: "250+80×2" (left to right, × and ÷ first).
enum KeypadMath {
  static func evaluate(_ expr: String) -> Decimal? {
    var numbers: [Decimal] = []
    var ops: [Character] = []
    var current = ""
    for ch in expr {
      if "+−×÷-*/".contains(ch) {
        guard let n = Decimal(string: current, locale: Locale(identifier: "en_US")) else { return nil }
        numbers.append(n); current = ""
        ops.append(ch == "-" ? "−" : ch == "*" ? "×" : ch == "/" ? "÷" : ch)
      } else {
        current.append(ch)
      }
    }
    if current.isEmpty { // trailing operator: ignore it
      if !ops.isEmpty { ops.removeLast() }
    } else {
      guard let n = Decimal(string: current, locale: Locale(identifier: "en_US")) else { return nil }
      numbers.append(n)
    }
    guard !numbers.isEmpty, numbers.count == ops.count + 1 else { return nil }
    // × and ÷ first.
    var nums = [numbers[0]]
    var addOps: [Character] = []
    for (i, op) in ops.enumerated() {
      let rhs = numbers[i + 1]
      if op == "×" { nums[nums.count - 1] *= rhs }
      else if op == "÷" { if rhs == 0 { return nil }; nums[nums.count - 1] /= rhs }
      else { nums.append(rhs); addOps.append(op) }
    }
    var total = nums[0]
    for (i, op) in addOps.enumerated() { total = op == "+" ? total + nums[i + 1] : total - nums[i + 1] }
    return total
  }

  static func isExpression(_ s: String) -> Bool { s.dropFirst().contains(where: { "+−×÷".contains($0) }) }
}

extension Money {
  /// Rupees (Decimal) → paise, rounded to the nearest paisa. Negative and zero give 0.
  static func paise(from rupees: Decimal) -> Int {
    var v = rupees * 100
    var r = Decimal()
    NSDecimalRound(&r, &v, 0, .plain)
    return max(0, NSDecimalNumber(decimal: r).intValue)
  }
}
