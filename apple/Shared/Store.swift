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
      config = ModelConfiguration(schema: schema, url: dir.appending(path: "PaisaPulse.store"))
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
}
