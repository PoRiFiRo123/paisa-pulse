import SwiftData
import SwiftUI

struct ActivityFilter: Equatable {
  var monthOffset = 0
  var accountId: String?
  var categoryId: String?
  var type: TxnType?
  var isDefault: Bool { accountId == nil && categoryId == nil && type == nil }
}

struct ActivityView: View {
  @Query(filter: #Predicate<Txn> { $0.deletedAt == nil }, sort: \Txn.occurredAt, order: .reverse) private var txns: [Txn]
  @Query(sort: \Account.sortOrder) private var accounts: [Account]
  @Query(sort: \Category.sortOrder) private var categories: [Category]
  @AppStorage(PrefKey.monthStartDay, store: AppGroup.defaults) private var monthStartDay = 1
  @State private var filter = ActivityFilter()
  @State private var query = ""

  var body: some View {
    let lookups = Lookups(accounts: accounts, categories: categories)
    let range = Periods.month(offset: filter.monthOffset, startDay: monthStartDay)
    let rows = txns.filter { keep($0, range: range, lookups: lookups) }
    let days = Dictionary(grouping: rows) { Calendar.current.startOfDay(for: $0.occurredAt) }.sorted { $0.key > $1.key }
    let summary = Ledger.summary(rows, in: range)

    List {
      Section {
        HStack(spacing: 0) {
          SummaryCell(label: "Spent", value: summary.spent, color: .expense)
          Divider()
          SummaryCell(label: "Income", value: summary.income, color: .income)
        }
        .frame(height: 52)
      }
      if rows.isEmpty {
        EmptyHint(title: query.isEmpty ? "Nothing here" : "No results", icon: query.isEmpty ? "tray" : "magnifyingglass",
                  message: query.isEmpty ? "No transactions in \(Periods.label(range, startDay: monthStartDay)) with these filters." : "Try a payee, note, category or amount.")
      }
      ForEach(days, id: \.key) { day, items in
        Section {
          ForEach(items) { t in
            NavigationLink(value: t) { TxnRow(txn: t, lookups: lookups) }.txnActions(t)
          }
        } header: {
          DayHeader(date: day, total: items.filter { $0.type == .expense }.reduce(0) { $0 + $1.effectiveAmount })
        }
      }
    }
    .navigationTitle("Activity")
    .searchable(text: $query, prompt: "Payee, note, category, amount")
    .navigationDestination(for: Txn.self) { TransactionDetailView(txn: $0) }
    .toolbar {
      ToolbarItemGroup(placement: .topBarLeading) {
        Button { filter.monthOffset -= 1 } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous month")
        Text(Periods.label(range, startDay: monthStartDay)).font(.subheadline.weight(.semibold)).fixedSize()
        Button { filter.monthOffset += 1 } label: { Image(systemName: "chevron.right") }
          .disabled(filter.monthOffset >= 0).accessibilityLabel("Next month")
      }
      ToolbarItem(placement: .topBarTrailing) { filterMenu(lookups) }
      ToolbarItem(placement: .topBarTrailing) { AddButton() }
    }
  }

  private func keep(_ t: Txn, range: DateInterval, lookups: Lookups) -> Bool {
    guard range.contains(t.occurredAt) else { return false }
    if let a = filter.accountId, t.accountId != a, t.toAccountId != a { return false }
    if let c = filter.categoryId, t.categoryId != c, Ledger.topLevel(t.categoryId, lookups.categories) != c { return false }
    if let type = filter.type, t.type != type { return false }
    return Search.matches(t, query, lookups)
  }

  private func filterMenu(_ lookups: Lookups) -> some View {
    Menu {
      Picker("Type", selection: $filter.type) {
        Text("All types").tag(TxnType?.none)
        ForEach(TxnType.allCases) { Text($0.label).tag(TxnType?.some($0)) }
      }
      Picker("Account", selection: $filter.accountId) {
        Text("All accounts").tag(String?.none)
        ForEach(accounts.filter { $0.archivedAt == nil }) { Text($0.name).tag(String?.some($0.id)) }
      }
      .pickerStyle(.menu)
      Picker("Category", selection: $filter.categoryId) {
        Text("All categories").tag(String?.none)
        ForEach(categories.filter { $0.parentId == nil && $0.archivedAt == nil }) { Text($0.name).tag(String?.some($0.id)) }
      }
      .pickerStyle(.menu)
      if !filter.isDefault {
        Button("Clear Filters", role: .destructive) { filter = ActivityFilter(monthOffset: filter.monthOffset) }
      }
    } label: {
      Image(systemName: filter.isDefault ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
    }
    .accessibilityLabel("Filters")
  }
}

struct SummaryCell: View {
  let label: String
  let value: Int
  let color: Color
  @AppStorage(PrefKey.hideAmounts, store: AppGroup.defaults) private var hidden = false
  var body: some View {
    VStack(spacing: 2) {
      Text(label).font(.caption).foregroundStyle(.secondary)
      Text(Money.format(value, hidden: hidden)).font(.headline).fontDesign(.rounded).foregroundStyle(color)
    }
    .frame(maxWidth: .infinity)
  }
}

enum Search {
  /// Matches payee, note, category, account, or an amount ("450", "4,500").
  static func matches(_ t: Txn, _ q: String, _ l: Lookups) -> Bool {
    let q = q.trimmingCharacters(in: .whitespaces).lowercased()
    if q.isEmpty { return true }
    if let paise = Money.parse(q), t.amount == paise { return true }
    let fields = [t.payee, t.note, t.categoryId.flatMap { l.categories[$0]?.name }, l.accounts[t.accountId]?.name]
    return fields.contains { $0?.lowercased().contains(q) == true }
  }
}

/// The search tab: everything, all months.
struct SearchView: View {
  @Query(filter: #Predicate<Txn> { $0.deletedAt == nil }, sort: \Txn.occurredAt, order: .reverse) private var txns: [Txn]
  @Query private var accounts: [Account]
  @Query private var categories: [Category]
  @State private var query = ""

  var body: some View {
    let lookups = Lookups(accounts: accounts, categories: categories)
    let results = query.isEmpty ? [] : Array(txns.filter { Search.matches($0, query, lookups) }.prefix(200))
    let total = results.filter { $0.type == .expense }.reduce(0) { $0 + $1.effectiveAmount }
    List {
      if query.isEmpty {
        EmptyHint(title: "Search everything", icon: "magnifyingglass", message: "Swiggy, rent, 499, a note… across every month.")
      } else if results.isEmpty {
        ContentUnavailableView.search(text: query)
      } else {
        Section {
          ForEach(results) { t in
            NavigationLink(value: t) { TxnRow(txn: t, lookups: lookups, showTime: false) }.txnActions(t)
          }
        } header: {
          Text("\(results.count) results · \(Money.format(total)) spent")
        }
      }
    }
    .navigationTitle("Search")
    .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
    .navigationDestination(for: Txn.self) { TransactionDetailView(txn: $0) }
  }
}
