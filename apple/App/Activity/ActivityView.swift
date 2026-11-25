import SwiftData
import SwiftUI

struct ActivityFilter: Equatable {
  var monthOffset = 0
  var accountId: String?
  var categoryId: String?
  var type: TxnType?
  var isDefault: Bool { accountId == nil && categoryId == nil && type == nil }
}

/// The JSON a saved filter stores (same shape on Android and in the RN app).
struct FilterPayload: Codable, Equatable {
  struct Filters: Codable, Equatable {
    var monthOffset: Int?
    var accountIds: [String] = []
    var categoryIds: [String] = []
    var types: [String] = []
  }
  var filters = Filters()
  var search = ""

  init(_ f: ActivityFilter, search: String) {
    filters = Filters(monthOffset: f.monthOffset == 0 ? nil : f.monthOffset, accountIds: f.accountId.map { [$0] } ?? [],
                      categoryIds: f.categoryId.map { [$0] } ?? [], types: f.type.map { [$0.rawValue] } ?? [])
    self.search = search
  }

  static func parse(_ json: String) -> FilterPayload? {
    json.data(using: .utf8).flatMap { try? JSONDecoder().decode(FilterPayload.self, from: $0) }
  }
  var json: String { (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}" }

  var filter: ActivityFilter {
    ActivityFilter(monthOffset: filters.monthOffset ?? 0, accountId: filters.accountIds.first,
                   categoryId: filters.categoryIds.first, type: filters.types.first.flatMap(TxnType.init(rawValue:)))
  }
}

struct ActivityView: View {
  @Query(filter: #Predicate<Txn> { $0.deletedAt == nil }, sort: \Txn.occurredAt, order: .reverse) private var txns: [Txn]
  @Query(sort: \Account.sortOrder) private var accounts: [Account]
  @Query(sort: \Category.sortOrder) private var categories: [Category]
  @Query(sort: \SavedFilter.sortOrder) private var saved: [SavedFilter]
  @AppStorage(PrefKey.monthStartDay, store: AppGroup.defaults) private var monthStartDay = 1
  @Environment(\.modelContext) private var context
  @Environment(Router.self) private var router
  @State private var filter = ActivityFilter()
  @State private var query = ""
  @State private var selecting = false
  @State private var selection = Set<String>()
  @State private var naming: SavedFilter?
  @State private var savingNew = false
  @State private var filterName = ""

  var body: some View {
    let lookups = Lookups(accounts: accounts, categories: categories)
    let range = Periods.month(offset: filter.monthOffset, startDay: monthStartDay)
    let rows = txns.filter { keep($0, range: range, lookups: lookups) }
    let days = Dictionary(grouping: rows) { Calendar.current.startOfDay(for: $0.occurredAt) }.sorted { $0.key > $1.key }
    let summary = Ledger.summary(rows, in: range)
    let current = FilterPayload(filter, search: query)

    List(selection: $selection) {
      if !saved.isEmpty {
        Section {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
              ForEach(saved) { f in
                let on = FilterPayload.parse(f.filters) == current
                Button {
                  if on { filter = ActivityFilter(monthOffset: filter.monthOffset); query = "" }
                  else if let p = FilterPayload.parse(f.filters) { filter = p.filter; query = p.search }
                } label: {
                  Label(f.name, systemImage: on ? "bookmark.fill" : "bookmark")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .foregroundStyle(on ? Color.white : Color.primary)
                    .background(on ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.pressable)
                .contextMenu {
                  Button { f.filters = current.json; f.updatedAt = .now; try? context.save(); router.show("Updated \(f.name)") } label: {
                    Label("Update to Current Filters", systemImage: "arrow.triangle.2.circlepath")
                  }
                  Button { filterName = f.name; naming = f } label: { Label("Rename", systemImage: "pencil") }
                  Button(role: .destructive) { context.delete(f); try? context.save() } label: { Label("Delete", systemImage: "trash") }
                }
              }
            }
            .padding(.horizontal, 16)
          }
          .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
          .listRowBackground(Color.clear)
        }
      }
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
            if selecting {
              TxnRow(txn: t, lookups: lookups).tag(t.id)
            } else {
              NavigationLink(value: t) { TxnRow(txn: t, lookups: lookups) }.txnActions(t)
            }
          }
        } header: {
          DayHeader(date: day, total: items.filter { $0.type == .expense }.reduce(0) { $0 + $1.effectiveAmount })
        }
      }
    }
    .environment(\.editMode, .constant(selecting ? .active : .inactive))
    .navigationTitle(selecting ? (selection.isEmpty ? "Select" : "\(selection.count) selected") : "Activity")
    .navigationBarTitleDisplayMode(selecting ? .inline : .automatic)
    .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Payee, note, category, amount")
    .navigationDestination(for: Txn.self) { TransactionDetailView(txn: $0) }
    .onChange(of: selecting) { _, on in router.hideTabBar = on }
    .onDisappear { router.hideTabBar = false }
    .toolbar {
      if selecting {
        ToolbarItem(placement: .topBarLeading) {
          Button(selection.count == rows.count ? "Deselect All" : "Select All") {
            selection = selection.count == rows.count ? [] : Set(rows.map(\.id))
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { selecting = false; selection = [] }.fontWeight(.semibold)
        }
        ToolbarItemGroup(placement: .bottomBar) { bulkBar(lookups) }
      } else {
        ToolbarItemGroup(placement: .topBarLeading) {
          Button { filter.monthOffset -= 1 } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous month")
          Text(Periods.label(range, startDay: monthStartDay)).font(.subheadline.weight(.semibold)).fixedSize()
          Button { filter.monthOffset += 1 } label: { Image(systemName: "chevron.right") }
            .disabled(filter.monthOffset >= 0).accessibilityLabel("Next month")
        }
        ToolbarItem(placement: .topBarTrailing) { filterMenu(lookups, canSave: !filter.isDefault || !query.isEmpty) }
      }
    }
    .alert("Save Filter", isPresented: $savingNew) {
      TextField("Name", text: $filterName)
      Button("Cancel", role: .cancel) {}
      Button("Save") {
        let name = filterName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        context.insert(SavedFilter(name: name, filters: current.json, sortOrder: (saved.map(\.sortOrder).max() ?? -1) + 1))
        try? context.save()
      }
    } message: { Text("It shows as a chip above your transactions.") }
    .alert("Rename Filter", isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
      TextField("Name", text: $filterName)
      Button("Cancel", role: .cancel) {}
      Button("Save") {
        let name = filterName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { naming?.name = name; naming?.updatedAt = .now; try? context.save() }
      }
    }
  }

  @ViewBuilder private func bulkBar(_ lookups: Lookups) -> some View {
    let chosen = txns.filter { selection.contains($0.id) }
    Menu {
      Button("Uncategorised") { bulk(chosen, "Category changed") { $0.categoryId = nil } }
      ForEach(categories.filter { $0.parentId == nil && $0.archivedAt == nil }) { c in
        Button { bulk(chosen.filter { $0.type != .transfer }, "Moved to \(c.name)") { $0.categoryId = c.id } } label: { Label(c.name, systemImage: c.icon) }
      }
    } label: { Label("Category", systemImage: "square.grid.2x2") }
    .disabled(chosen.isEmpty)
    Spacer()
    Menu {
      ForEach(accounts.filter { $0.archivedAt == nil }) { a in
        Button { bulk(chosen, "Moved to \(a.name)") { $0.accountId = a.id } } label: { Label(a.name, systemImage: a.icon) }
      }
    } label: { Label("Account", systemImage: "building.columns") }
    .disabled(chosen.isEmpty)
    Spacer()
    Button(role: .destructive) { bulk(chosen, "Deleted \(chosen.count)") { $0.deletedAt = .now } } label: {
      Label("Delete", systemImage: "trash")
    }
    .disabled(chosen.isEmpty)
  }

  /// Applies a change to every selected transaction; one Undo puts them all back.
  private func bulk(_ items: [Txn], _ message: String, _ change: (Txn) -> Void) {
    let before = items.map { ($0, $0.categoryId, $0.accountId, $0.deletedAt) }
    items.forEach { change($0); $0.updatedAt = .now }
    try? context.save()
    WidgetRefresh.now()
    selecting = false; selection = []
    router.show(message) {
      for (t, c, a, d) in before { t.categoryId = c; t.accountId = a; t.deletedAt = d }
      try? context.save()
      WidgetRefresh.now()
    }
  }

  private func keep(_ t: Txn, range: DateInterval, lookups: Lookups) -> Bool {
    guard range.contains(t.occurredAt) else { return false }
    if let a = filter.accountId, t.accountId != a, t.toAccountId != a { return false }
    if let c = filter.categoryId, t.categoryId != c, Ledger.topLevel(t.categoryId, lookups.categories) != c { return false }
    if let type = filter.type, t.type != type { return false }
    return Search.matches(t, query, lookups)
  }

  private func filterMenu(_ lookups: Lookups, canSave: Bool) -> some View {
    Menu {
      Button { selecting = true } label: { Label("Select", systemImage: "checkmark.circle") }
      if canSave {
        Button { filterName = ""; savingNew = true } label: { Label("Save Current Filter…", systemImage: "bookmark") }
      }
      Divider()
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
    if q.hasPrefix("#") { return t.tags.contains { $0.hasPrefix(String(q.dropFirst())) } }
    let fields = [t.payee, t.note, t.categoryId.flatMap { l.categories[$0]?.name }, l.accounts[t.accountId]?.name] + t.tags.map { Optional($0) }
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
