import Foundation
import SwiftUI

/// Mirrors `WidgetSnapshot` in src/features/widgets/snapshot.ts. The app writes it as JSON
/// into the shared App Group; every value is pre-formatted (₹, lakh/crore, privacy mask).
struct Snapshot: Codable {
  struct Budget: Codable {
    let label: String
    let ratio: Double
    let over: Bool
  }
  struct Category: Codable, Identifiable {
    let name: String
    let amount: String
    let color: String
    let icon: String
    var id: String { name }
  }

  let version: Int
  let month: String
  let spent: String
  let spentCompact: String
  let today: String
  let income: String
  let budget: Budget?
  let top: [Category]
  let hidden: Bool
  let updatedAt: Double

  static let appGroup = "group.com.paisapulse.app"

  static func load() -> Snapshot? {
    guard
      let json = UserDefaults(suiteName: appGroup)?.string(forKey: "snapshot"),
      let data = json.data(using: .utf8)
    else { return nil }
    return try? JSONDecoder().decode(Snapshot.self, from: data)
  }

  static let placeholder = Snapshot(
    version: 1, month: "September", spent: "₹38,450", spentCompact: "₹38K", today: "₹420", income: "₹90,000",
    budget: Budget(label: "₹11,550 left", ratio: 0.77, over: false),
    top: [
      Category(name: "Rent", amount: "₹15,000", color: "#AF52DE", icon: "house.fill"),
      Category(name: "Food", amount: "₹12,400", color: "#FF9500", icon: "fork.knife"),
      Category(name: "Transport", amount: "₹4,180", color: "#007AFF", icon: "car.fill"),
    ],
    hidden: false, updatedAt: 0)
}

extension Color {
  init(hex: String) {
    var value: UInt64 = 0
    Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
    self.init(
      red: Double((value >> 16) & 0xFF) / 255,
      green: Double((value >> 8) & 0xFF) / 255,
      blue: Double(value & 0xFF) / 255)
  }
}
