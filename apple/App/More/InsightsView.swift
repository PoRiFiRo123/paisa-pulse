import Charts
import SwiftData
import SwiftUI

struct InsightsView: View {
  @Query(filter: #Predicate<Txn> { $0.deletedAt == nil }) private var txns: [Txn]
  @Query private var accounts: [Account]
  @Query private var categories: [Category]
  @AppStorage(PrefKey.monthStartDay, store: AppGroup.defaults) private var monthStartDay = 1
  @State private var offset = 0
  @State private var selectedMonth: Date?

  var body: some View {
    let lookups = Lookups(accounts: accounts, categories: categories)
    let range = Periods.month(offset: offset, startDay: monthStartDay)
    let prev = Periods.month(offset: offset - 1, startDay: monthStartDay)
    let s = Ledger.summary(txns, in: range)
    let p = Ledger.summary(txns, in: prev)
    let months: [(start: Date, spent: Int)] = (0..<6).reversed().map { i in
      let r = Periods.month(offset: offset - i, startDay: monthStartDay)
      return (r.start, Ledger.summary(txns, in: r).spent)
    }
    let cats = Ledger.byCategory(txns, in: range, categories: lookups.categories)
    let days = max(1, Calendar.current.dateComponents([.day], from: range.start, to: min(range.end, .now)).day ?? 1)

    List {
      Section {
        VStack(alignment: .leading, spacing: 4) {
          Text("Spent in \(Periods.label(range, startDay: monthStartDay))").font(.subheadline).foregroundStyle(.secondary)
          Text(Money.format(s.spent)).font(.system(size: 36, weight: .bold, design: .rounded))
          HStack(spacing: 18) {
            stat("Per day", Money.format(s.spent / days), .primary)
            if p.spent > 0 {
              let change = Double(s.spent - p.spent) / Double(p.spent)
              stat("vs last month", "\(change >= 0 ? "up" : "down") \(Int(abs(change) * 100))%", change > 0 ? .expense : .income)
            }
            stat("Kept", Money.format(max(0, s.saved)), .income)
          }
          .padding(.top, 6)
        }
        .padding(.vertical, 6)
      }

      Section("Last 6 months") {
        Chart(months, id: \.start) { m in
          BarMark(x: .value("Month", m.start, unit: .month), y: .value("Spent", Double(m.spent) / 100))
            .foregroundStyle(Calendar.current.isDate(m.start, equalTo: range.start, toGranularity: .month) ? Color.accentColor : Color.accentColor.opacity(0.35))
            .cornerRadius(6)
        }
        .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
        .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let d = v.as(Double.self) { Text(Money.compact(Int(d * 100))) } } } }
        .frame(height: 180)
        .padding(.vertical, 8)
      }

      if !cats.isEmpty {
        Section("Where it went") {
          Chart(cats, id: \.id) { item in
            SectorMark(angle: .value("Spent", item.amount), innerRadius: .ratio(0.62), angularInset: 1.5)
              .foregroundStyle(Color(hex: lookups.categories[item.id]?.color ?? "#8E8E93"))
              .cornerRadius(4)
          }
          .frame(height: 200)
          .padding(.vertical, 8)
          ForEach(cats, id: \.id) { item in
            let c = lookups.categories[item.id]
            HStack {
              CategoryBadge(icon: c?.icon ?? "questionmark", color: c?.color ?? "#8E8E93", size: 30)
              Text(c?.name ?? "Uncategorised")
              Spacer()
              VStack(alignment: .trailing) {
                Text(Money.format(item.amount)).fontDesign(.rounded).foregroundStyle(Color.expense)
                Text("\(Int((Double(item.amount) / Double(max(s.spent, 1)) * 100).rounded()))%").font(.caption).foregroundStyle(.secondary)
              }
            }
          }
        }
      }

      let biggest = txns.filter { $0.type == .expense && range.contains($0.occurredAt) }.sorted { $0.effectiveAmount > $1.effectiveAmount }.prefix(5)
      if !biggest.isEmpty {
        Section("Biggest expenses") {
          ForEach(Array(biggest)) { t in TxnRow(txn: t, lookups: lookups, showTime: false) }
        }
      }
    }
    .navigationTitle("Insights")
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        Button { offset -= 1 } label: { Image(systemName: "chevron.left") }
        Button { offset += 1 } label: { Image(systemName: "chevron.right") }.disabled(offset >= 0)
      }
    }
  }

  private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(label).font(.caption).foregroundStyle(.secondary)
      Text(value).font(.subheadline.weight(.semibold)).fontDesign(.rounded).foregroundStyle(color)
    }
  }
}

struct CalendarView: View {
  @Query(filter: #Predicate<Txn> { $0.deletedAt == nil }, sort: \Txn.occurredAt, order: .reverse) private var txns: [Txn]
  @Query private var accounts: [Account]
  @Query private var categories: [Category]
  @Environment(Router.self) private var router
  @State private var month = Calendar.current.dateInterval(of: .month, for: .now)!
  @State private var selected = Calendar.current.startOfDay(for: .now)

  var body: some View {
    let cal = Calendar.current
    let lookups = Lookups(accounts: accounts, categories: categories)
    let daily = Ledger.dailySpend(txns, in: month)
    let maxDay = max(daily.values.max() ?? 1, 1)
    let firstWeekday = cal.component(.weekday, from: month.start)
    let lead = (firstWeekday - cal.firstWeekday + 7) % 7
    let count = cal.range(of: .day, in: .month, for: month.start)!.count
    let cells: [Date?] = Array(repeating: nil, count: lead) + (0..<count).map { cal.date(byAdding: .day, value: $0, to: month.start)! }
    let dayTxns = txns.filter { cal.isDate($0.occurredAt, inSameDayAs: selected) }
    let s = Ledger.summary(txns, in: month)

    List {
      Section {
        HStack(spacing: 0) {
          SummaryCell(label: "Spent", value: s.spent, color: .expense)
          SummaryCell(label: "Income", value: s.income, color: .income)
        }
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
          ForEach(Array(cal.veryShortWeekdaySymbols.rotated(by: cal.firstWeekday - 1).enumerated()), id: \.offset) { _, d in
            Text(d).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
          }
          ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
            if let day {
              let spent = daily[day] ?? 0
              let heat = spent > 0 ? 0.15 + 0.75 * sqrt(Double(spent) / Double(maxDay)) : 0
              Button { selected = day } label: {
                VStack(spacing: 1) {
                  Text("\(cal.component(.day, from: day))").font(.subheadline.weight(cal.isDateInToday(day) ? .bold : .regular))
                  Text(spent > 0 ? String(Money.compact(spent).dropFirst()) : " ").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.expense.opacity(heat), in: RoundedRectangle(cornerRadius: 8))
                .overlay { if cal.isDate(day, inSameDayAs: selected) { RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 2) } }
              }
              .buttonStyle(.plain)
            } else {
              Color.clear.frame(minHeight: 44)
            }
          }
        }
        .padding(.vertical, 6)
      } footer: { Text("Redder days are bigger spending days.") }

      Section {
        if dayTxns.isEmpty { Text("Nothing on this day").foregroundStyle(.secondary) }
        ForEach(dayTxns) { t in
          NavigationLink { TransactionDetailView(txn: t) } label: { TxnRow(txn: t, lookups: lookups) }.txnActions(t)
        }
        Button { router.add = AddRequest(type: .expense, date: selected.addingTimeInterval(12 * 3600)) } label: {
          Label("Add on \(selected.formatted(.dateTime.day().month()))", systemImage: "plus")
        }
      } header: { Text(DayHeader.label(selected)) }
    }
    .navigationTitle(month.start.formatted(.dateTime.month(.wide).year()))
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        Button { shift(-1) } label: { Image(systemName: "chevron.up") }.accessibilityLabel("Previous month")
        Button { shift(1) } label: { Image(systemName: "chevron.down") }.accessibilityLabel("Next month")
      }
    }
  }

  private func shift(_ by: Int) {
    let d = Calendar.current.date(byAdding: .month, value: by, to: month.start)!
    month = Calendar.current.dateInterval(of: .month, for: d)!
    selected = month.start
  }
}

extension Array {
  func rotated(by n: Int) -> [Element] {
    guard !isEmpty else { return self }
    let k = ((n % count) + count) % count
    return Array(self[k...] + self[..<k])
  }
}

/// Net worth at the end of each of the last 12 months, rebuilt from transactions.
struct NetWorthView: View {
  @Query private var accounts: [Account]
  @Query(filter: #Predicate<Txn> { $0.deletedAt == nil }) private var txns: [Txn]

  var body: some View {
    let points: [(Date, Int)] = (0..<12).reversed().map { i in
      let end = Calendar.current.date(byAdding: .month, value: -i, to: .now)!
      let b = Ledger.balances(accounts: accounts, txns: txns.filter { $0.occurredAt <= end })
      return (end, Ledger.netWorth(accounts: accounts, balances: b))
    }
    List {
      Section {
        Chart(points, id: \.0) { p in
          AreaMark(x: .value("Month", p.0), y: .value("Net worth", Double(p.1) / 100))
            .foregroundStyle(LinearGradient(colors: [Color.accentColor.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
            .interpolationMethod(.catmullRom)
          LineMark(x: .value("Month", p.0), y: .value("Net worth", Double(p.1) / 100))
            .interpolationMethod(.catmullRom)
        }
        .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let d = v.as(Double.self) { Text(Money.compact(Int(d * 100))) } } } }
        .frame(height: 240).padding(.vertical, 8)
      } footer: {
        Text("Rebuilt from your transactions and each account's starting balance.")
      }
      Section {
        ForEach(points.reversed().prefix(6), id: \.0) { p in
          LabeledContent(p.0.formatted(.dateTime.month(.wide).year())) {
            Text(Money.format(p.1)).foregroundStyle(p.1 < 0 ? Color.expense : .primary)
          }
        }
      }
    }
    .navigationTitle("Net Worth")
  }
}
