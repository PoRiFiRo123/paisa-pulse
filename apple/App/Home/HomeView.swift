import SwiftData
import SwiftUI

struct HomeView: View {
  @Environment(Router.self) private var router
  @Query(filter: #Predicate<Txn> { $0.deletedAt == nil }, sort: \Txn.occurredAt, order: .reverse) private var txns: [Txn]
  @Query(sort: \Account.sortOrder) private var accounts: [Account]
  @Query(sort: \Category.sortOrder) private var categories: [Category]
  @Query private var budgets: [Budget]
  @Query(sort: \RecurringRule.nextAt) private var rules: [RecurringRule]
  @Query(sort: \Goal.createdAt) private var goals: [Goal]
  @AppStorage(PrefKey.monthStartDay, store: AppGroup.defaults) private var monthStartDay = 1
  @AppStorage(PrefKey.weekStartDay, store: AppGroup.defaults) private var weekStartDay = 2
  @AppStorage(PrefKey.hideAmounts, store: AppGroup.defaults) private var hidden = false

  var body: some View {
    let lookups = Lookups(accounts: accounts, categories: categories)
    let month = Periods.month(containing: .now, startDay: monthStartDay)
    let summary = Ledger.summary(txns, in: month)
    let overall = budgets.first { $0.categoryId == nil && $0.period == "monthly" }
    let progress = Budgets.progress(budgets, txns: txns, categories: lookups.categories, month: month,
                                    week: Periods.week(containing: .now, firstWeekday: weekStartDay))
    let top = Ledger.byCategory(txns, in: month, categories: lookups.categories).prefix(6)

    List {
      Section {
        HeroCard(summary: summary, budget: overall?.amount, hidden: hidden)
          .listRowInsets(EdgeInsets())
      }

      if !top.isEmpty {
        Section("Where it went") {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
              ForEach(Array(top), id: \.id) { item in
                let c = lookups.categories[item.id]
                HStack(spacing: 8) {
                  CategoryBadge(icon: c?.icon ?? "questionmark", color: c?.color ?? "#8E8E93", size: 28)
                  VStack(alignment: .leading, spacing: 0) {
                    Text(c?.name ?? "Uncategorised").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text(Money.format(item.amount, hidden: hidden)).font(.subheadline.weight(.semibold)).fontDesign(.rounded)
                  }
                }
                .padding(.vertical, 8).padding(.horizontal, 12)
                .background(Color(.tertiarySystemFill), in: Capsule())
              }
            }
            .padding(.vertical, 4)
          }
          .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
          NavigationLink { InsightsView() } label: { Label("Insights", systemImage: "chart.bar.xaxis") }
        }
      }

      if !progress.isEmpty {
        Section {
          ForEach(progress) { p in BudgetRow(progress: p, lookups: lookups) }
        } header: {
          HStack { Text("Budgets"); Spacer(); NavigationLink("Edit") { BudgetsView() }.font(.subheadline).textCase(nil) }
        }
      }

      let activeGoals = goals.filter { $0.archivedAt == nil }
      if !activeGoals.isEmpty {
        Section {
          ForEach(activeGoals.prefix(3)) { g in GoalRow(goal: g) }
        } header: {
          HStack { Text("Goals"); Spacer(); NavigationLink("All") { GoalsView() }.font(.subheadline).textCase(nil) }
        }
      }

      let upcoming = rules.filter { $0.pausedAt == nil && $0.nextAt < Date.now.addingTimeInterval(7 * 86_400) }.prefix(3)
      if !upcoming.isEmpty {
        Section("Next 7 days") {
          ForEach(Array(upcoming)) { r in
            HStack {
              let c = r.categoryId.flatMap { lookups.categories[$0] }
              CategoryBadge(icon: c?.icon ?? "repeat", color: c?.color ?? "#8E8E93", size: 30)
              VStack(alignment: .leading) {
                Text(r.payee ?? c?.name ?? "Recurring")
                Text(r.nextAt.formatted(.relative(presentation: .named))).font(.footnote).foregroundStyle(.secondary)
              }
              Spacer()
              AmountText(amount: r.amount, type: r.type)
            }
          }
        }
      }

      Section {
        if txns.isEmpty {
          EmptyHint(title: "No transactions yet", icon: "indianrupeesign.circle",
                    message: "Tap + to add what you spent. It takes two taps.")
        }
        ForEach(txns.prefix(8)) { t in
          NavigationLink(value: t) { TxnRow(txn: t, lookups: lookups) }
            .txnActions(t)
        }
      } header: {
        HStack {
          Text("Recent"); Spacer()
          Button("See all") { router.tab = .activity }.font(.subheadline).textCase(nil)
        }
      }
    }
    .navigationTitle(month.start.formatted(.dateTime.month(.wide)))
    .navigationDestination(for: Txn.self) { TransactionDetailView(txn: $0) }
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        NavigationLink { CalendarView() } label: { Image(systemName: "calendar") }
          .accessibilityLabel("Calendar")
      }
      ToolbarItem(placement: .topBarTrailing) { AddButton() }
    }
  }
}

/// The + in the toolbar: tap for an expense, long-press for income or a transfer.
struct AddButton: View {
  @Environment(Router.self) private var router
  var body: some View {
    Menu {
      Button { router.add = AddRequest(type: .income) } label: { Label("Income", systemImage: "arrow.down.left") }
      Button { router.add = AddRequest(type: .transfer) } label: { Label("Transfer", systemImage: "arrow.left.arrow.right") }
      Button { router.add = AddRequest(type: .expense) } label: { Label("Expense", systemImage: "arrow.up.right") }
      Divider()
      Button { router.capture = true } label: { Label("From Screenshots", systemImage: "photo.on.rectangle") }
    } label: {
      Image(systemName: "plus").fontWeight(.semibold)
    } primaryAction: {
      router.add = AddRequest(type: .expense)
    }
    .accessibilityLabel("Add expense")
  }
}

/// One card, one ring: this month's spending against the budget (or income when there's no budget).
struct HeroCard: View {
  let summary: Ledger.Summary
  let budget: Int?
  let hidden: Bool

  var body: some View {
    let base = budget ?? summary.income
    let ratio = base > 0 ? min(Double(summary.spent) / Double(base), 1.5) : 0
    HStack(alignment: .center, spacing: 18) {
      VStack(alignment: .leading, spacing: 10) {
        Text("Spent this month").font(.subheadline).foregroundStyle(.secondary)
        Text(Money.format(summary.spent, hidden: hidden))
          .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
          .minimumScaleFactor(0.5).lineLimit(1)
          .contentTransition(.numericText())
        HStack(spacing: 16) {
          stat("Income", summary.income, .income)
          stat(summary.saved >= 0 ? "Saved" : "Overspent", abs(summary.saved), summary.saved >= 0 ? .primary : .expense)
        }
      }
      Spacer(minLength: 0)
      if base > 0 {
        ZStack {
          Circle().stroke(Color(.tertiarySystemFill), lineWidth: 10)
          Circle().trim(from: 0, to: min(ratio, 1))
            .stroke(ratio > 1 ? Color.expense : Color.accentColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
            .rotationEffect(.degrees(-90))
          VStack(spacing: 0) {
            Text("\(Int((ratio * 100).rounded()))%").font(.headline).fontDesign(.rounded)
            Text(budget != nil ? "of budget" : "of income").font(.caption2).foregroundStyle(.secondary)
          }
        }
        .frame(width: 88, height: 88)
        .animation(.spring, value: ratio)
        .accessibilityElement(children: .combine)
      }
    }
    .padding(20)
  }

  private func stat(_ label: String, _ value: Int, _ color: Color) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(label).font(.caption).foregroundStyle(.secondary)
      Text(Money.format(value, hidden: hidden)).font(.subheadline.weight(.semibold)).fontDesign(.rounded).foregroundStyle(color)
    }
  }
}

struct BudgetRow: View {
  let progress: Budgets.Progress
  let lookups: Lookups
  @AppStorage(PrefKey.hideAmounts, store: AppGroup.defaults) private var hidden = false

  var body: some View {
    let c = progress.budget.categoryId.flatMap { lookups.categories[$0] }
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(c?.name ?? "Everything").font(.subheadline.weight(.medium))
        if progress.budget.period == "weekly" { Text("weekly").font(.caption).foregroundStyle(.secondary) }
        Spacer()
        Text(progress.over ? "\(Money.format(-progress.left, hidden: hidden)) over" : "\(Money.format(progress.left, hidden: hidden)) left")
          .font(.subheadline).foregroundStyle(progress.over ? Color.expense : .secondary)
      }
      ProgressView(value: min(progress.ratio, 1))
        .tint(progress.over ? Color.expense : progress.ratio > 0.8 ? .orange : Color(hex: c?.color ?? "#5E5CE6"))
    }
    .padding(.vertical, 4)
  }
}
