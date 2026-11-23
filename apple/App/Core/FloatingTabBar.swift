import SwiftData
import SwiftUI

/// The floating Liquid Glass tab bar with the round + beside it, where the thumb rests.
/// Tap + for an expense; long-press for income, transfer, templates and screenshots.
struct FloatingTabBar: View {
  @Environment(Router.self) private var router
  private let tabs: [(AppTab, String, String)] = [
    (.home, "Home", "house.fill"), (.activity, "Activity", "list.bullet.rectangle.fill"),
    (.accounts, "Accounts", "creditcard.fill"), (.settings, "Settings", "gearshape.fill"),
  ]

  var body: some View {
    HStack(spacing: 10) {
      HStack(spacing: 0) {
        ForEach(tabs, id: \.0) { tab, title, icon in
          let selected = router.tab == tab
          Button {
            if router.tab == tab { router.popToRoot.toggle() } else { router.tab = tab }
          } label: {
            VStack(spacing: 2) {
              Image(systemName: icon).font(.system(size: 20, weight: .semibold)).frame(height: 24)
              Text(title).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { if selected { Capsule().fill(Color.primary.opacity(0.08)) } }
            .contentShape(Capsule())
          }
          .buttonStyle(.plain)
          .accessibilityLabel(title)
          .accessibilityAddTraits(selected ? .isSelected : [])
        }
      }
      .padding(4)
      .frame(height: 62)
      .glassCapsule()
      AddCircleButton()
    }
    .padding(.horizontal, 20)
    .padding(.bottom, 6)
    .sensoryFeedback(.selection, trigger: router.tab)
    .animation(.spring(duration: 0.3), value: router.tab)
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
