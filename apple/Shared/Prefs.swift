import SwiftUI

/// Keys for preferences kept in the App Group's UserDefaults (shared with the widget).
enum PrefKey {
  static let onboarded = "onboarded"
  static let theme = "theme"               // system | light | dark
  static let accent = "accent"             // Palette.accents key
  static let monthStartDay = "monthStartDay"
  static let weekStartDay = "weekStartDay" // 1 = Sunday, 2 = Monday
  static let hideAmounts = "hideAmounts"
  static let appLock = "appLock"
  static let lastAccountId = "lastAccountId"
  static let notifyBudgets = "notifyBudgets"
  static let notifyBills = "notifyBills"
  static let notifyWeekly = "notifyWeekly"
  static let autoBackup = "autoBackup"
  static let lastBackupAt = "lastBackupAt"
  static let merchantLogos = "merchantLogos"
}
