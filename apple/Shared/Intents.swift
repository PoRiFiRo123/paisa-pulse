import AppIntents
import Foundation

/// Opens Quick Add. Used by the Control Center / Action Button control (iOS 18).
@available(iOS 18.0, *)
struct OpenAddExpenseIntent: AppIntent {
  static let title: LocalizedStringResource = "Add Expense"
  static let description = IntentDescription("Opens Paisa Pulse to add an expense.")
  static let openAppWhenRun = true

  func perform() async throws -> some IntentResult & OpensIntent {
    .result(opensIntent: OpenURLIntent(URL(string: "paisapulse://add?type=expense")!))
  }
}
