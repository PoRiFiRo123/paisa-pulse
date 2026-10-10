import Foundation

/// An entry logged from Siri, Shortcuts or a Wallet automation. The app turns these into
/// transactions the next time it opens (src/features/capture/pending.ts reads the same JSON).
struct PendingEntry: Codable {
  let id: String
  /// "expense" or "income".
  let kind: String
  /// Rupees, as spoken or passed by Shortcuts.
  let amount: Double
  let payee: String?
  let note: String?
  /// Account or card name to match (e.g. Wallet's card name).
  let account: String?
  let category: String?
  /// Epoch seconds.
  let at: Double
  /// "siri" or "wallet".
  let source: String
}

enum Shared {
  static let appGroup = "group.com.paisapulse.app"
  static let pendingKey = "pendingCaptures"

  static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

  static func appendPending(_ entry: PendingEntry) {
    guard let defaults else { return }
    var list: [PendingEntry] = []
    if let json = defaults.string(forKey: pendingKey), let data = json.data(using: .utf8),
      let existing = try? JSONDecoder().decode([PendingEntry].self, from: data)
    {
      list = existing
    }
    list.append(entry)
    if let data = try? JSONEncoder().encode(list), let json = String(data: data, encoding: .utf8) {
      defaults.set(json, forKey: pendingKey)
    }
  }

  /// The parts of the widget snapshot (src/features/widgets/snapshot.ts) Siri reads out.
  struct Snapshot: Decodable {
    let month: String
    let spent: String
    let today: String
    let hidden: Bool
  }

  static func snapshot() -> Snapshot? {
    guard let json = defaults?.string(forKey: "snapshot"), let data = json.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(Snapshot.self, from: data)
  }

  /// "₹250", "₹1,250.50" with Indian grouping.
  static func rupees(_ amount: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.locale = Locale(identifier: "en_IN")
    formatter.currencyCode = "INR"
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = amount.rounded() == amount ? 0 : 2
    return formatter.string(from: NSNumber(value: amount)) ?? "₹\(amount)"
  }
}
