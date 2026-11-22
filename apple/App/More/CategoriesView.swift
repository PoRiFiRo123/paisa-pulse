import SwiftData
import SwiftUI

struct CategoriesView: View {
  @Query(sort: \Category.sortOrder) private var categories: [Category]
  @State private var kind: CategoryKind = .expense
  @State private var editing: Category?
  @State private var adding = false

  var body: some View {
    List {
      Picker("Kind", selection: $kind) {
        Text("Expense").tag(CategoryKind.expense)
        Text("Income").tag(CategoryKind.income)
      }
      .pickerStyle(.segmented)
      .listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets())

      ForEach(categories.filter { $0.kind == kind && $0.parentId == nil && $0.archivedAt == nil }) { parent in
        Section {
          row(parent)
          ForEach(categories.filter { $0.parentId == parent.id && $0.archivedAt == nil }) { row($0, child: true) }
        }
      }
      let archived = categories.filter { $0.kind == kind && $0.archivedAt != nil }
      if !archived.isEmpty {
        Section("Hidden") { ForEach(archived) { row($0) } }
      }
    }
    .navigationTitle("Categories")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") } }
    }
    .sheet(item: $editing) { c in NavigationStack { CategoryFormView(category: c, kind: c.kind) } }
    .sheet(isPresented: $adding) { NavigationStack { CategoryFormView(category: nil, kind: kind) } }
  }

  private func row(_ c: Category, child: Bool = false) -> some View {
    Button { editing = c } label: {
      HStack {
        CategoryBadge(icon: c.icon, color: c.color, size: child ? 26 : 32)
        Text(c.name).foregroundStyle(.primary)
        Spacer()
        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
      }
      .padding(.leading, child ? 20 : 0)
    }
  }
}

struct CategoryFormView: View {
  let category: Category?
  let kind: CategoryKind
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @Query(sort: \Category.sortOrder) private var all: [Category]
  @State private var name = ""
  @State private var icon = "tag.fill"
  @State private var color = "#5E5CE6"
  @State private var parentId: String?

  static let icons = [
    "fork.knife", "cart.fill", "car.fill", "fuelpump.fill", "tram.fill", "bag.fill", "doc.text.fill", "bolt.fill",
    "wifi", "tv.fill", "house.fill", "building.columns.fill", "cross.case.fill", "popcorn.fill", "repeat.circle.fill",
    "airplane", "graduationcap.fill", "gift.fill", "chart.line.uptrend.xyaxis", "sparkles", "pawprint.fill",
    "figure.2.and.child.holdinghands", "gamecontroller.fill", "dumbbell.fill", "cup.and.saucer.fill", "wineglass.fill",
    "tshirt.fill", "iphone", "wrench.and.screwdriver.fill", "book.fill", "music.note", "heart.fill", "leaf.fill",
    "scooter", "bicycle", "bus.fill", "banknote.fill", "laptopcomputer", "percent", "indianrupeesign.circle.fill",
    "tag.fill", "star.fill",
  ]

  var body: some View {
    Form {
      Section {
        HStack {
          CategoryBadge(icon: icon, color: color, size: 44)
          TextField("Name", text: $name).font(.title3)
        }
        Picker("Inside", selection: $parentId) {
          Text("None (main category)").tag(String?.none)
          ForEach(all.filter { $0.kind == kind && $0.parentId == nil && $0.id != category?.id }) { Text($0.name).tag(String?.some($0.id)) }
        }
      }
      Section("Colour") { ColorRow(selection: $color) }
      Section("Icon") {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 14) {
          ForEach(Self.icons, id: \.self) { name in
            Image(systemName: name)
              .font(.title3)
              .frame(width: 40, height: 40)
              .foregroundStyle(icon == name ? .white : .primary)
              .background(icon == name ? Color(hex: color) : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
              .onTapGesture { icon = name }
          }
        }
        .padding(.vertical, 6)
      }
      if let c = category {
        Section {
          Button(c.archivedAt == nil ? "Hide Category" : "Show Category") {
            c.archivedAt = c.archivedAt == nil ? .now : nil
            try? context.save(); dismiss()
          }
        } footer: { Text("Hidden categories keep their past transactions.") }
      }
    }
    .navigationTitle(category == nil ? "New Category" : "Edit Category")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
    }
    .onAppear {
      if let c = category { name = c.name; icon = c.icon; color = c.color; parentId = c.parentId }
    }
  }

  private func save() {
    let c = category ?? Category(kind: kind, name: name, icon: icon, color: color, sortOrder: all.count)
    c.name = name.trimmingCharacters(in: .whitespaces); c.icon = icon; c.color = color; c.parentId = parentId; c.updatedAt = .now
    if category == nil { context.insert(c) }
    try? context.save()
    dismiss()
  }
}

struct BudgetsView: View {
  @Query private var budgets: [Budget]
  @Query(filter: #Predicate<Txn> { $0.deletedAt == nil }) private var txns: [Txn]
  @Query private var accounts: [Account]
  @Query(sort: \Category.sortOrder) private var categories: [Category]
  @Environment(\.modelContext) private var context
  @AppStorage(PrefKey.monthStartDay, store: AppGroup.defaults) private var monthStartDay = 1
  @AppStorage(PrefKey.weekStartDay, store: AppGroup.defaults) private var weekStartDay = 2
  @State private var editing: Budget?
  @State private var adding = false

  var body: some View {
    let lookups = Lookups(accounts: accounts, categories: categories)
    let progress = Budgets.progress(budgets, txns: txns, categories: lookups.categories,
                                    month: Periods.month(containing: .now, startDay: monthStartDay),
                                    week: Periods.week(containing: .now, firstWeekday: weekStartDay))
    List {
      if progress.isEmpty {
        EmptyHint(title: "No budgets", icon: "gauge.with.dots.needle.33percent",
                  message: "Set a monthly limit for everything or for one category. You'll get a nudge at 80%.")
      }
      ForEach(progress) { p in
        Button { editing = p.budget } label: { BudgetRow(progress: p, lookups: lookups).foregroundStyle(.primary) }
          .swipeActions {
            Button(role: .destructive) { context.delete(p.budget); try? context.save() } label: { Label("Delete", systemImage: "trash") }
          }
      }
    }
    .navigationTitle("Budgets")
    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") } } }
    .sheet(item: $editing) { b in NavigationStack { BudgetFormView(budget: b) } }
    .sheet(isPresented: $adding) { NavigationStack { BudgetFormView(budget: nil) } }
  }
}

struct BudgetFormView: View {
  let budget: Budget?
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @Query(filter: #Predicate<Category> { $0.archivedAt == nil }, sort: \Category.sortOrder) private var categories: [Category]
  @State private var categoryId: String?
  @State private var period = "monthly"
  @State private var amount = ""

  var body: some View {
    Form {
      Picker("For", selection: $categoryId) {
        Text("Everything").tag(String?.none)
        ForEach(categories.filter { $0.kind == .expense && $0.parentId == nil }) { Text($0.name).tag(String?.some($0.id)) }
      }
      Picker("Every", selection: $period) {
        Text("Month").tag("monthly")
        Text("Week").tag("weekly")
      }
      .pickerStyle(.segmented)
      TextField("Limit, e.g. 20000", text: $amount).keyboardType(.decimalPad)
    }
    .navigationTitle(budget == nil ? "New Budget" : "Edit Budget")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          guard let p = Money.parse(amount) else { return }
          let b = budget ?? Budget(categoryId: categoryId, period: period, amount: p)
          b.categoryId = categoryId; b.period = period; b.amount = p; b.updatedAt = .now
          if budget == nil { context.insert(b) }
          try? context.save(); dismiss()
        }
        .disabled(Money.parse(amount) == nil)
      }
    }
    .onAppear {
      if let b = budget { categoryId = b.categoryId; period = b.period; amount = String(b.amount / 100) }
    }
  }
}

struct RecurringView: View {
  @Query(sort: \RecurringRule.nextAt) private var rules: [RecurringRule]
  @Query private var accounts: [Account]
  @Query private var categories: [Category]
  @Environment(\.modelContext) private var context
  @State private var adding = false

  var body: some View {
    let lookups = Lookups(accounts: accounts, categories: categories)
    List {
      if rules.isEmpty {
        EmptyHint(title: "Nothing repeats yet", icon: "repeat", message: "Rent, SIPs, subscriptions: add them once and they log themselves.")
      }
      ForEach(rules) { r in
        NavigationLink { RecurringFormView(rule: r) } label: {
          HStack {
            let c = r.categoryId.flatMap { lookups.categories[$0] }
            CategoryBadge(icon: c?.icon ?? "repeat", color: c?.color ?? "#8E8E93")
            VStack(alignment: .leading, spacing: 2) {
              Text(r.payee ?? c?.name ?? "Recurring")
              Text(r.pausedAt != nil ? "Paused" : "Every \(r.interval > 1 ? "\(r.interval) " : "")\(r.frequency.noun)\(r.interval > 1 ? "s" : "") · next \(r.nextAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            AmountText(amount: r.amount, type: r.type)
          }
        }
        .swipeActions {
          Button(role: .destructive) { context.delete(r); try? context.save() } label: { Label("Delete", systemImage: "trash") }
          Button { r.pausedAt = r.pausedAt == nil ? .now : nil; try? context.save() } label: {
            Label(r.pausedAt == nil ? "Pause" : "Resume", systemImage: r.pausedAt == nil ? "pause" : "play")
          }
          .tint(.orange)
        }
      }
    }
    .navigationTitle("Recurring")
    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") } } }
    .sheet(isPresented: $adding) { NavigationStack { RecurringFormView() } }
  }
}

struct RecurringFormView: View {
  var rule: RecurringRule? = nil
  var from: Txn? = nil
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @Query(filter: #Predicate<Account> { $0.archivedAt == nil }, sort: \Account.sortOrder) private var accounts: [Account]
  @Query(filter: #Predicate<Category> { $0.archivedAt == nil }, sort: \Category.sortOrder) private var categories: [Category]
  @State private var type: TxnType = .expense
  @State private var amount = ""
  @State private var payee = ""
  @State private var accountId: String?
  @State private var toAccountId: String?
  @State private var categoryId: String?
  @State private var frequency: Frequency = .monthly
  @State private var interval = 1
  @State private var start = Date.now
  @State private var hasEnd = false
  @State private var end = Date.now.addingTimeInterval(365 * 86_400)

  var body: some View {
    Form {
      Section {
        Picker("Type", selection: $type) { ForEach(TxnType.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
        TextField("Amount", text: $amount).keyboardType(.decimalPad)
        TextField("Payee, e.g. Rent", text: $payee)
        Picker(type == .transfer ? "From" : "Account", selection: $accountId) {
          ForEach(accounts) { Text($0.displayName).tag(String?.some($0.id)) }
        }
        if type == .transfer {
          Picker("To", selection: $toAccountId) {
            Text("Choose").tag(String?.none)
            ForEach(accounts.filter { $0.id != accountId }) { Text($0.displayName).tag(String?.some($0.id)) }
          }
        } else {
          Picker("Category", selection: $categoryId) {
            Text("Uncategorised").tag(String?.none)
            ForEach(categories.filter { $0.kind == (type == .income ? .income : .expense) }) { Text($0.name).tag(String?.some($0.id)) }
          }
        }
      }
      Section("Repeats") {
        Picker("Every", selection: $frequency) { ForEach(Frequency.allCases) { Text($0.noun.capitalized).tag($0) } }
        Stepper("Every \(interval) \(frequency.noun)\(interval > 1 ? "s" : "")", value: $interval, in: 1...12)
        DatePicker("Starts", selection: $start, displayedComponents: .date)
        Toggle("Ends", isOn: $hasEnd)
        if hasEnd { DatePicker("End date", selection: $end, displayedComponents: .date) }
      }
    }
    .navigationTitle(rule == nil ? "Repeat" : "Edit Recurring")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(Money.parse(amount) == nil || accountId == nil) }
    }
    .onAppear(perform: load)
  }

  private func load() {
    if let r = rule {
      type = r.type; amount = String(Double(r.amount) / 100); payee = r.payee ?? ""; accountId = r.accountId
      toAccountId = r.toAccountId; categoryId = r.categoryId; frequency = r.frequency; interval = r.interval
      start = r.startAt; hasEnd = r.endAt != nil; end = r.endAt ?? end
    } else if let t = from {
      type = t.type; amount = String(Double(t.amount) / 100); payee = t.payee ?? ""; accountId = t.accountId
      toAccountId = t.toAccountId; categoryId = t.categoryId
      start = Calendar.current.date(byAdding: .month, value: 1, to: t.occurredAt) ?? .now
    } else {
      accountId = accounts.first?.id
    }
  }

  private func save() {
    guard let p = Money.parse(amount), let accountId else { return }
    let r = rule ?? RecurringRule(type: type, amount: p, accountId: accountId, frequency: frequency, startAt: start)
    r.typeRaw = type.rawValue; r.amount = p; r.accountId = accountId
    r.toAccountId = type == .transfer ? toAccountId : nil; r.categoryId = type == .transfer ? nil : categoryId
    r.payee = payee.isEmpty ? nil : payee; r.frequency = frequency; r.interval = interval
    if rule == nil || rule?.startAt != start { r.startAt = start; r.nextAt = start }
    r.endAt = hasEnd ? end : nil; r.updatedAt = .now
    if rule == nil { context.insert(r) }
    if let t = from { t.recurringId = r.id; if r.nextAt <= t.occurredAt { r.nextAt = Recurrence.next(after: t.occurredAt, rule: r) } }
    try? context.save()
    Maintenance.run(context)
    dismiss()
  }
}
