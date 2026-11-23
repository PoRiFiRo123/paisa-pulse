import SwiftData
import SwiftUI

// Planning: trips and any planned event. Same screens on Android (ui/screens/Planning.kt).

/// Planning home: what's coming up, what's on, and everything you've planned.
struct PlanningView: View {
  @Query(sort: \Trip.createdAt, order: .reverse) private var trips: [Trip]
  @Query private var items: [TripItem]
  @Query private var wallets: [TripWallet]
  @Query(filter: #Predicate<Txn> { $0.deletedAt == nil }) private var txns: [Txn]
  @State private var creating: TripKinds.Kind?
  @State private var filter = "all"
  @State private var region = "any"
  @AppStorage(PrefKey.hideAmounts, store: AppGroup.defaults) private var hidden = false

  var body: some View {
    let live = trips.filter { $0.archivedAt == nil }
    let summaries = live.map { TripMath.summary($0, items: items, wallets: wallets, txns: txns) }
    let o = TripMath.overview(summaries)
    let shown = summaries.filter { s in
      (filter == "all" || (filter == "over" ? s.overBudget : s.status.rawValue == filter))
        && (region == "any" || (region == "international") == s.trip.international)
    }
    .sorted { a, b in
      let rank: (TripMath.Status) -> Int = { $0 == .ongoing ? 0 : $0 == .upcoming ? 1 : 2 }
      if rank(a.status) != rank(b.status) { return rank(a.status) < rank(b.status) }
      return (a.trip.startAt ?? a.trip.createdAt) > (b.trip.startAt ?? b.trip.createdAt)
    }
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
          GridRow {
            kpi("Upcoming", "\(o.upcoming)", "calendar.badge.clock", "#2563EB")
            kpi("Happening now", "\(o.ongoing)", "location.fill", "#16A34A")
          }
          GridRow {
            kpi("Planned budget", Money.compact(o.planned, hidden: hidden), "target", "#0891B2")
            kpi("Over budget", "\(o.overBudget)", "exclamationmark.triangle.fill", o.overBudget > 0 ? "#E5484D" : "#8E8E93")
          }
        }

        VStack(alignment: .leading, spacing: 10) {
          Text("Plan something new").font(.title3.weight(.bold))
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
              ForEach(TripKinds.all) { k in
                Button { creating = k } label: {
                  VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: k.icon).font(.title2.weight(.semibold))
                    Text(k.label).font(.subheadline.weight(.semibold)).lineLimit(1)
                  }
                  .foregroundStyle(.white)
                  .frame(width: 112, height: 96, alignment: .topLeading)
                  .padding(14)
                  .background(LinearGradient(colors: [Color(hex: k.color), Color(hex: k.color).opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing),
                              in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New \(k.label)")
              }
            }
            .padding(.horizontal, 2)
          }
          .scrollClipDisabled()
        }

        if !live.isEmpty {
          VStack(alignment: .leading, spacing: 10) {
            HStack {
              Text("Your plans").font(.title3.weight(.bold))
              Spacer()
              Menu {
                Picker("Where", selection: $region) {
                  Text("Anywhere").tag("any"); Text("Domestic").tag("domestic"); Text("International").tag("international")
                }
              } label: { Label(region == "any" ? "Anywhere" : region.capitalized, systemImage: "line.3.horizontal.decrease.circle").font(.subheadline) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 8) {
                ForEach([("all", "All"), ("ongoing", "Now"), ("upcoming", "Upcoming"), ("completed", "Done"), ("over", "Over budget")], id: \.0) { key, label in
                  Button { withAnimation(.snappy) { filter = key } } label: {
                    Text(label).font(.subheadline.weight(.medium)).padding(.vertical, 7).padding(.horizontal, 14)
                      .foregroundStyle(filter == key ? .white : .primary)
                      .background(filter == key ? Color.accentColor : Color(.tertiarySystemFill), in: Capsule())
                  }
                  .buttonStyle(.plain)
                }
              }
            }
            if shown.isEmpty {
              Text("Nothing here with these filters.").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 20).frame(maxWidth: .infinity)
            }
            ForEach(shown, id: \.trip.id) { s in
              NavigationLink { TripDetailView(trip: s.trip) } label: { TripCard(summary: s, hidden: hidden) }.buttonStyle(.plain)
            }
          }
        } else {
          EmptyHint(title: "Plan your first trip", icon: "airplane.departure",
                    message: "Pick a type above. Set a budget for each part, track cash or forex you carry, and split with friends.")
            .frame(maxWidth: .infinity).padding(.top, 20)
        }
        let archived = trips.filter { $0.archivedAt != nil }
        if !archived.isEmpty {
          NavigationLink { ArchivedTripsView() } label: {
            Label("Archived (\(archived.count))", systemImage: "archivebox").font(.subheadline).frame(maxWidth: .infinity)
          }
        }
      }
      .padding()
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle("Planning")
    .sheet(item: $creating) { k in NavigationStack { TripFormView(kind: k.id) } }
  }

  private func kpi(_ label: String, _ value: String, _ icon: String, _ color: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Image(systemName: icon).font(.headline).foregroundStyle(Color(hex: color))
      Text(value).font(.title2.weight(.bold)).fontDesign(.rounded).lineLimit(1).minimumScaleFactor(0.6)
      Text(label).font(.caption).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }
}

struct ArchivedTripsView: View {
  @Query(filter: #Predicate<Trip> { $0.archivedAt != nil }, sort: \Trip.createdAt, order: .reverse) private var trips: [Trip]
  var body: some View {
    List(trips) { t in NavigationLink(t.name) { TripDetailView(trip: t) } }.navigationTitle("Archived")
  }
}

/// "In 12 days" / "Day 3 of 5" / "Done" for a trip.
func tripStatusText(_ s: TripMath.Summary) -> String {
  switch s.status {
  case .upcoming: return s.daysToGo.map { $0 == 0 ? "Starts today" : $0 == 1 ? "Tomorrow" : "In \($0) days" } ?? "Upcoming"
  case .ongoing: return s.day.map { d in s.days.map { "Day \(d) of \($0)" } ?? "Day \(d)" } ?? "Happening now"
  case .completed: return s.trip.startAt == nil ? "Logged" : "Done"
  }
}

func tripDates(_ t: Trip) -> String? {
  guard let s = t.startAt else { return nil }
  let e = t.endAt ?? s
  if Calendar.current.isDate(s, inSameDayAs: e) { return s.formatted(.dateTime.day().month(.abbreviated).year()) }
  return "\(s.formatted(.dateTime.day().month(.abbreviated))) – \(e.formatted(.dateTime.day().month(.abbreviated).year()))"
}

/// A trip in a list: coloured header, status, budget progress.
struct TripCard: View {
  let summary: TripMath.Summary
  var hidden = false
  var body: some View {
    let t = summary.trip
    let k = TripKinds.of(t.kind)
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top) {
        Image(systemName: k.icon).font(.headline).foregroundStyle(.white)
          .frame(width: 40, height: 40).background(Color(hex: k.color), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        VStack(alignment: .leading, spacing: 2) {
          Text(t.name).font(.headline).lineLimit(1)
          Text([tripDates(t), t.places.isEmpty ? nil : t.places.map(\.name).joined(separator: ", ")].compactMap { $0 }.joined(separator: " · "))
            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        Spacer()
        Text(tripStatusText(summary)).font(.caption.weight(.semibold)).padding(.vertical, 4).padding(.horizontal, 8)
          .foregroundStyle(summary.status == .ongoing ? Color.income : summary.status == .upcoming ? Color.accentColor : .secondary)
          .background((summary.status == .ongoing ? Color.income : summary.status == .upcoming ? Color.accentColor : Color.secondary).opacity(0.12), in: Capsule())
      }
      HStack(alignment: .firstTextBaseline) {
        Text(Money.format(summary.spent, hidden: hidden)).font(.title3.weight(.bold)).fontDesign(.rounded)
        if summary.budget > 0 { Text("of \(Money.format(summary.budget, hidden: hidden))").font(.subheadline).foregroundStyle(.secondary) }
        Spacer()
        if t.international { Image(systemName: "globe.asia.australia.fill").foregroundStyle(.secondary) }
      }
      if summary.budget > 0 { BudgetBar(progress: summary.progress) }
    }
    .padding(16)
    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    .accessibilityElement(children: .combine)
  }
}

/// Green under 80%, amber to 100%, red over.
struct BudgetBar: View {
  let progress: Double
  var height: CGFloat = 8
  var body: some View {
    let color: Color = progress > 1 ? .expense : progress >= 0.8 ? .orange : .income
    GeometryReader { g in
      ZStack(alignment: .leading) {
        Capsule().fill(Color(.tertiarySystemFill))
        Capsule().fill(color).frame(width: max(height, g.size.width * min(progress, 1)))
      }
    }
    .frame(height: height)
    .animation(.spring, value: progress)
  }
}

// MARK: - Create / edit

struct TripFormView: View {
  var kind: String = "trip"
  var trip: Trip?
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @Query(sort: \Friend.name) private var friends: [Friend]
  @Query private var groups: [SplitGroup]
  @Query private var allItems: [TripItem]

  @State private var kindId = "trip"
  @State private var name = ""
  @State private var international = false
  @State private var places: [TripPlace] = []
  @State private var newPlace = ""
  @State private var hasDates = true
  @State private var start = Calendar.current.startOfDay(for: .now)
  @State private var end = Calendar.current.date(byAdding: .day, value: 3, to: Calendar.current.startOfDay(for: .now))!
  @State private var travellers = 1
  @State private var people: [String] = []
  @State private var newPerson = ""
  @State private var budgetOn = true
  @State private var countInBudgets = true
  struct ItemRow: Identifiable { var id: String; var label: String; var budget: String }
  @State private var items: [ItemRow] = []
  @State private var newItem = ""
  @State private var notes = ""
  @State private var pickingCountry = false
  @State private var loaded = false

  var body: some View {
    let k = TripKinds.of(kindId)
    Form {
      Section {
        HStack(spacing: 12) {
          Image(systemName: k.icon).font(.title3).foregroundStyle(.white)
            .frame(width: 44, height: 44).background(Color(hex: k.color), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
          TextField(k.places ? "Name, e.g. Goa with college gang" : "Name, e.g. Ananya's wedding", text: $name).font(.headline)
        }
        Picker("Type", selection: $kindId) { ForEach(TripKinds.all) { Label($0.label, systemImage: $0.icon).tag($0.id) } }
      }

      if k.places {
        Section {
          Picker("Where", selection: $international) { Text("In India").tag(false); Text("Abroad").tag(true) }.pickerStyle(.segmented)
          ForEach(places, id: \.self) { p in
            HStack {
              Image(systemName: international ? "globe" : "mappin.and.ellipse").foregroundStyle(.secondary)
              Text(p.name)
              Spacer()
              if let c = p.currency { Text("\(World.symbol(c)) \(c)").font(.subheadline).foregroundStyle(.secondary) }
            }
          }
          .onDelete { places.remove(atOffsets: $0) }
          if international {
            Button { pickingCountry = true } label: { Label("Add a Country", systemImage: "plus.circle.fill") }
          } else {
            HStack {
              TextField("Add a place (Goa, Coorg…)", text: $newPlace).onSubmit(addPlace)
              Button("Add", action: addPlace).disabled(newPlace.trimmingCharacters(in: .whitespaces).isEmpty)
            }
          }
        } header: { Text("Destinations") } footer: {
          if international { Text("Each country sets its currency, so spends there can be entered in it.") }
        }
      }

      Section {
        if !k.dated { Toggle("Has dates", isOn: $hasDates) }
        if k.dated || hasDates {
          DatePicker("From", selection: $start, displayedComponents: .date)
          DatePicker("To", selection: $end, in: start..., displayedComponents: .date)
        }
        Stepper("People: \(travellers)", value: $travellers, in: 1...50)
      } header: { Text("When") }

      Section {
        ForEach(friends) { f in
          Button {
            if people.contains(f.id) { people.removeAll { $0 == f.id } } else { people.append(f.id) }
            travellers = max(travellers, people.count + 1)
          } label: {
            HStack {
              Image(systemName: people.contains(f.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(people.contains(f.id) ? Color.accentColor : .secondary)
              Avatar(name: f.name, size: 28)
              Text(f.name).foregroundStyle(.primary)
            }
          }
        }
        HStack {
          TextField("Add someone by name", text: $newPerson).onSubmit(addPerson)
          Button("Add", action: addPerson).disabled(newPerson.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      } header: { Text("Who's going") } footer: {
        Text("They become a split group, so you can split expenses and settle up at the end. Friends linked to Paisa Pulse see the trip and its shared expenses on their phone.")
      }

      Section {
        Toggle("Plan a budget", isOn: $budgetOn.animation())
        if budgetOn {
          ForEach($items, id: \.id) { $item in
            HStack {
              TextField("Item", text: $item.label)
              TextField("\(Money.symbol)0", text: $item.budget).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 110)
            }
          }
          .onDelete { items.remove(atOffsets: $0) }
          .onMove { items.move(fromOffsets: $0, toOffset: $1) }
          HStack {
            TextField("Add an item", text: $newItem).onSubmit(addItem)
            Button("Add", action: addItem).disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
          }
          let total = items.reduce(0) { $0 + (Money.parse($1.budget) ?? 0) }
          LabeledContent("Total budget") { Text(Money.format(total)).fontWeight(.semibold) }
        }
        Toggle("Count in monthly budgets", isOn: $countInBudgets)
      } header: { Text("Budget") } footer: {
        Text("Switch off to keep this trip's spending out of your monthly budgets (it still counts in totals and Insights).")
      }

      Section("Notes") { TextField("Bookings, ideas…", text: $notes, axis: .vertical).lineLimit(2...6) }
    }
    .navigationTitle(trip == nil ? "New \(k.label)" : "Edit")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).fontWeight(.semibold).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
    }
    .sheet(isPresented: $pickingCountry) { CountryPickerSheet { c in places.append(TripPlace(name: c.name, country: c.name, currency: c.currency)) } }
    .onAppear(perform: load)
    .onChange(of: kindId) { _, _ in if trip == nil { resetItems() } }
    .onChange(of: international) { _, _ in if trip == nil { resetItems() }; places = [] }
  }

  private func resetItems() {
    items = TripKinds.items(kindId, international: international).map { ItemRow(id: UUID().uuidString.lowercased(), label: $0, budget: "") }
  }
  private func addPlace() {
    let n = newPlace.trimmingCharacters(in: .whitespaces); guard !n.isEmpty else { return }
    places.append(TripPlace(name: n)); newPlace = ""
  }
  private func addItem() {
    let n = newItem.trimmingCharacters(in: .whitespaces); guard !n.isEmpty else { return }
    items.append(ItemRow(id: UUID().uuidString.lowercased(), label: n, budget: "")); newItem = ""
  }
  private func addPerson() {
    let n = newPerson.trimmingCharacters(in: .whitespaces); guard !n.isEmpty else { return }
    let f = Friend(name: n); context.insert(f); people.append(f.id); newPerson = ""
    travellers = max(travellers, people.count + 1)
  }

  private func load() {
    guard !loaded else { return }; loaded = true
    guard let t = trip else { kindId = kind; resetItems(); return }
    kindId = t.kind; name = t.name; international = t.international; places = t.places
    hasDates = t.startAt != nil; start = t.startAt ?? start; end = t.endAt ?? t.startAt ?? end
    travellers = t.travellers; budgetOn = t.budgetEnabled; countInBudgets = t.countInBudgets; notes = t.notes ?? ""
    people = t.groupId.flatMap { id in groups.first { $0.id == id } }?.memberIds ?? []
    items = allItems.filter { $0.tripId == t.id }.sorted { $0.sortOrder < $1.sortOrder }
      .map { ItemRow(id: $0.id, label: $0.label, budget: $0.budget.map { String($0 / 100) } ?? "") }
  }

  private func save() {
    let k = TripKinds.of(kindId)
    let t = trip ?? Trip(name: name)
    t.name = name.trimmingCharacters(in: .whitespaces); t.kind = kindId
    t.international = k.places && international; t.places = k.places ? places : []
    let dated = k.dated || hasDates
    t.startAt = dated ? Calendar.current.startOfDay(for: start) : nil
    t.endAt = dated ? Calendar.current.startOfDay(for: max(start, end)) : nil
    t.travellers = max(travellers, people.count + 1); t.budgetEnabled = budgetOn; t.countInBudgets = countInBudgets
    t.notes = notes.nilIfEmpty; t.updatedAt = .now
    // People → the trip's split group.
    if !people.isEmpty {
      if let g = t.groupId.flatMap({ id in groups.first { $0.id == id } }) { g.name = t.name; g.memberIds = people }
      else { let g = SplitGroup(name: t.name, memberIds: people); context.insert(g); t.groupId = g.id }
    } else if let g = t.groupId.flatMap({ id in groups.first { $0.id == id } }) { g.memberIds = [] }
    if trip == nil { context.insert(t) }
    // Budget items: keep ids so linked expenses stay linked.
    let existing = allItems.filter { $0.tripId == t.id }
    for old in existing where !items.contains(where: { $0.id == old.id }) { context.delete(old) }
    for (i, row) in items.enumerated() where !row.label.trimmingCharacters(in: .whitespaces).isEmpty {
      if let it = existing.first(where: { $0.id == row.id }) {
        it.label = row.label; it.budget = Money.parse(row.budget); it.sortOrder = i
      } else {
        context.insert(TripItem(id: row.id, tripId: t.id, label: row.label, budget: Money.parse(row.budget), sortOrder: i))
      }
    }
    try? context.save()
    dismiss()
  }
}

/// Countries with their currencies, searchable.
struct CountryPickerSheet: View {
  let onPick: (World.Country) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  var body: some View {
    NavigationStack {
      List(World.countries.filter { $0.name != "India" && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.currency.localizedCaseInsensitiveContains(query)) }, id: \.self) { c in
        Button { onPick(c); dismiss() } label: {
          HStack { Text(c.name).foregroundStyle(.primary); Spacer(); Text("\(c.symbol) \(c.currency)").foregroundStyle(.secondary) }
        }
      }
      .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Country")
      .navigationTitle("Add a Country").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }
  }
}

// MARK: - Trip page

struct TripDetailView: View {
  @Bindable var trip: Trip
  @Environment(\.modelContext) private var context
  @Environment(Router.self) private var router
  @Environment(\.dismiss) private var dismiss
  @Environment(\.displayScale) private var scale
  @Query private var items: [TripItem]
  @Query private var wallets: [TripWallet]
  @Query(filter: #Predicate<Txn> { $0.deletedAt == nil }, sort: \Txn.occurredAt, order: .reverse) private var txns: [Txn]
  @Query private var accounts: [Account]
  @Query private var categories: [Category]
  @Query private var groups: [SplitGroup]
  @Query(sort: \Friend.name) private var friends: [Friend]
  @Query private var entries: [SplitEntry]
  @State private var editing = false
  @State private var addingWallet = false
  @State private var shareImage: TripShareImage?
  @State private var confirmDelete = false
  @AppStorage(PrefKey.hideAmounts, store: AppGroup.defaults) private var hidden = false

  var body: some View {
    let s = TripMath.summary(trip, items: items, wallets: wallets, txns: txns)
    let lookups = Lookups(accounts: accounts, categories: categories)
    let k = TripKinds.of(trip.kind)
    let mine = txns.filter { $0.tripId == trip.id }
    let group = trip.groupId.flatMap { id in groups.first { $0.id == id } }
    List {
      Section {
        hero(s, k).listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
      }

      Section {
        Button { router.add = AddRequest(type: .expense, tripId: trip.id) } label: {
          Label("Add an Expense", systemImage: "plus.circle.fill").font(.headline).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent).controlSize(.large)
        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
      }

      if !s.items.isEmpty {
        Section {
          ForEach(s.items) { i in
            VStack(alignment: .leading, spacing: 6) {
              HStack {
                Text(i.item.label)
                Spacer()
                Text(Money.format(i.spent, hidden: hidden)).fontDesign(.rounded).fontWeight(.semibold)
                if let b = i.item.budget, b > 0 { Text("/ \(Money.compact(b, hidden: hidden))").font(.subheadline).foregroundStyle(.secondary) }
              }
              if let b = i.item.budget, b > 0 {
                BudgetBar(progress: Double(i.spent) / Double(b), height: 6)
                Text(i.remaining >= 0 ? "\(Money.format(i.remaining, hidden: hidden)) left" : "\(Money.format(-i.remaining, hidden: hidden)) over")
                  .font(.caption).foregroundStyle(i.remaining >= 0 ? Color.secondary : Color.expense)
              }
            }
            .padding(.vertical, 2)
          }
          if s.unassigned > 0 {
            LabeledContent("Not assigned") { Text(Money.format(s.unassigned, hidden: hidden)).fontDesign(.rounded) }
          }
        } header: { Text(trip.budgetEnabled ? "Budget" : "Spending") }
      }

      Section {
        ForEach(s.wallets) { w in
          let code = w.wallet.currency ?? Money.base
          VStack(alignment: .leading, spacing: 6) {
            HStack {
              Label(w.wallet.label, systemImage: w.wallet.currency == nil ? "banknote.fill" : "creditcard.and.123")
              Spacer()
              Text("\(Money.format(max(0, w.left), code: code, hidden: hidden)) left").fontDesign(.rounded).fontWeight(.semibold)
                .foregroundStyle(w.left < 0 ? Color.expense : .primary)
            }
            BudgetBar(progress: w.wallet.amount > 0 ? Double(w.spent) / Double(w.wallet.amount) : 0, height: 6)
            Text("Carried \(Money.format(w.wallet.amount, code: code, hidden: hidden))" + (w.wallet.currency == nil ? "" : " at \(Money.symbol)\(String(format: "%.2f", w.wallet.rate))"))
              .font(.caption).foregroundStyle(.secondary)
          }
          .swipeActions { Button("Delete", role: .destructive) { context.delete(w.wallet); try? context.save() } }
        }
        Button { addingWallet = true } label: { Label(trip.international ? "Add Cash or Forex Card" : "Add Cash You're Carrying", systemImage: "plus.circle") }
      } header: { Text("Money you carry") } footer: {
        Text("Pick it under \"Paid from\" when you add an expense to see what's left.")
      }

      if !s.byCurrency.isEmpty {
        Section("By currency") {
          ForEach(s.byCurrency.sorted { $0.value > $1.value }, id: \.key) { code, amount in
            LabeledContent(World.currencyName(code)) { Text(Money.format(amount, code: code, hidden: hidden)).fontDesign(.rounded) }
          }
        }
      }

      if let group, !group.memberIds.isEmpty {
        let balances = Splits.balances(entries.filter { $0.groupId == group.id })
        Section {
          ForEach(friends.filter { group.memberIds.contains($0.id) }) { f in
            NavigationLink { FriendDetailView(friend: f, groupId: group.id) } label: {
              HStack { Avatar(name: f.name); Text(f.name); Spacer(); BalanceLabel(balance: balances[f.id] ?? 0) }
            }
          }
          NavigationLink { GroupDetailView(group: group) } label: { Label("Settle Up", systemImage: "checkmark.circle") }
        } header: { Text("People") } footer: {
          Text("Split an expense with \"\(group.name)\" in Quick Add › Split.")
        }
      }

      TripGroupSpendingSection(tripId: trip.id)

      Section {
        if mine.isEmpty {
          Text("No expenses yet. While the trip is on, new expenses link to it on their own.").font(.subheadline).foregroundStyle(.secondary)
        }
        ForEach(mine.prefix(100)) { t in
          NavigationLink { TransactionDetailView(txn: t) } label: { TxnRow(txn: t, lookups: lookups) }.txnActions(t)
        }
      } header: { Text("Expenses (\(mine.count))") }

      if let n = trip.notes, !n.isEmpty { Section("Notes") { Text(n) } }
    }
    .navigationTitle(trip.name)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button { editing = true } label: { Label("Edit", systemImage: "pencil") }
          Button { shareImage = render(s, k).map(TripShareImage.init) } label: { Label("Share Summary", systemImage: "square.and.arrow.up") }
          Toggle(isOn: Binding(get: { trip.countInBudgets }, set: { trip.countInBudgets = $0; try? context.save() })) {
            Label("Count in Monthly Budgets", systemImage: "chart.pie")
          }
          Button {
            trip.archivedAt = trip.archivedAt == nil ? .now : nil; try? context.save()
          } label: { Label(trip.archivedAt == nil ? "Archive" : "Unarchive", systemImage: "archivebox") }
          Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
        } label: { Image(systemName: "ellipsis") }
      }
    }
    .sheet(isPresented: $editing) { NavigationStack { TripFormView(trip: trip) } }
    .sheet(isPresented: $addingWallet) { NavigationStack { WalletFormView(trip: trip) } }
    .sheet(item: $shareImage) { ActivitySheet(items: [$0.image]) }
    .confirmationDialog("Delete \(trip.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
      Button("Delete Trip", role: .destructive) { delete() }
    } message: { Text("Its expenses stay in your history, just no longer linked to a trip.") }
  }

  private func hero(_ s: TripMath.Summary, _ k: TripKinds.Kind) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Image(systemName: k.icon).font(.title2.weight(.semibold))
        Spacer()
        Text(tripStatusText(s)).font(.subheadline.weight(.semibold)).padding(.vertical, 5).padding(.horizontal, 10)
          .background(.white.opacity(0.2), in: Capsule())
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(trip.name).font(.title2.weight(.bold)).lineLimit(2)
        Text([tripDates(trip), trip.places.isEmpty ? nil : trip.places.map(\.name).joined(separator: ", ")].compactMap { $0 }.joined(separator: " · "))
          .font(.subheadline).opacity(0.85)
      }
      HStack(alignment: .bottom) {
        VStack(alignment: .leading, spacing: 2) {
          Text("You've spent").font(.caption).opacity(0.85)
          Text(Money.format(s.spent, hidden: hidden)).font(.system(size: 34, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 2) {
          if s.budget > 0 {
            Text(s.remaining >= 0 ? "\(Money.format(s.remaining, hidden: hidden)) left" : "\(Money.format(-s.remaining, hidden: hidden)) over")
              .font(.subheadline.weight(.semibold))
            Text("of \(Money.format(s.budget, hidden: hidden))").font(.caption).opacity(0.85)
          }
          if trip.travellers > 1 { Text("\(Money.format(s.perPerson, hidden: hidden)) per person").font(.caption).opacity(0.85) }
        }
      }
      if s.budget > 0 {
        GeometryReader { g in
          ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.25))
            Capsule().fill(s.overBudget ? Color(hex: "#FFB4B4") : .white).frame(width: max(8, g.size.width * min(s.progress, 1)))
          }
        }
        .frame(height: 8)
      }
    }
    .foregroundStyle(.white)
    .padding(20)
    .background(LinearGradient(colors: [Color(hex: k.color), Color(hex: k.color).opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 26, style: .continuous))
  }

  @MainActor private func render(_ s: TripMath.Summary, _ k: TripKinds.Kind) -> UIImage? {
    let card = VStack(alignment: .leading, spacing: 12) {
      hero(s, k)
      ForEach(s.items.filter { $0.spent > 0 }) { i in
        HStack { Text(i.item.label); Spacer(); Text(Money.format(i.spent)).fontWeight(.semibold) }.font(.subheadline)
      }
      Text("Paisa Pulse").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
    }
    .padding(16).frame(width: 380).background(Color(.systemGroupedBackground))
    let r = ImageRenderer(content: card)
    r.scale = scale
    return r.uiImage
  }

  private func delete() {
    for t in txns where t.tripId == trip.id { t.tripId = nil; t.tripItemId = nil; t.walletId = nil }
    for i in items where i.tripId == trip.id { context.delete(i) }
    for w in wallets where w.tripId == trip.id { context.delete(w) }
    context.delete(trip)
    try? context.save()
    dismiss()
  }
}

struct TripShareImage: Identifiable { let id = UUID(); let image: UIImage }

/// Cash or a forex card for a trip: what you carry, in which currency, at what rate.
struct WalletFormView: View {
  let trip: Trip
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @State private var label = ""
  @State private var currency: String?
  @State private var amount = ""
  @State private var rateText = ""
  @State private var picking = false

  var body: some View {
    Form {
      Section {
        TextField(trip.international ? "Name, e.g. Baht cash, Niyo forex card" : "Name, e.g. Cash", text: $label)
        Menu {
          Button(Money.base) { currency = nil }
          ForEach(trip.currencies, id: \.self) { c in Button("\(c) · \(World.currencyName(c))") { setCurrency(c) } }
          Button("Other…") { picking = true }
        } label: {
          LabeledContent("Currency") { Text(currency ?? Money.base) }
        }
        TextField("Amount in \(currency ?? Money.base)", text: $amount).keyboardType(.decimalPad)
        if let c = currency {
          TextField("\(Money.symbol) per 1 \(c)", text: $rateText).keyboardType(.decimalPad)
        }
      } footer: {
        Text(currency == nil ? "Cash you take along. Spends paid from it show how much is left."
             : "Use the rate you bought it at, so the trip's totals match what it really cost you.")
      }
    }
    .navigationTitle(trip.international ? "Cash or Forex" : "Cash")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(Money.parse(amount) == nil) }
    }
    .sheet(isPresented: $picking) { CurrencyPickerSheet { setCurrency($0) } }
    .onAppear {
      if trip.international, let c = trip.currencies.first { setCurrency(c) }
      if label.isEmpty { label = trip.international ? "Forex" : "Cash" }
    }
  }

  private func setCurrency(_ c: String) {
    currency = c == Money.base ? nil : c
    guard currency != nil else { return }
    Task { if let r = await Currency.rates(), let v = Fx.rate(from: c, to: Money.base, inrPer: r.inrPer) { rateText = String(format: "%.4f", v) } }
  }

  private func save() {
    guard let a = Money.parse(amount) else { return }
    let rate = currency == nil ? 1 : (Double(rateText) ?? 1)
    context.insert(TripWallet(tripId: trip.id, label: label.nilIfEmpty ?? "Cash", currency: currency, amount: a, rate: rate))
    try? context.save()
    dismiss()
  }
}

/// Home: the trip that's on now, or the next one coming up.
struct HomeTripsSection: View {
  let trips: [Trip]
  let items: [TripItem]
  let wallets: [TripWallet]
  let txns: [Txn]
  var hidden = false
  var body: some View {
    let live = trips.filter { $0.archivedAt == nil }.map { TripMath.summary($0, items: items, wallets: wallets, txns: txns) }
    let shown = (live.filter { $0.status == .ongoing } + live.filter { $0.status == .upcoming }.sorted { ($0.trip.startAt ?? .distantFuture) < ($1.trip.startAt ?? .distantFuture) }).prefix(2)
    Section {
      if shown.isEmpty {
        NavigationLink { PlanningView() } label: {
          Label { VStack(alignment: .leading) { Text("Plan a trip or event"); Text("Budgets, forex and splits in one place").font(.caption).foregroundStyle(.secondary) } }
          icon: { CategoryBadge(icon: "airplane", color: "#2563EB", size: 32) }
        }
      }
      ForEach(Array(shown), id: \.trip.id) { s in
        NavigationLink { TripDetailView(trip: s.trip) } label: { TripCard(summary: s, hidden: hidden) }
          .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
      }
    } header: {
      HStack { Text("Planning"); Spacer(); NavigationLink("All") { PlanningView() }.font(.subheadline).textCase(nil) }
    }
  }
}
