import AppIntents
import Foundation

/// Opens Quick Add. Used by the Control Center / Action Button control and by Shortcuts.
/// It runs inside the app (openAppWhenRun), so it hands the route to the app directly:
/// iOS refuses to open the app's own custom URL scheme from an intent ("launch is prohibited").
@available(iOS 18.0, *)
struct OpenAddExpenseIntent: AppIntent {
  static let title: LocalizedStringResource = "Add Expense"
  static let description = IntentDescription("Opens Paisa Pulse to add an expense.")
  static let openAppWhenRun = true

  @MainActor func perform() async throws -> some IntentResult {
    PendingRoute.open("paisapulse://add?type=expense")
    return .result()
  }
}

@available(iOS 18.0, *)
struct OpenAddIncomeIntent: AppIntent {
  static let title: LocalizedStringResource = "Add Income"
  static let description = IntentDescription("Opens Paisa Pulse to add income.")
  static let openAppWhenRun = true

  @MainActor func perform() async throws -> some IntentResult {
    PendingRoute.open("paisapulse://add?type=income")
    return .result()
  }
}

/// A route for the app to open, from an intent. Posted now (app running) and kept until handled (cold launch).
enum PendingRoute {
  static let notification = Notification.Name("PaisaQuickAction")
  private static let key = "pendingRoute"
  static func open(_ s: String) {
    AppGroup.defaults.set(s, forKey: key)
    NotificationCenter.default.post(name: notification, object: URL(string: s))
  }
  /// The route waiting to be opened, cleared once read.
  static func take() -> URL? {
    guard let s = AppGroup.defaults.string(forKey: key) else { return nil }
    AppGroup.defaults.removeObject(forKey: key)
    return URL(string: s)
  }
}
