import AppIntents
import SwiftUI
import WidgetKit

/// Opens Paisa Pulse on the Quick Add sheet. Used by the Control Center control and the
/// Action Button (iOS 18+), and shows up in Shortcuts.
@available(iOS 18.0, *)
struct OpenQuickAddIntent: AppIntent {
  static var title: LocalizedStringResource = "Add Expense"
  static var description = IntentDescription("Open Paisa Pulse to log an expense.")
  static var openAppWhenRun = true

  func perform() async throws -> some IntentResult & OpensIntent {
    .result(opensIntent: OpenURLIntent(URL(string: "paisapulse://add?type=expense")!))
  }
}

@available(iOS 18.0, *)
struct QuickAddControl: ControlWidget {
  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: "com.paisapulse.app.quick-add") {
      ControlWidgetButton(action: OpenQuickAddIntent()) {
        Label("Add Expense", systemImage: "indianrupeesign.circle.fill")
      }
    }
    .displayName("Add Expense")
    .description("Log an expense in Paisa Pulse.")
  }
}
