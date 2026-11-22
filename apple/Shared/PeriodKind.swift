import Foundation

/// Insights periods: week / month / quarter / year (months follow "Month starts on"), or a custom range.
/// Same maths as the Android app's PeriodKind (logic/Periods2.kt).
enum PeriodKind: String, CaseIterable, Identifiable {
  case week, month, quarter, year, custom
  var id: String { rawValue }
  var label: String { rawValue.capitalized }
  var noun: String { self == .custom ? "period" : rawValue }

  /// The period `offset` steps from the one containing `date` (0 = current, -1 = previous).
  func range(offset: Int, from date: Date = .now, startDay: Int, weekStart: Int, custom: DateInterval? = nil,
             calendar: Calendar = .current) -> DateInterval {
    switch self {
    case .week:
      let w = Periods.week(containing: date, firstWeekday: weekStart, calendar: calendar)
      let s = calendar.date(byAdding: .weekOfYear, value: offset, to: w.start)!
      return DateInterval(start: s, end: calendar.date(byAdding: .weekOfYear, value: 1, to: s)!)
    case .month:
      return Periods.month(offset: offset, from: date, startDay: startDay, calendar: calendar)
    case .quarter, .year:
      let size = self == .quarter ? 3 : 12
      let current = Periods.month(containing: date, startDay: startDay, calendar: calendar)
      // The salary month's calendar month decides the quarter/year it belongs to.
      let m = calendar.component(.month, from: current.start) - 1
      let firstOffset = -(m % size) + offset * size
      let start = Periods.month(offset: firstOffset, from: date, startDay: startDay, calendar: calendar).start
      let end = Periods.month(offset: firstOffset + size, from: date, startDay: startDay, calendar: calendar).start
      return DateInterval(start: start, end: end)
    case .custom:
      let c = custom ?? Periods.month(containing: date, startDay: startDay, calendar: calendar)
      let len = c.end.timeIntervalSince(c.start)
      return DateInterval(start: c.start.addingTimeInterval(len * Double(offset)), duration: len)
    }
  }

  func label(_ r: DateInterval, startDay: Int) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_IN")
    let last = r.end.addingTimeInterval(-1)
    switch self {
    case .month: return Periods.label(r, startDay: startDay)
    case .year:
      f.dateFormat = "yyyy"
      return startDay == 1 ? f.string(from: r.start) : "\(f.string(from: r.start))–\(f.string(from: last).suffix(2))"
    case .quarter:
      f.dateFormat = "MMM"
      let y = Calendar.current.component(.year, from: r.start)
      return "\(f.string(from: r.start))–\(f.string(from: last)) \(y)"
    case .week, .custom:
      f.dateFormat = "d MMM"
      return "\(f.string(from: r.start)) – \(f.string(from: last))"
    }
  }

  /// Short bar label for the chart.
  func short(_ r: DateInterval) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_IN")
    switch self {
    case .week: f.dateFormat = "d MMM"
    case .month: f.dateFormat = "MMM"
    case .quarter:
      let q = (Calendar.current.component(.month, from: r.start) - 1) / 3 + 1
      return "Q\(q) ’\(Calendar.current.component(.year, from: r.start) % 100)"
    case .year: f.dateFormat = "yyyy"
    case .custom: f.dateFormat = "d MMM"
    }
    return f.string(from: r.start)
  }
}
