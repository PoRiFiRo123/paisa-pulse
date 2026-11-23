import SwiftUI

extension Color {
  init(hex: String) {
    var v: UInt64 = 0
    Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
    self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
  }

  static func dynamic(light: String, dark: String) -> Color {
    #if canImport(UIKit)
    Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light)) })
    #else
    Color(hex: light)
    #endif
  }

  /// Expenses: a soft red (no minus signs anywhere; colour carries the direction).
  static let expense = Color.dynamic(light: "#E5484D", dark: "#FF6B6B")
  /// Income: green.
  static let income = Color.dynamic(light: "#1E9E5A", dark: "#30D158")
  static let transfer = Color.secondary
}

enum Palette {
  static let colors = [
    "#FF3B30", "#FF9500", "#FFB800", "#34C759", "#30B0C7", "#32ADE6", "#007AFF",
    "#5E5CE6", "#5856D6", "#AF52DE", "#FF2D55", "#A2845E", "#8E8E93", "#1E9E5A",
  ]
  static let accents: [(key: String, name: String, light: String, dark: String)] = [
    ("indigo", "Indigo", "#5E5CE6", "#7D7AFF"), ("blue", "Blue", "#007AFF", "#0A84FF"),
    ("purple", "Purple", "#AF52DE", "#BF5AF2"), ("pink", "Pink", "#FF2D55", "#FF375F"),
    ("orange", "Orange", "#FF9500", "#FF9F0A"), ("green", "Green", "#34C759", "#30D158"),
    ("teal", "Teal", "#30B0C7", "#40C8E0"),
  ]
  static func accent(_ key: String) -> Color {
    // "custom": your own colour from the colour wheel (Settings › Accent colour).
    if key == "custom", let hex = AppGroup.defaults.string(forKey: PrefKey.customAccent) { return Color(hex: hex) }
    let a = accents.first(where: { $0.key == key }) ?? accents[0]
    return Color.dynamic(light: a.light, dark: a.dark)
  }
}

extension TxnType {
  var color: Color {
    switch self {
    case .expense: .expense
    case .income: .income
    case .transfer: .transfer
    }
  }
}
