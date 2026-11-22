import SwiftData
import SwiftUI
import WidgetKit

@main
struct PaisaPulseWidgets: WidgetBundle {
  var body: some Widget {
    SpendingWidget()
    if #available(iOS 18.0, *) {
      AddExpenseControl()
    }
  }
}

struct SpendingEntry: TimelineEntry {
  struct Top: Identifiable { let name: String; let amount: Int; let color: String; let icon: String; var id: String { name } }
  let date: Date
  let spent: Int
  let today: Int
  let income: Int
  let budget: Int?
  let top: [Top]
  let hidden: Bool

  static let placeholder = SpendingEntry(date: .now, spent: 3_845_000, today: 42_000, income: 9_000_000, budget: 5_000_000,
                                         top: [.init(name: "Rent", amount: 1_500_000, color: "#AF52DE", icon: "house.fill"),
                                               .init(name: "Food", amount: 1_240_000, color: "#FF9500", icon: "fork.knife"),
                                               .init(name: "Transport", amount: 418_000, color: "#007AFF", icon: "car.fill")],
                                         hidden: false)
}

struct SpendingProvider: TimelineProvider {
  func placeholder(in context: Context) -> SpendingEntry { .placeholder }
  func getSnapshot(in context: Context, completion: @escaping (SpendingEntry) -> Void) {
    completion(context.isPreview ? .placeholder : load())
  }
  func getTimeline(in context: Context, completion: @escaping (Timeline<SpendingEntry>) -> Void) {
    completion(Timeline(entries: [load()], policy: .after(.now.addingTimeInterval(30 * 60))))
  }

  /// Reads the app's database straight from the App Group.
  private func load() -> SpendingEntry {
    let d = AppGroup.defaults
    let container = Store.makeContainer()
    let ctx = ModelContext(container)
    let txns = (try? ctx.fetch(FetchDescriptor<Txn>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
    let cats = Dictionary(((try? ctx.fetch(FetchDescriptor<Category>())) ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    let budgets = (try? ctx.fetch(FetchDescriptor<Budget>())) ?? []
    let month = Periods.month(containing: .now, startDay: max(1, d.integer(forKey: PrefKey.monthStartDay)))
    let today = Calendar.current.dateInterval(of: .day, for: .now)!
    let s = Ledger.summary(txns, in: month)
    let top = Ledger.byCategory(txns, in: month, categories: cats).prefix(3).map { item in
      SpendingEntry.Top(name: cats[item.id]?.name ?? "Other", amount: item.amount, color: cats[item.id]?.color ?? "#8E8E93", icon: cats[item.id]?.icon ?? "questionmark")
    }
    return SpendingEntry(date: .now, spent: s.spent, today: Ledger.summary(txns, in: today).spent, income: s.income,
                         budget: budgets.first { $0.categoryId == nil && $0.period == "monthly" }?.amount,
                         top: Array(top), hidden: d.bool(forKey: PrefKey.hideAmounts))
  }
}

struct SpendingWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "Spending", provider: SpendingProvider()) { entry in
      SpendingWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName("This Month")
    .description("What you've spent this month, your budget and a quick Add button.")
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
  }
}

struct SpendingWidgetView: View {
  let entry: SpendingEntry
  @Environment(\.widgetFamily) private var family
  private let addURL = URL(string: "paisapulse://add?type=expense")!

  var body: some View {
    switch family {
    case .accessoryInline:
      Text("\(Money.compact(entry.spent, hidden: entry.hidden)) this month")
    case .accessoryCircular:
      if let b = entry.budget, b > 0 {
        Gauge(value: min(Double(entry.spent) / Double(b), 1)) { Image(systemName: "indianrupeesign") } currentValueLabel: {
          Text(Money.compact(entry.spent, hidden: entry.hidden).dropFirst())
        }
        .gaugeStyle(.accessoryCircularCapacity)
      } else {
        VStack(spacing: 0) { Image(systemName: "indianrupeesign"); Text(Money.compact(entry.spent, hidden: entry.hidden).dropFirst()).font(.caption) }
      }
    case .accessoryRectangular:
      VStack(alignment: .leading) {
        Text("This month").font(.caption2)
        Text(Money.format(entry.spent, hidden: entry.hidden)).font(.headline)
        Text("Today \(Money.format(entry.today, hidden: entry.hidden))").font(.caption2)
      }
      .widgetURL(addURL)
    case .systemMedium:
      HStack(alignment: .top, spacing: 14) {
        VStack(alignment: .leading, spacing: 4) {
          Text("This month").font(.caption).foregroundStyle(.secondary)
          Text(Money.format(entry.spent, hidden: entry.hidden)).font(.system(.title2, design: .rounded).weight(.bold)).minimumScaleFactor(0.6).lineLimit(1)
          budgetLine
          Spacer(minLength: 0)
          Link(destination: addURL) {
            Label("Add", systemImage: "plus").font(.subheadline.weight(.semibold))
              .padding(.horizontal, 14).padding(.vertical, 7)
              .background(Color.accentColor, in: Capsule()).foregroundStyle(.white)
          }
        }
        VStack(alignment: .leading, spacing: 8) {
          ForEach(entry.top) { t in
            HStack(spacing: 6) {
              Image(systemName: t.icon).font(.caption2).foregroundStyle(.white).frame(width: 20, height: 20)
                .background(Color(hex: t.color), in: RoundedRectangle(cornerRadius: 5))
              Text(t.name).font(.caption).lineLimit(1)
              Spacer(minLength: 2)
              Text(Money.compact(t.amount, hidden: entry.hidden)).font(.caption.weight(.semibold)).foregroundStyle(Color.expense)
            }
          }
        }
      }
    default:
      VStack(alignment: .leading, spacing: 4) {
        Text("This month").font(.caption).foregroundStyle(.secondary)
        Text(Money.compact(entry.spent, hidden: entry.hidden)).font(.system(.title, design: .rounded).weight(.bold))
        Text("Today \(Money.compact(entry.today, hidden: entry.hidden))").font(.caption).foregroundStyle(Color.expense)
        Spacer(minLength: 0)
        budgetLine
        HStack { Spacer(); Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Color.accentColor) }
      }
      .widgetURL(addURL)
    }
  }

  @ViewBuilder private var budgetLine: some View {
    if let b = entry.budget, b > 0 {
      let left = b - entry.spent
      VStack(alignment: .leading, spacing: 3) {
        ProgressView(value: min(Double(entry.spent) / Double(b), 1)).tint(left < 0 ? Color.expense : .accentColor)
        Text(left < 0 ? "\(Money.compact(-left, hidden: entry.hidden)) over" : "\(Money.compact(left, hidden: entry.hidden)) left")
          .font(.caption2).foregroundStyle(left < 0 ? Color.expense : .secondary)
      }
    }
  }
}

@available(iOS 18.0, *)
struct AddExpenseControl: ControlWidget {
  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: "com.paisapulse.app.add") {
      ControlWidgetButton(action: OpenAddExpenseIntent()) {
        Label("Add Expense", systemImage: "indianrupeesign.circle")
      }
    }
    .displayName("Add Expense")
    .description("Log an expense from Control Center or the Action Button.")
  }
}
