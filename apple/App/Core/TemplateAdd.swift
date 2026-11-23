import SwiftData
import SwiftUI

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
