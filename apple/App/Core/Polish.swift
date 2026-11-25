import SwiftData
import SwiftUI
import UIKit

// Small things that make the app feel alive: one timing everywhere, rolling numbers, pressable
// buttons, skeletons, a live liquid shader, and one big celebration. Same on Android (ui/Polish.kt).

extension Animation {
  /// Every animation in the app: about 0.2 seconds.
  static let quick = Animation.snappy(duration: 0.2)
}

extension View {
  /// Amounts roll digit by digit when they change.
  func rolling<V: Equatable>(_ value: V) -> some View {
    contentTransition(.numericText()).animation(.quick, value: value)
  }
}

/// Buttons shrink a tiny bit while pressed.
struct PressableStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.96 : 1)
      .opacity(configuration.isPressed ? 0.85 : 1)
      .animation(.quick, value: configuration.isPressed)
  }
}

extension ButtonStyle where Self == PressableStyle {
  static var pressable: PressableStyle { PressableStyle() }
}

/// A soft tap when a row is dropped in a new place (reorder lists use `.onMove`, which has no trigger value).
enum Haptic {
  @MainActor static func soft() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
}

// MARK: Skeletons

/// Placeholder rows while something loads, instead of a spinner.
struct SkeletonRows: View {
  var count = 4
  var body: some View {
    ForEach(0..<count, id: \.self) { _ in
      HStack(spacing: 12) {
        Circle().frame(width: 32, height: 32)
        VStack(alignment: .leading, spacing: 4) {
          Text("Loading something here")
          Text("A little more detail").font(.caption)
        }
        Spacer()
        Text("₹1,234")
      }
      .redacted(reason: .placeholder)
      .foregroundStyle(.secondary)
      .accessibilityHidden(true)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Loading")
  }
}

// MARK: Live shader (Shaders.metal)

/// Drives a shader 30 times a second; holds still in Low Power Mode or with Reduce Motion.
private struct ShaderClock<Content: View>: View {
  @ViewBuilder var content: (Float) -> Content
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || lowPower)) { ctx in
      content(Float(ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)))
    }
    .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
      lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    }
  }
}

/// A slow liquid gradient in the accent colours (behind Home's balance).
struct LiquidBackground: View {
  var tint: Color = .accentColor
  @Environment(\.colorScheme) private var scheme
  var body: some View {
    ShaderClock { t in
      GeometryReader { g in
        Rectangle().colorEffect(ShaderLibrary.liquid(.float2(g.size), .float(t), .color(tint), .color(tint.mix(with: .pink, by: 0.35))))
      }
    }
    .opacity(scheme == .dark ? 0.28 : 0.16)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

/// A progress bar whose fill moves gently, like liquid (budgets, goals, trips).
struct LiquidProgress: View {
  var value: Double
  var tint: Color = .accentColor
  var height: CGFloat = 8
  var body: some View {
    let v = min(max(value, 0), 1)
    GeometryReader { g in
      ZStack(alignment: .leading) {
        Capsule().fill(Color(.tertiarySystemFill))
        ShaderClock { t in
          Capsule().fill(tint)
            .colorEffect(ShaderLibrary.wave(.float2(CGSize(width: max(height, g.size.width * v), height: height)), .float(t)))
        }
        .frame(width: v > 0 ? max(height, g.size.width * v) : 0)
        .animation(.quick, value: v)
      }
    }
    .frame(height: height)
    .accessibilityElement()
    .accessibilityValue("\(Int((v * 100).rounded())) percent")
  }
}

// MARK: Celebration

/// The one big moment: confetti in the app's colours plus a success tap. Fired by `Celebrations`.
@MainActor @Observable final class Celebration {
  static let shared = Celebration()
  private(set) var count = 0
  private(set) var message = ""
  func fire(_ message: String) { self.message = message; count += 1 }
}

struct ConfettiOverlay: View {
  @State private var celebration = Celebration.shared
  @State private var start: Date?
  @State private var pieces: [Piece] = []
  @State private var banner: String?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  struct Piece {
    var x: Double, vx: Double, vy: Double, spin: Double, size: Double, color: Color, round: Bool
  }
  private static let colors: [Color] = [.accentColor, .income, Color(hex: "#FF9500"), Color(hex: "#FF2D55"), Color(hex: "#FFB800"), Color(hex: "#007AFF"), Color(hex: "#AF52DE")]
  private let duration = 2.6

  var body: some View {
    ZStack(alignment: .top) {
      if let start {
        TimelineView(.animation) { ctx in
          let t = ctx.date.timeIntervalSince(start)
          Canvas { g, size in
            for p in pieces {
              let x = p.x * size.width + p.vx * t * 60
              let y = -20 + p.vy * t * 60 + 0.5 * 900 * t * t / 2
              guard y < size.height + 20 else { continue }
              var c = g
              c.opacity = max(0, 1 - max(0, t - duration + 0.6) / 0.6)
              c.translateBy(x: x, y: y)
              c.rotate(by: .degrees(p.spin * t * 360))
              let r = CGRect(x: -p.size / 2, y: -p.size / 3, width: p.size, height: p.round ? p.size : p.size * 0.6)
              c.fill(p.round ? Path(ellipseIn: r) : Path(r), with: .color(p.color))
            }
          }
        }
        .ignoresSafeArea()
        .transition(.opacity)
      }
      if let banner {
        Label(banner, systemImage: "sparkles").font(.headline).padding(.horizontal, 18).padding(.vertical, 12)
          .glassCapsule().padding(.top, 8).transition(.move(edge: .top).combined(with: .opacity))
      }
    }
    .allowsHitTesting(false)
    .sensoryFeedback(.success, trigger: celebration.count)
    .onChange(of: celebration.count) {
      withAnimation(.quick) { banner = celebration.message }
      if !reduceMotion {
        pieces = (0..<140).map { _ in
          Piece(x: .random(in: 0...1), vx: .random(in: -2...2), vy: .random(in: 0.5...4), spin: .random(in: -2...2),
                size: .random(in: 6...12), color: Self.colors.randomElement()!, round: Bool.random())
        }
        start = .now
      }
      let fired = celebration.count
      Task {
        try? await Task.sleep(for: .seconds(duration))
        guard fired == celebration.count else { return }
        withAnimation(.quick) { start = nil; banner = nil }
      }
    }
  }
}

/// When to celebrate: a savings goal reached, a month that ended under budget, and everyone settled up.
/// Each fires once; on the first run the current state is noted without celebrating old wins.
enum Celebrations {
  private static let d = AppGroup.defaults

  @MainActor static func check(_ context: ModelContext) {
    // Goals reached.
    let goals = (try? context.fetch(FetchDescriptor<Goal>())) ?? []
    let reached = Set(goals.filter { $0.archivedAt == nil && $0.target > 0 && $0.saved >= $0.target }.map(\.id))
    if let seen = d.stringArray(forKey: "celebratedGoals") {
      if let g = goals.first(where: { reached.contains($0.id) && !seen.contains($0.id) }) {
        Celebration.shared.fire("You reached \(g.name)!")
      }
      d.set(Array(Set(seen).union(reached)), forKey: "celebratedGoals")
    } else {
      d.set(Array(reached), forKey: "celebratedGoals")
    }

    // Everyone settled up (after owing something).
    let entries = (try? context.fetch(FetchDescriptor<SplitEntry>())) ?? []
    let open = Splits.balances(entries).values.contains { $0 != 0 }
    if d.bool(forKey: "hadOpenSplits") && !open && !entries.isEmpty { Celebration.shared.fire("All settled up!") }
    d.set(open, forKey: "hadOpenSplits")

    // Last month under budget (checked once, in the first days of a new month).
    let startDay = max(1, d.integer(forKey: PrefKey.monthStartDay))
    let month = Periods.month(containing: .now, startDay: startDay)
    let key = Int(month.start.timeIntervalSince1970)
    let last = d.integer(forKey: "budgetCelebratedMonth")
    guard last != key else { return }
    d.set(key, forKey: "budgetCelebratedMonth")
    guard last != 0 else { return }
    let budgets = ((try? context.fetch(FetchDescriptor<Budget>())) ?? []).filter { $0.period != "weekly" }
    guard !budgets.isEmpty else { return }
    let prev = Periods.month(containing: month.start.addingTimeInterval(-3600), startDay: startDay)
    let txns = (try? context.fetch(FetchDescriptor<Txn>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
    let cats = Dictionary(((try? context.fetch(FetchDescriptor<Category>())) ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    let trips = (try? context.fetch(FetchDescriptor<Trip>())) ?? []
    let progress = Budgets.progress(budgets, txns: TripMath.budgetTxns(txns, trips: trips), categories: cats, month: prev, week: prev)
    if !progress.isEmpty && progress.allSatisfy({ !$0.over }) {
      Celebration.shared.fire("You stayed under budget in \(prev.start.formatted(.dateTime.month(.wide)))!")
    }
  }
}
