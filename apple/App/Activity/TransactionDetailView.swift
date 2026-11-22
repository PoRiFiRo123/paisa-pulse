import SwiftData
import SwiftUI

struct TransactionDetailView: View {
  @Bindable var txn: Txn
  @Environment(Router.self) private var router
  @Environment(\.modelContext) private var context
  @Environment(\.dismiss) private var dismiss
  @Query private var accounts: [Account]
  @Query private var categories: [Category]
  @Query private var friends: [Friend]
  @Query private var splitEntries: [SplitEntry]
  @State private var repeatSheet = false

  var body: some View {
    let lookups = Lookups(accounts: accounts, categories: categories)
    let badge = lookups.badge(txn)
    let mySplits = splitEntries.filter { $0.txnId == txn.id }
    List {
      Section {
        VStack(spacing: 10) {
          CategoryBadge(icon: badge.icon, color: badge.color, size: 64)
          Text(lookups.title(txn)).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
          AmountText(amount: txn.amount, type: txn.type, font: .system(size: 44, weight: .bold))
          Text(txn.occurredAt.formatted(date: .complete, time: .shortened)).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
      }
      .listRowBackground(Color.clear)

      Section {
        LabeledContent("Type", value: txn.type.label)
        if txn.type == .transfer {
          LabeledContent("From", value: lookups.accounts[txn.accountId]?.displayName ?? "—")
          LabeledContent("To", value: txn.toAccountId.flatMap { lookups.accounts[$0]?.displayName } ?? "—")
        } else {
          LabeledContent("Category", value: txn.categoryId.flatMap { lookups.categories[$0]?.name } ?? "Uncategorised")
          LabeledContent("Account", value: lookups.accounts[txn.accountId]?.displayName ?? "—")
        }
        if let note = txn.note, !note.isEmpty { LabeledContent("Note", value: note) }
        if txn.source != "manual" { LabeledContent("Added by", value: txn.source.capitalized) }
      }

      if let share = txn.splitShare {
        Section("Split") {
          LabeledContent("Your share") { Text(Money.format(share)) }
          ForEach(mySplits) { e in
            LabeledContent(friends.first { $0.id == e.friendId }?.name ?? "Friend") {
              Text(e.amount >= 0 ? "owes \(Money.format(e.amount))" : "paid, you owe \(Money.format(-e.amount))")
                .foregroundStyle(e.amount >= 0 ? Color.income : Color.expense)
            }
          }
        }
      }

      Section {
        Button { router.add = AddRequest(type: txn.type, editing: txn) } label: { Label("Edit", systemImage: "pencil") }
        Button { TxnOps.duplicate(txn, context: context, router: router) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
        if txn.recurringId == nil {
          Button { repeatSheet = true } label: { Label("Repeat…", systemImage: "repeat") }
        }
        Button(role: .destructive) {
          TxnOps.delete(txn, context: context, router: router)
          dismiss()
        } label: { Label("Delete", systemImage: "trash") }
      }
    }
    .navigationTitle("")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Edit") { router.add = AddRequest(type: txn.type, editing: txn) }
      }
    }
    .sheet(isPresented: $repeatSheet) {
      NavigationStack { RecurringFormView(from: txn) }
    }
  }
}
