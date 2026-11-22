import SwiftData
import SwiftUI

/// Settings › Data › Clean Up: periodic auto-delete of old transactions (folded into opening balances, backup first)
/// and Delete All Data. Same screen on Android (CleanupScreen).
struct CleanupView: View {
  @AppStorage(PrefKey.autoCleanup, store: AppGroup.defaults) private var auto = "off"
  @AppStorage(PrefKey.autoCleanupMonths, store: AppGroup.defaults) private var customMonths = 24
  @AppStorage(PrefKey.lastCleanupAt, store: AppGroup.defaults) private var lastCleanup = 0.0
  @Query private var txns: [Txn]
  @Environment(\.modelContext) private var context
  @Environment(Router.self) private var router
  @State private var confirmNow = false
  @State private var confirmAll = false
  @State private var confirmAllAgain = false

  var body: some View {
    let months = Cleanup.months(key: auto, custom: customMonths)
    let cutoff = months.map { Cleanup.cutoff(months: $0) }
    let old = cutoff.map { c in txns.filter { $0.occurredAt < c }.count } ?? 0
    Form {
      Section {
        Picker("Keep transactions", selection: $auto) {
          ForEach(Cleanup.options, id: \.key) { Text($0.label).tag($0.key) }
        }
        if auto == "custom" {
          Stepper("Keep \(customMonths) months", value: $customMonths, in: 1...120)
        }
      } header: { Text("Auto clean-up") } footer: {
        Text("Transactions older than this are removed to save space. Account balances stay right: what they added up to moves into each account's starting balance. A backup is saved first.")
      }
      if let cutoff {
        Section {
          LabeledContent("Older than", value: cutoff.formatted(date: .abbreviated, time: .omitted))
          LabeledContent("Transactions", value: "\(old)")
          Button("Clean Up Now") { confirmNow = true }.disabled(old == 0)
        } footer: {
          if lastCleanup > 0 { Text("Last clean-up \(Date(timeIntervalSince1970: lastCleanup).formatted(date: .abbreviated, time: .omitted)).") }
        }
      }
      Section {
        Button("Delete All Data", role: .destructive) { confirmAll = true }
      } footer: { Text("Removes every account, transaction, budget, split and loan from this phone. A backup is saved first in Files › Paisa Pulse › backups.") }
    }
    .navigationTitle("Clean Up Data")
    .confirmationDialog("Remove \(old) transactions from before \(cutoff?.formatted(date: .abbreviated, time: .omitted) ?? "")?", isPresented: $confirmNow, titleVisibility: .visible) {
      Button("Back Up and Clean Up", role: .destructive) {
        let n = DataCleanup.run(context, months: months ?? 0)
        router.show("Removed \(n) old transactions")
      }
    }
    .confirmationDialog("Delete everything?", isPresented: $confirmAll, titleVisibility: .visible) {
      Button("Delete All Data", role: .destructive) { confirmAllAgain = true }
    } message: { Text("This can't be undone, except by restoring the backup.") }
    .alert("Are you sure?", isPresented: $confirmAllAgain) {
      Button("Delete Everything", role: .destructive) { DataCleanup.deleteAll(context) }
      Button("Cancel", role: .cancel) {}
    } message: { Text("Paisa Pulse will start fresh.") }
  }
}

enum DataCleanup {
  /// Backs up, folds transactions older than `months` into opening balances and removes them. Returns how many were removed.
  @MainActor @discardableResult static func run(_ context: ModelContext, months: Int) -> Int {
    guard months > 0 else { return 0 }
    try? AutoBackup.write(context)
    let txns = (try? context.fetch(FetchDescriptor<Txn>())) ?? []
    let plan = Cleanup.plan(txns, before: Cleanup.cutoff(months: months))
    guard !plan.remove.isEmpty else { return 0 }
    let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
    for a in accounts { if let d = plan.delta[a.id] { a.openingBalance += d; a.updatedAt = .now } }
    var removed = 0
    for t in txns where plan.remove.contains(t.id) { if t.deletedAt == nil { removed += 1 }; context.delete(t) }
    try? context.save()
    AppGroup.defaults.set(Date.now.timeIntervalSince1970, forKey: PrefKey.lastCleanupAt)
    WidgetRefresh.now()
    return removed
  }

  /// Auto clean-up, at most once a day (called from Maintenance).
  @MainActor static func runIfDue(_ context: ModelContext) {
    let d = AppGroup.defaults
    guard let months = Cleanup.months(key: d.string(forKey: PrefKey.autoCleanup) ?? "off", custom: d.integer(forKey: PrefKey.autoCleanupMonths)) else { return }
    guard Date.now.timeIntervalSince1970 - d.double(forKey: PrefKey.lastCleanupAt) > 86_400 else { return }
    run(context, months: months)
  }

  @MainActor static func deleteAll(_ context: ModelContext) {
    try? AutoBackup.write(context)
    try? context.delete(model: Txn.self); try? context.delete(model: Account.self); try? context.delete(model: Category.self)
    try? context.delete(model: RecurringRule.self); try? context.delete(model: Budget.self); try? context.delete(model: Friend.self)
    try? context.delete(model: SplitEntry.self); try? context.delete(model: Goal.self); try? context.delete(model: PaymentCard.self)
    try? context.delete(model: SavedFilter.self); try? context.delete(model: ImportBatch.self); try? context.delete(model: SplitGroup.self)
    try? context.delete(model: Loan.self); try? context.delete(model: LoanPayment.self)
    try? context.save()
    AppGroup.defaults.set(false, forKey: PrefKey.onboarded)
    WidgetRefresh.now()
  }
}
