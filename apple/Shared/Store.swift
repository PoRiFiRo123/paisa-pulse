import Foundation
import SwiftData

enum Store {
  static let schema = Schema([
    Account.self, Category.self, Txn.self, Budget.self, RecurringRule.self,
    Friend.self, SplitEntry.self, Goal.self, PaymentCard.self, SavedFilter.self, ImportBatch.self, SplitGroup.self, Loan.self, LoanPayment.self, TxnTemplate.self, Valuation.self, Trip.self, TripItem.self, TripWallet.self,
  ])

  /// The database lives in the App Group so the widget can read it.
  static func makeContainer(inMemory: Bool = false) -> ModelContainer {
    let config: ModelConfiguration
    if inMemory {
      config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    } else if let dir = AppGroup.containerURL {
      let url = dir.appending(path: "PaisaPulse.store")
      if AppGroup.isMainApp { moveOldStore(to: url); AppGroup.moveOldDefaults() }
      config = ModelConfiguration(schema: schema, url: url)
    } else {
      // No App Group (e.g. an unsigned simulator build): Application Support, created if missing.
      let dir = URL.applicationSupportDirectory
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      config = ModelConfiguration(schema: schema, url: dir.appending(path: "PaisaPulse.store"))
    }
    do {
      return try ModelContainer(for: schema, configurations: config)
    } catch {
      // Never lose the app to a bad store: fall back to memory and say so in the log.
      print("Paisa Pulse: couldn't open the store (\(error)); using a temporary one")
      return try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }
  }

  /// Builds that couldn't find the App Group kept the database in the app's own Application Support, where the widget
  /// and the share extension can't see it. Once the group is found, move it there (only if the group has none yet).
  static func moveOldStore(to url: URL) {
    let fm = FileManager.default
    let old = URL.applicationSupportDirectory.appending(path: "PaisaPulse.store")
    guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: url.path) else { return }
    for suffix in ["", "-wal", "-shm"] {
      let from = URL(fileURLWithPath: old.path + suffix), to = URL(fileURLWithPath: url.path + suffix)
      if fm.fileExists(atPath: from.path) { try? fm.moveItem(at: from, to: to) }
    }
  }
}
