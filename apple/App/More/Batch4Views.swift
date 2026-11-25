import Charts
import SwiftData
import SwiftUI

// Templates, tags, monthly recap, month-end forecast, Home layout and investment values.
// Same screens on Android (ui/screens/Batch4.kt).

struct ForecastCard: View {
  let forecast: Forecast.Result
  let hidden: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Likely by month-end").font(.subheadline).foregroundStyle(.secondary)
          Text(Money.format(forecast.projected, hidden: hidden)).font(.system(size: 28, weight: .bold, design: .rounded)).rolling(forecast.projected)
            .foregroundStyle(forecast.projected < 0 ? Color.expense : .primary)
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 2) {
          Text("Now").font(.caption).foregroundStyle(.secondary)
          Text(Money.format(forecast.now, hidden: hidden)).font(.subheadline.weight(.semibold)).fontDesign(.rounded)
        }
      }
      HStack(spacing: 14) {
        if forecast.incoming > 0 { item("Coming in", forecast.incoming, .income) }
        if forecast.outgoing > 0 { item("Bills", forecast.outgoing, .expense) }
        item("Everyday · \(forecast.daysLeft)d", forecast.dailySpend * forecast.daysLeft, .secondary)
      }
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
  }
  private func item(_ label: String, _ value: Int, _ color: Color) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(label).font(.caption2).foregroundStyle(.secondary)
      Text(Money.format(value, hidden: hidden)).font(.caption.weight(.semibold)).fontDesign(.rounded).foregroundStyle(color)
    }
  }
}

struct TemplatesView: View {
  @Query(sort: \TxnTemplate.sortOrder) private var templates: [TxnTemplate]
  @Query private var accounts: [Account]
  @Query private var categories: [Category]
  @Environment(\.modelContext) private var context

  var body: some View {
    let lookups = Lookups(accounts: accounts, categories: categories)
    List {
      if templates.isEmpty {
        EmptyHint(title: "No templates yet", icon: "bolt", message: "Open any transaction and tap Save as Template. Templates add in one tap from Home and Quick Add.")
      }
      ForEach(templates) { t in
        HStack(spacing: 12) {
          let c = t.categoryId.flatMap { lookups.categories[$0] }
          CategoryBadge(icon: c?.icon ?? "bolt.fill", color: c?.color ?? "#5E5CE6", size: 32)
          VStack(alignment: .leading, spacing: 2) {
            Text(t.name)
            Text([t.accountId.flatMap { lookups.accounts[$0]?.name }, c?.name].compactMap { $0 }.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary)
          }
          Spacer()
          AmountText(amount: t.amount, type: t.type)
        }
      }
      .onDelete { idx in idx.map { templates[$0] }.forEach { context.delete($0) }; try? context.save() }
      .onMove { from, to in
        Haptic.soft()
        var list = templates
        list.move(fromOffsets: from, toOffset: to)
        for (i, t) in list.enumerated() { t.sortOrder = i }
        try? context.save()
      }
    }
    .navigationTitle("Templates")
    .toolbar { if !templates.isEmpty { EditButton() } }
  }
}

struct TagsView: View {
  @Query(filter: #Predicate<Txn> { $0.deletedAt == nil }) private var txns: [Txn]
  @AppStorage(PrefKey.hideAmounts, store: AppGroup.defaults) private var hidden = false

  var body: some View {
    let tagged = txns.filter { !$0.tags.isEmpty }
    let groups = Dictionary(grouping: tagged.flatMap { t in t.tags.map { ($0, t) } }, by: \.0).mapValues { $0.map(\.1) }
    List {
      if groups.isEmpty {
        EmptyHint(title: "No tags yet", icon: "number", message: "Add tags like \"goa trip\" or \"work\" in Quick Add to total things that span categories.")
      }
      ForEach(groups.keys.sorted(), id: \.self) { tag in
        let list = groups[tag] ?? []
        NavigationLink { TagDetailView(tag: tag) } label: {
          HStack {
            Text("#\(tag)").foregroundStyle(Color.accentColor)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
              Text(Money.format(list.filter { $0.type == .expense }.reduce(0) { $0 + $1.effectiveAmount }, hidden: hidden)).fontDesign(.rounded)
              Text("\(list.count) transactions").font(.caption2).foregroundStyle(.secondary)
            }
          }
        }
      }
    }
    .navigationTitle("Tags")
  }
}

struct TagDetailView: View {
  let tag: String
  @Query(filter: #Predicate<Txn> { $0.deletedAt == nil }, sort: \Txn.occurredAt, order: .reverse) private var txns: [Txn]
  @Query private var accounts: [Account]
  @Query private var categories: [Category]

  var body: some View {
    let lookups = Lookups(accounts: accounts, categories: categories)
    let list = txns.filter { $0.tags.contains(tag) }
    let spent = list.filter { $0.type == .expense }.reduce(0) { $0 + $1.effectiveAmount }
    let byCat = Dictionary(grouping: list.filter { $0.type == .expense }, by: { Ledger.topLevel($0.categoryId, lookups.categories) ?? "" })
      .mapValues { $0.reduce(0) { $0 + $1.effectiveAmount } }.sorted { $0.value > $1.value }
    List {
      Section {
        VStack(alignment: .leading, spacing: 4) {
          Text("Spent on #\(tag)").font(.subheadline).foregroundStyle(.secondary)
          Text(Money.format(spent)).font(.system(size: 36, weight: .bold, design: .rounded)).rolling(spent)
          if let first = list.last?.occurredAt, let last = list.first?.occurredAt {
            Text("\(first.formatted(date: .abbreviated, time: .omitted)) – \(last.formatted(date: .abbreviated, time: .omitted))").font(.footnote).foregroundStyle(.secondary)
          }
        }
      }
      if byCat.count > 1 {
        Section("By category") {
          ForEach(byCat, id: \.key) { id, amount in
            let c = lookups.categories[id]
            LabeledContent { Text(Money.format(amount)) } label: {
              Label { Text(c?.name ?? "Uncategorised") } icon: { CategoryBadge(icon: c?.icon ?? "questionmark", color: c?.color ?? "#8E8E93", size: 26) }
            }
          }
        }
      }
      Section("Transactions") {
        ForEach(list) { t in NavigationLink(value: t) { TxnRow(txn: t, lookups: lookups) } }
      }
    }
    .navigationTitle("#\(tag)")
    .navigationDestination(for: Txn.self) { TransactionDetailView(txn: $0) }
  }
}

struct RecapView: View {
  @State var offset: Int
  @Query(filter: #Predicate<Txn> { $0.deletedAt == nil }) private var txns: [Txn]
  @Query private var accounts: [Account]
  @Query private var categories: [Category]
  @AppStorage(PrefKey.monthStartDay, store: AppGroup.defaults) private var monthStartDay = 1
  @Environment(\.displayScale) private var scale
  @State private var shareImage: ShareImage?

  var body: some View {
    let lookups = Lookups(accounts: accounts, categories: categories)
    let month = Periods.month(offset: offset, startDay: monthStartDay)
    let r = Recap.make(txns: txns, categories: lookups.categories, month: month, previous: Periods.month(offset: offset - 1, startDay: monthStartDay))
    let card = RecapCard(recap: r, title: month.start.formatted(.dateTime.month(.wide).year()), lookups: lookups,
                         biggest: r.biggestId.flatMap { id in txns.first { $0.id == id } })
    ScrollView {
      card.padding()
      // The picture is drawn when you tap Share, never while the screen is being built
      // (rendering inside body crashed the app on some iPhones).
      Button {
        shareImage = render(card).map(ShareImage.init)
      } label: {
        Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent).controlSize(.large).padding(.horizontal)
      Text("The picture shows totals only, no account names.").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
    }
    .sheet(item: $shareImage) { item in
      ActivitySheet(items: [item.image]).presentationDetents([.medium, .large])
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle("Recap")
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        Button { offset -= 1 } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous month")
        Button { offset += 1 } label: { Image(systemName: "chevron.right") }.disabled(offset >= 0).accessibilityLabel("Next month")
      }
    }
  }

  @MainActor private func render(_ card: RecapCard) -> UIImage? {
    let r = ImageRenderer(content: card.frame(width: 360).padding(12).background(Color(.systemGroupedBackground)))
    r.scale = scale
    return r.uiImage
  }
}

struct ShareImage: Identifiable { let id = UUID(); let image: UIImage }

/// The system share sheet for things SwiftUI's ShareLink can't take directly (a freshly drawn picture).
struct ActivitySheet: UIViewControllerRepresentable {
  let items: [Any]
  func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
  func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct RecapCard: View {
  let recap: Recap.Result
  let title: String
  let lookups: Lookups
  let biggest: Txn?

  var body: some View {
    let top = recap.topCategoryId.flatMap { lookups.categories[$0] }
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.headline).foregroundStyle(.white.opacity(0.85))
        Text(Money.format(recap.spent)).font(.system(size: 44, weight: .bold, design: .rounded)).foregroundStyle(.white)
        if let change = recap.change {
          Text(change >= 0 ? "\(Int((change * 100).rounded()))% more than last month" : "\(Int((-change * 100).rounded()))% less than last month")
            .font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.9))
        }
      }
      .padding(20).frame(maxWidth: .infinity, alignment: .leading)
      .background(LinearGradient(colors: [Color(hex: "#5E5CE6"), Color(hex: "#AF52DE")], startPoint: .topLeading, endPoint: .bottomTrailing),
                  in: RoundedRectangle(cornerRadius: 24, style: .continuous))

      Grid(horizontalSpacing: 12, verticalSpacing: 12) {
        GridRow {
          tile("Top category", top?.name ?? "—", Money.format(recap.topCategoryAmount), top?.icon ?? "chart.pie.fill", top?.color ?? "#FF9500")
          tile(recap.saved >= 0 ? "Saved" : "Overspent", Money.format(abs(recap.saved)), "of \(Money.format(recap.income)) income", "banknote.fill", recap.saved >= 0 ? "#34C759" : "#E5484D")
        }
        GridRow {
          tile("No-spend days", "\(recap.noSpendDays) of \(recap.days)", "Best streak \(recap.longestNoSpendStreak) days", "leaf.fill", "#30B0C7")
          tile("Favourite place", recap.topPayee ?? "—", recap.topPayeeCount > 1 ? "\(recap.topPayeeCount) times" : "", "storefront.fill", "#FF2D55")
        }
      }
      if let b = biggest {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text("Biggest expense").font(.caption).foregroundStyle(.secondary)
            Text(lookups.title(b)).font(.subheadline.weight(.semibold))
          }
          Spacer()
          Text(Money.format(b.effectiveAmount)).font(.headline).fontDesign(.rounded).foregroundStyle(Color.expense)
        }
        .padding(16).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      }
      Text("\(recap.count) transactions · Paisa Pulse").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
    }
  }

  private func tile(_ label: String, _ value: String, _ detail: String, _ icon: String, _ color: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      CategoryBadge(icon: icon, color: color, size: 28)
      Text(label).font(.caption).foregroundStyle(.secondary)
      Text(value).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
      if !detail.isEmpty { Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
    }
    .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
    .padding(14).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }
}

struct HomeLayoutView: View {
  @AppStorage(PrefKey.homeOrder, store: AppGroup.defaults) private var homeOrder = ""
  @AppStorage(PrefKey.homeHidden, store: AppGroup.defaults) private var homeHidden = ""
  @Environment(\.dismiss) private var dismiss
  @State private var order: [String] = []
  @State private var hidden: Set<String> = []

  var body: some View {
    List {
      Section {
        ForEach(order, id: \.self) { key in
          let info = HomeSections.all.first { $0.key == key }
          Toggle(isOn: Binding(get: { !hidden.contains(key) }, set: { if $0 { hidden.remove(key) } else { hidden.insert(key) } })) {
            Label { Text(info?.label ?? key) } icon: { Image(systemName: info?.icon ?? "square").foregroundStyle(Color.accentColor) }
          }
        }
        .onMove { order.move(fromOffsets: $0, toOffset: $1); Haptic.soft() }
      } footer: { Text("Drag to reorder, switch off what you don't need.") }
      Section { Button("Reset to Default") { order = HomeSections.all.map(\.key); hidden = [] } }
    }
    .environment(\.editMode, .constant(.active))
    .navigationTitle("Home Screen")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Done") { homeOrder = order.joined(separator: ","); homeHidden = hidden.sorted().joined(separator: ","); dismiss() }.fontWeight(.semibold)
      }
    }
    .onAppear { order = HomeSections.order(homeOrder); hidden = HomeSections.hidden(homeHidden) }
  }
}

/// Investments: record what the account is worth today (Groww, mutual funds, PF).
struct ValuationSection: View {
  let account: Account
  @Query(sort: \Valuation.at, order: .reverse) private var all: [Valuation]
  @Environment(\.modelContext) private var context
  @State private var updating = false
  @State private var value = ""

  var body: some View {
    let list = all.filter { $0.accountId == account.id }
    Section {
      Button { updating = true } label: { Label("Update Value", systemImage: "arrow.triangle.2.circlepath") }
      if list.count > 1 {
        Chart(list.reversed(), id: \.id) { v in
          LineMark(x: .value("Date", v.at), y: .value("Value", Double(v.value) / 100)).interpolationMethod(.catmullRom)
          PointMark(x: .value("Date", v.at), y: .value("Value", Double(v.value) / 100)).symbolSize(20)
        }
        .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let d = v.as(Double.self) { Text(Money.compact(Int(d * 100))) } } } }
        .frame(height: 160)
      }
      ForEach(list.prefix(6)) { v in
        LabeledContent(v.at.formatted(date: .abbreviated, time: .omitted), value: Money.format(v.value))
      }
      .onDelete { idx in idx.map { list[$0] }.forEach { context.delete($0) }; try? context.save() }
    } header: { Text("Value") } footer: {
      Text("Money you move in later is added on top of the last value. Update it whenever you check your app.")
    }
    .alert("What's it worth today?", isPresented: $updating) {
      TextField("Current value", text: $value).keyboardType(.decimalPad)
      Button("Save") {
        if let p = Money.parse(value) { context.insert(Valuation(accountId: account.id, value: p)); try? context.save(); WidgetRefresh.now() }
        value = ""
      }
      Button("Cancel", role: .cancel) { value = "" }
    }
  }
}
