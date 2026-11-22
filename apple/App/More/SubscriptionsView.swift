import SwiftData
import SwiftUI

/// Recurring expenses with what they cost a month and a year, plus steady payments found in your history.
struct SubscriptionsView: View {
  @Query(sort: \RecurringRule.nextAt) private var rules: [RecurringRule]
  @Query(filter: #Predicate<Txn> { $0.deletedAt == nil }) private var txns: [Txn]
  @Query private var accounts: [Account]
  @Query private var categories: [Category]
  @Environment(\.modelContext) private var context
  @Environment(Router.self) private var router
  @AppStorage(PrefKey.hideAmounts, store: AppGroup.defaults) private var hidden = false
  @State private var dismissed: Set<String> = []

  var body: some View {
    let lookups = Lookups(accounts: accounts, categories: categories)
    let subs = rules.filter { $0.type == .expense }
      .sorted { (Subscriptions.isActive($0) ? 0 : 1, $0.nextAt) < (Subscriptions.isActive($1) ? 0 : 1, $1.nextAt) }
    let active = subs.filter { Subscriptions.isActive($0) }
    let monthly = active.reduce(0) { $0 + Subscriptions.monthly($1) }
    let found = Subscriptions.detect(txns, rules: rules).filter { !dismissed.contains($0.id) }
    let paid = Dictionary(grouping: txns.filter { $0.recurringId != nil }, by: { $0.recurringId! })

    List {
      Section {
        VStack(alignment: .leading, spacing: 4) {
          Text("Every month").font(.subheadline).foregroundStyle(.secondary)
          Text(Money.format(monthly, hidden: hidden)).font(.system(size: 40, weight: .bold, design: .rounded))
            .foregroundStyle(Color.expense)
          Text("\(Money.format(monthly * 12, hidden: hidden)) a year · \(active.count) active")
            .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
      }

      if !found.isEmpty {
        Section {
          ForEach(found) { d in
            HStack(spacing: 12) {
              badge(d.payee, categoryId: d.categoryId, lookups)
              VStack(alignment: .leading, spacing: 2) {
                Text(d.payee).lineLimit(1)
                Text("\(Money.format(d.amount, hidden: hidden)) every \(d.frequency.noun) · \(d.txnIds.count) payments")
                  .font(.footnote).foregroundStyle(.secondary)
              }
              Spacer()
              Button("Track") { track(d) }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.small)
            }
            .swipeActions { Button("Ignore") { dismissed.insert(d.id) }.tint(.gray) }
          }
        } header: { Text("Found in your history") } footer: {
          Text("Steady payments on a steady cadence. Tracking adds the next payment for you and links the past ones.")
        }
      }

      Section(subs.isEmpty ? "" : "Tracked") {
        if subs.isEmpty {
          EmptyHint(title: "No subscriptions yet", icon: "creditcard.and.123",
                    message: "Netflix, Spotify, the gym: track them here, or add a monthly expense under Recurring.")
        }
        ForEach(subs) { r in
          let on = Subscriptions.isActive(r)
          let payments = paid[r.id] ?? []
          NavigationLink { RecurringFormView(rule: r) } label: {
            HStack(spacing: 12) {
              badge(r.payee, categoryId: r.categoryId, lookups)
              VStack(alignment: .leading, spacing: 2) {
                Text(r.payee ?? r.categoryId.flatMap { lookups.categories[$0]?.name } ?? "Subscription").lineLimit(1)
                Text(on ? "Renews \(r.nextAt.formatted(.dateTime.day().month(.abbreviated)))" : r.pausedAt != nil ? "Paused" : "Ended")
                  .font(.footnote).foregroundStyle(on ? .secondary : .tertiary)
                if !payments.isEmpty {
                  Text("Paid \(Money.format(payments.reduce(0) { $0 + $1.amount }, hidden: hidden)) over \(payments.count) payments")
                    .font(.caption).foregroundStyle(.secondary)
                }
              }
              Spacer()
              VStack(alignment: .trailing, spacing: 2) {
                AmountText(amount: r.amount, type: .expense)
                Text("/\(r.interval > 1 ? "\(r.interval) " : "")\(r.frequency.noun)\(r.interval > 1 ? "s" : "")")
                  .font(.caption).foregroundStyle(.secondary)
              }
            }
            .opacity(on ? 1 : 0.55)
          }
        }
      }
    }
    .navigationTitle("Subscriptions")
  }

  @ViewBuilder private func badge(_ payee: String?, categoryId: String?, _ lookups: Lookups) -> some View {
    if let brand = Brands.match(payee) {
      MerchantBadge(brand: brand)
    } else {
      let c = categoryId.flatMap { lookups.categories[$0] }
      CategoryBadge(icon: c?.icon ?? "repeat", color: c?.color ?? "#32ADE6")
    }
  }

  private func track(_ d: Subscriptions.Detected) {
    let rule = Subscriptions.rule(for: d)
    context.insert(rule)
    let ids = Set(d.txnIds)
    for t in txns where ids.contains(t.id) { t.recurringId = rule.id }
    try? context.save()
    router.show("Tracking \(d.payee)") {
      for t in txns where ids.contains(t.id) { t.recurringId = nil }
      context.delete(rule)
      try? context.save()
    }
  }
}
