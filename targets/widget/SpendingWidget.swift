import SwiftUI
import WidgetKit

struct SpendingEntry: TimelineEntry {
  let date: Date
  let snapshot: Snapshot?
}

struct SpendingProvider: TimelineProvider {
  func placeholder(in context: Context) -> SpendingEntry {
    SpendingEntry(date: .now, snapshot: .placeholder)
  }

  func getSnapshot(in context: Context, completion: @escaping (SpendingEntry) -> Void) {
    completion(SpendingEntry(date: .now, snapshot: context.isPreview ? .placeholder : (Snapshot.load() ?? .placeholder)))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<SpendingEntry>) -> Void) {
    // The app reloads widgets whenever data changes; also refresh at midnight for "Today".
    let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))
    completion(Timeline(entries: [SpendingEntry(date: .now, snapshot: Snapshot.load())], policy: .after(midnight)))
  }
}

private let addURL = URL(string: "paisapulse://add?type=expense")!
private let homeURL = URL(string: "paisapulse://")!

struct SpendingWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: SpendingEntry

  var body: some View {
    if let s = entry.snapshot {
      switch family {
      case .accessoryCircular: circular(s)
      case .accessoryRectangular: rectangular(s)
      case .accessoryInline: Text("\(s.month): \(s.spentCompact)")
      case .systemMedium: medium(s)
      default: small(s)
      }
    } else {
      VStack(alignment: .leading, spacing: 6) {
        Image(systemName: "indianrupeesign.circle.fill").font(.title2).foregroundStyle(Color("Accent"))
        Text("Open Paisa Pulse to get started").font(.footnote).foregroundStyle(.secondary)
      }
      .widgetURL(homeURL)
    }
  }

  private func small(_ s: Snapshot) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(s.month).font(.caption).foregroundStyle(.secondary)
        Spacer()
        Link(destination: addURL) {
          Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(Color("Accent"))
        }
      }
      Text(s.spent)
        .font(.system(.title, design: .rounded, weight: .bold))
        .minimumScaleFactor(0.5)
        .lineLimit(1)
        .contentTransition(.numericText())
      Spacer(minLength: 0)
      if let b = s.budget {
        ProgressView(value: b.ratio).tint(b.over ? Color("Expense") : Color("Accent"))
        Text(b.label).font(.caption2).foregroundStyle(b.over ? Color("Expense") : .secondary)
      } else {
        Text("Today \(s.today)").font(.caption).foregroundStyle(.secondary)
      }
    }
    .widgetURL(homeURL)
  }

  private func medium(_ s: Snapshot) -> some View {
    HStack(alignment: .top, spacing: 16) {
      small(s)
      VStack(alignment: .leading, spacing: 8) {
        Text("Top categories").font(.caption).foregroundStyle(.secondary)
        ForEach(s.top) { c in
          HStack(spacing: 6) {
            Image(systemName: c.icon)
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(.white)
              .frame(width: 20, height: 20)
              .background(Circle().fill(Color(hex: c.color)))
            Text(c.name).font(.caption).lineLimit(1)
            Spacer(minLength: 4)
            Text(c.amount).font(.system(.caption, design: .rounded, weight: .semibold))
          }
        }
        Spacer(minLength: 0)
        Text("Today \(s.today)").font(.caption2).foregroundStyle(.secondary)
      }
    }
  }

  private func circular(_ s: Snapshot) -> some View {
    Gauge(value: s.budget?.ratio ?? 0) {
      Image(systemName: "indianrupeesign")
    } currentValueLabel: {
      Text(s.spentCompact).minimumScaleFactor(0.5)
    }
    .gaugeStyle(.accessoryCircular)
    .widgetURL(homeURL)
  }

  private func rectangular(_ s: Snapshot) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("Spent in \(s.month)").font(.caption2).foregroundStyle(.secondary)
      Text(s.spent).font(.system(.headline, design: .rounded)).widgetAccentable()
      if let b = s.budget {
        ProgressView(value: b.ratio)
      } else {
        Text("Today \(s.today)").font(.caption2)
      }
    }
    .widgetURL(homeURL)
  }
}

struct SpendingWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "SpendingWidget", provider: SpendingProvider()) { entry in
      SpendingWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName("Month Spend")
    .description("What you've spent this month, your budget and a quick Add button.")
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
  }
}
