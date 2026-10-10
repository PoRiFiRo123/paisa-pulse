import AppIntents
import Foundation

/// "Hey Siri, log an expense in Paisa Pulse" → "How much?" → "What was it for?"
struct LogExpenseIntent: AppIntent {
  static var title: LocalizedStringResource = "Log Expense"
  static var description = IntentDescription("Add an expense to Paisa Pulse without opening the app.")

  @Parameter(title: "Amount", description: "In rupees", requestValueDialog: "How much did you spend?")
  var amount: Double

  @Parameter(title: "For", requestValueDialog: "What was it for?")
  var payee: String

  @Parameter(title: "Account", description: "Account or card name, e.g. Axis or Cash")
  var account: String?

  static var parameterSummary: some ParameterSummary {
    Summary("Log \(\.$amount) for \(\.$payee)") {
      \.$account
    }
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    guard amount > 0 else { throw $amount.needsValueError("How much did you spend?") }
    Shared.appendPending(
      PendingEntry(
        id: UUID().uuidString, kind: "expense", amount: amount, payee: payee, note: nil, account: account, category: nil,
        at: Date().timeIntervalSince1970, source: "siri"))
    return .result(dialog: "Logged \(Shared.rupees(amount)) for \(payee).")
  }
}

/// "Log income in Paisa Pulse".
struct LogIncomeIntent: AppIntent {
  static var title: LocalizedStringResource = "Log Income"
  static var description = IntentDescription("Add money you received to Paisa Pulse.")

  @Parameter(title: "Amount", description: "In rupees", requestValueDialog: "How much did you receive?")
  var amount: Double

  @Parameter(title: "From", requestValueDialog: "Who was it from?")
  var payee: String

  @Parameter(title: "Account", description: "Account name, e.g. Axis")
  var account: String?

  static var parameterSummary: some ParameterSummary {
    Summary("Log income of \(\.$amount) from \(\.$payee)") {
      \.$account
    }
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    guard amount > 0 else { throw $amount.needsValueError("How much did you receive?") }
    Shared.appendPending(
      PendingEntry(
        id: UUID().uuidString, kind: "income", amount: amount, payee: payee, note: nil, account: account, category: nil,
        at: Date().timeIntervalSince1970, source: "siri"))
    return .result(dialog: "Logged \(Shared.rupees(amount)) from \(payee).")
  }
}

/// For Shortcuts automations, e.g. Wallet's "When I tap a card" trigger:
/// pass Shortcut Input › Amount, Merchant and Card. Never asks questions, so it can run silently.
struct LogCardPaymentIntent: AppIntent {
  static var title: LocalizedStringResource = "Log Card Payment"
  static var description = IntentDescription(
    "Record a payment from an automation (for example a Wallet transaction). Runs without asking anything.")

  @Parameter(title: "Amount", description: "In rupees")
  var amount: Double

  @Parameter(title: "Merchant")
  var merchant: String?

  @Parameter(title: "Card", description: "The card name; matched to your Paisa Pulse accounts")
  var card: String?

  static var parameterSummary: some ParameterSummary {
    Summary("Log \(\.$amount) at \(\.$merchant)") {
      \.$card
    }
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    guard amount > 0 else { return .result(dialog: "Nothing to log.") }
    Shared.appendPending(
      PendingEntry(
        id: UUID().uuidString, kind: "expense", amount: amount, payee: merchant, note: nil, account: card, category: nil,
        at: Date().timeIntervalSince1970, source: "wallet"))
    return .result(dialog: "Paisa Pulse logged \(Shared.rupees(amount))\(merchant.map { " at \($0)" } ?? "").")
  }
}

/// "How much have I spent in Paisa Pulse?" — read from the widget snapshot the app keeps fresh.
struct SpentThisMonthIntent: AppIntent {
  static var title: LocalizedStringResource = "Spent This Month"
  static var description = IntentDescription("Hear how much you've spent this month.")

  func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
    guard let s = Shared.snapshot() else {
      return .result(value: "", dialog: "Open Paisa Pulse once so I can see your spending.")
    }
    if s.hidden {
      return .result(value: "", dialog: "Amounts are hidden in Paisa Pulse. Open the app to see them.")
    }
    return .result(value: s.spent, dialog: "You've spent \(s.spent) so far in \(s.month), \(s.today) today.")
  }
}

/// Opens the voice capture sheet ("250 lunch, 80 auto and 40 chai"). iOS 18+.
@available(iOS 18.0, *)
struct SayItIntent: AppIntent {
  static var title: LocalizedStringResource = "Say Expenses"
  static var description = IntentDescription("Open Paisa Pulse and log several expenses by voice.")
  static var openAppWhenRun = true

  func perform() async throws -> some IntentResult & OpensIntent {
    .result(opensIntent: OpenURLIntent(URL(string: "paisapulse://capture?mode=voice")!))
  }
}

/// Siri phrases that work with no setup. Every phrase must name the app.
struct PaisaPulseShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: LogExpenseIntent(),
      phrases: [
        "Log an expense in \(.applicationName)",
        "Add an expense to \(.applicationName)",
        "Log spending in \(.applicationName)",
        "\(.applicationName) expense",
      ],
      shortTitle: "Log Expense",
      systemImageName: "indianrupeesign.circle.fill")
    AppShortcut(
      intent: LogIncomeIntent(),
      phrases: ["Log income in \(.applicationName)", "Add income to \(.applicationName)"],
      shortTitle: "Log Income",
      systemImageName: "arrow.down.left.circle.fill")
    AppShortcut(
      intent: SpentThisMonthIntent(),
      phrases: [
        "How much have I spent in \(.applicationName)",
        "What have I spent this month in \(.applicationName)",
        "\(.applicationName) spending",
      ],
      shortTitle: "Spent This Month",
      systemImageName: "chart.bar.fill")
  }
}
