import SwiftData
import SwiftUI

/// The floating Liquid Glass tab bar with the round + beside it, where the thumb rests.
/// Tap + for an expense; long-press for income, transfer, templates and screenshots.
struct FloatingTabBar: View {
  @Environment(Router.self) private var router
  /// Where the finger is while sliding across the bar (nil when not touching).
  @State private var dragX: CGFloat?
  @State private var hover: AppTab?
  private let tabs: [(AppTab, String, String)] = [
    (.home, "Home", "house.fill"), (.activity, "Activity", "list.bullet.rectangle.fill"),
    (.accounts, "Accounts", "creditcard.fill"), (.settings, "Settings", "gearshape.fill"),
  ]

  var body: some View {
    HStack(spacing: 10) {
      GeometryReader { geo in
        let w = geo.size.width / CGFloat(tabs.count)
        let index = tabs.firstIndex { $0.0 == router.tab } ?? 0
        let lensX = dragX.map { min(max($0 - w / 2, 0), geo.size.width - w) } ?? CGFloat(index) * w
        ZStack(alignment: .leading) {
          // The lens: sits under the selected tab and follows your finger, like the iOS 26 tab bar.
          lens(dragging: dragX != nil)
            .frame(width: w, height: geo.size.height)
            .scaleEffect(dragX != nil ? 1.12 : 1)
            .offset(x: lensX)
          HStack(spacing: 0) {
            ForEach(tabs, id: \.0) { tab, title, icon in
              let lit = (hover ?? router.tab) == tab
              VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold)).frame(height: 24)
                Text(title).font(.system(size: 10, weight: .medium))
              }
              .foregroundStyle(lit ? Color.accentColor : Color.primary)
              .scaleEffect(dragX != nil && lit ? 1.08 : 1)
              .frame(width: w, height: geo.size.height)
              .contentShape(Rectangle())
              .accessibilityElement(children: .ignore)
              .accessibilityLabel(title)
              .accessibilityAddTraits(router.tab == tab ? [.isButton, .isSelected] : .isButton)
              .accessibilityAction { router.tab = tab }
            }
          }
        }
        .contentShape(Capsule())
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { v in
              let i = min(max(Int(v.location.x / w), 0), tabs.count - 1)
              // Only show the sliding lens once the finger actually moves; a tap just selects.
              if abs(v.translation.width) > 6 || dragX != nil {
                withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.8)) { dragX = v.location.x }
              }
              if hover != tabs[i].0 { hover = tabs[i].0 }
            }
            .onEnded { v in
              let i = min(max(Int(v.location.x / w), 0), tabs.count - 1)
              let tab = tabs[i].0
              withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                if tab == router.tab && dragX == nil { router.popToRoot.toggle() } else { router.tab = tab }
                dragX = nil; hover = nil
              }
            }
        )
      }
      .padding(4)
      .frame(height: 62)
      .glassCapsule()
      AddCircleButton()
    }
    .padding(.horizontal, 20)
    .padding(.bottom, 6)
    .sensoryFeedback(.selection, trigger: hover)
    .sensoryFeedback(.selection, trigger: router.tab)
  }

  @ViewBuilder private func lens(dragging: Bool) -> some View {
    if #available(iOS 26.0, *), dragging {
      Capsule().fill(Color.primary.opacity(0.04)).glassEffect(.regular.interactive(), in: .capsule)
    } else {
      Capsule().fill(Color.primary.opacity(dragging ? 0.14 : 0.08))
    }
  }
}

struct AddCircleButton: View {
  @Environment(Router.self) private var router
  @Environment(\.modelContext) private var context
  @Query(sort: \TxnTemplate.sortOrder) private var templates: [TxnTemplate]
  @State private var tapped = 0

  var body: some View {
    Menu {
      Button { router.add = AddRequest(type: .income) } label: { Label("Income", systemImage: "arrow.down.left") }
      Button { router.add = AddRequest(type: .transfer) } label: { Label("Transfer", systemImage: "arrow.left.arrow.right") }
      Button { router.add = AddRequest(type: .expense) } label: { Label("Expense", systemImage: "arrow.up.right") }
      if !templates.isEmpty {
        Section("Templates") {
          ForEach(templates.prefix(3)) { t in
            Button { TemplateAdd.run(t, context: context, router: router) } label: {
              Label("\(t.name) · \(Money.format(t.amount))", systemImage: "bolt.fill")
            }
          }
        }
      }
      Divider()
      Button { router.capture = true } label: { Label("From Screenshots", systemImage: "photo.on.rectangle") }
    } label: {
      Image(systemName: "plus")
        .font(.system(size: 26, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 62, height: 62)
        .addCircleBackground()
        .contentShape(Circle())
    } primaryAction: {
      tapped += 1
      router.add = AddRequest(type: .expense)
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .sensoryFeedback(.impact(weight: .medium), trigger: tapped)
    .accessibilityLabel("Add expense")
    .accessibilityHint("Long-press for income, transfer and templates")
  }
}

private extension View {
  /// Accent-tinted Liquid Glass on iOS 26, a solid accent circle before.
  @ViewBuilder func addCircleBackground() -> some View {
    if #available(iOS 26.0, *) {
      self.glassEffect(.regular.tint(.accentColor).interactive(), in: .circle)
    } else {
      self.background(Circle().fill(Color.accentColor).shadow(color: .black.opacity(0.2), radius: 8, y: 3))
    }
  }
}

/// A template adds straight away, with Undo (Home's Quick add row and the + menu).
enum TemplateAdd {
  @MainActor static func run(_ t: TxnTemplate, context: ModelContext, router: Router) {
    let accounts = ((try? context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []).filter { $0.archivedAt == nil }
    let last = AppGroup.defaults.string(forKey: PrefKey.lastAccountId) ?? ""
    guard let accountId = t.accountId.flatMap({ id in accounts.first { $0.id == id }?.id })
      ?? accounts.first(where: { $0.id == last })?.id ?? accounts.first?.id else { return }
    let txn = Txn(type: t.type, amount: t.amount, accountId: accountId, toAccountId: t.type == .transfer ? t.toAccountId : nil,
                  categoryId: t.type == .transfer ? nil : t.categoryId, payee: t.payee ?? t.name, source: "template")
    context.insert(txn)
    try? context.save()
    WidgetRefresh.now()
    router.show("Added \(t.name) · \(Money.format(t.amount))") { txn.deletedAt = .now; try? context.save(); WidgetRefresh.now() }
  }
}
