import SwiftData
import SwiftUI

/// Card bills and recurring bills due in the next month, soonest first. Same screen as Android Bills.
struct BillsView: View {
  @Query(sort: \Account.sortOrder) private var accounts: [Account]
  @Query(filter: #Predicate<Txn> { $0.deletedAt == nil }) private var txns: [Txn]
  @Query private var rules: [RecurringRule]
  @Query private var valuations: [Valuation]
  @Environment(\.modelContext) private var context
  @Environment(Router.self) private var router
  @AppStorage(PrefKey.lastAccountId, store: AppGroup.defaults) private var lastAccountId = ""
  @AppStorage(PrefKey.notifyBills, store: AppGroup.defaults) private var notifyBills = false

  var body: some View {
    let balances = Ledger.balances(accounts: accounts, txns: txns, valuations: valuations)
    let bills = Bills.upcoming(accounts: accounts, txns: txns, rules: rules, balances: balances)
    List {
      if bills.isEmpty {
        EmptyHint(title: "No bills coming up", icon: "checkmark.seal",
                  message: "Card bills show here when a card has a due day (Accounts › card › Edit). Recurring expenses like rent show too.")
      } else {
        Section {
          ForEach(bills) { b in row(b) }
        } header: { Text("Next 31 days") } footer: {
          Text("\(Money.format(bills.reduce(0) { $0 + $1.amount })) in total. Recurring bills are added on their day by themselves.")
        }
      }
      Section {
        Toggle("Remind me", isOn: $notifyBills)
      } footer: {
        Text("Card bills 3 days before the due day, other bills 2 days before.")
      }
      .onChange(of: notifyBills) { _, on in Task { if on { _ = await Notifier.requestPermission() }; Notifier.refresh(context) } }
    }
    .navigationTitle("Bills")
  }

  private func row(_ b: Bill) -> some View {
    let days = Bills.daysLeft(b)
    return HStack(spacing: 12) {
      CategoryBadge(icon: b.icon, color: b.color)
      VStack(alignment: .leading, spacing: 2) {
        Text(b.title).lineLimit(1)
        Text("\(Bills.dueText(b)) · \(b.due.formatted(.dateTime.day().month()))").font(.caption)
          .foregroundStyle(days <= 1 ? Color.expense : .secondary)
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 4) {
        Text(Money.format(b.amount)).font(.body.weight(.semibold)).monospacedDigit()
        if b.isCard {
          Button("Record Payment") { recordPayment(b) }.font(.caption.weight(.semibold)).buttonStyle(.pressable).foregroundStyle(Color.accentColor)
        }
      }
    }
  }

  /// A transfer from your bank into the card for the amount due, with Undo.
  private func recordPayment(_ b: Bill) {
    let banks = accounts.filter { $0.type == .bank && $0.archivedAt == nil }
    guard let from = banks.first(where: { $0.id == lastAccountId }) ?? banks.first else {
      router.showError("Add a bank account first to pay the card from."); return
    }
    let t = Txn(type: .transfer, amount: b.amount, accountId: from.id, toAccountId: b.accountId, note: "Card bill payment")
    context.insert(t); try? context.save(); WidgetRefresh.now(); Notifier.refresh(context)
    router.show("Paid \(Money.format(b.amount)) from \(from.name)") {
      t.deletedAt = .now; try? context.save(); WidgetRefresh.now()
    }
  }
}
