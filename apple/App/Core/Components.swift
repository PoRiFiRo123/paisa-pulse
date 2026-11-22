import SwiftData
import SwiftUI

/// Rounded square with a white SF Symbol, like Settings icons.
struct CategoryBadge: View {
  let icon: String
  let color: String
  var size: CGFloat = 36

  var body: some View {
    Image(systemName: icon)
      .font(.system(size: size * 0.46, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: size, height: size)
      .background(Color(hex: color).gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
      .accessibilityHidden(true)
  }
}

/// An amount with no minus sign: soft red for expenses, green for income, grey for transfers.
struct AmountText: View {
  let amount: Int
  let type: TxnType
  var font: Font = .body.weight(.semibold)
  @AppStorage(PrefKey.hideAmounts, store: AppGroup.defaults) private var hidden = false

  var body: some View {
    Text(Money.format(amount, hidden: hidden))
      .font(font)
      .fontDesign(.rounded)
      .monospacedDigit()
      .foregroundStyle(type.color)
      .accessibilityLabel("\(type == .income ? "Received" : type == .transfer ? "Moved" : "Spent") \(Money.format(amount, hidden: hidden))")
  }
}

/// Lookups built once per screen from @Query results.
struct Lookups {
  var accounts: [String: Account] = [:]
  var categories: [String: Category] = [:]

  init(accounts: [Account], categories: [Category]) {
    self.accounts = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    self.categories = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
  }

  func title(_ t: Txn) -> String {
    if let p = t.payee, !p.isEmpty { return p }
    if t.type == .transfer { return "Transfer" }
    return t.categoryId.flatMap { categories[$0]?.name } ?? (t.type == .income ? "Income" : "Expense")
  }

  func subtitle(_ t: Txn) -> String {
    let account = accounts[t.accountId]?.name ?? "Account"
    if t.type == .transfer {
      return "\(account) → \(t.toAccountId.flatMap { accounts[$0]?.name } ?? "Account")"
    }
    let category = t.categoryId.flatMap { categories[$0]?.name } ?? "Uncategorised"
    return "\(category) · \(account)"
  }

  func badge(_ t: Txn) -> (icon: String, color: String) {
    if t.type == .transfer { return ("arrow.left.arrow.right", "#8E8E93") }
    if let c = t.categoryId.flatMap({ categories[$0] }) { return (c.icon, c.color) }
    return (t.type == .income ? "arrow.down.left" : "questionmark", "#8E8E93")
  }
}

/// A known merchant: its logo (when Merchant logos is on) or a monogram in the brand colour.
struct MerchantBadge: View {
  let brand: Brand
  var size: CGFloat = 36
  @AppStorage(PrefKey.merchantLogos, store: AppGroup.defaults) private var logos = false

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
    ZStack {
      shape.fill(Color(hex: brand.color).gradient)
      Text(brand.monogram)
        .font(.system(size: size * 0.48, weight: .bold, design: .rounded))
        .foregroundStyle(Brands.onColor(brand.color))
      if logos, let url = brand.logoURL() {
        AsyncImage(url: url) { phase in
          if let image = phase.image {
            image.resizable().scaledToFit().padding(size * 0.14).frame(width: size, height: size).background(.white, in: shape)
          }
        }
      }
    }
    .frame(width: size, height: size)
    .clipShape(shape)
    .accessibilityHidden(true)
  }
}

struct TxnRow: View {
  let txn: Txn
  let lookups: Lookups
  var showTime = true

  var body: some View {
    let badge = lookups.badge(txn)
    HStack(spacing: 12) {
      if txn.type != .transfer, let brand = Brands.match(txn.payee) {
        MerchantBadge(brand: brand)
      } else {
        CategoryBadge(icon: badge.icon, color: badge.color)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(lookups.title(txn)).font(.body).lineLimit(1)
        HStack(spacing: 4) {
          if txn.splitShare != nil { Image(systemName: "person.2.fill").font(.caption2) }
          Text(lookups.subtitle(txn) + (showTime ? " · " + txn.occurredAt.formatted(date: .omitted, time: .shortened) : ""))
            .lineLimit(1)
        }
        .font(.footnote).foregroundStyle(.secondary)
      }
      Spacer(minLength: 8)
      VStack(alignment: .trailing, spacing: 2) {
        AmountText(amount: txn.amount, type: txn.type)
        if let share = txn.splitShare {
          Text("yours \(Money.format(share))").font(.caption2).foregroundStyle(.secondary)
        }
      }
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
  }
}

/// Swipe and long-press actions shared by every transaction list.
struct TxnActions: ViewModifier {
  let txn: Txn
  @Environment(\.modelContext) private var context
  @Environment(Router.self) private var router

  func body(content: Content) -> some View {
    content
      .swipeActions(edge: .trailing, allowsFullSwipe: true) {
        Button(role: .destructive) { TxnOps.delete(txn, context: context, router: router) } label: {
          Label("Delete", systemImage: "trash")
        }
      }
      .swipeActions(edge: .leading) {
        Button { TxnOps.duplicate(txn, context: context, router: router) } label: {
          Label("Duplicate", systemImage: "plus.square.on.square")
        }
        .tint(.indigo)
      }
      .contextMenu {
        Button { router.add = AddRequest(type: txn.type, editing: txn) } label: { Label("Edit", systemImage: "pencil") }
        Button { TxnOps.duplicate(txn, context: context, router: router) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
        Divider()
        Button(role: .destructive) { TxnOps.delete(txn, context: context, router: router) } label: { Label("Delete", systemImage: "trash") }
      }
  }
}

extension View {
  func txnActions(_ txn: Txn) -> some View { modifier(TxnActions(txn: txn)) }
}

enum TxnOps {
  static func delete(_ t: Txn, context: ModelContext, router: Router) {
    t.deletedAt = .now
    try? context.save()
    WidgetRefresh.now()
    router.show("Deleted") {
      t.deletedAt = nil
      try? context.save()
      WidgetRefresh.now()
    }
  }

  static func duplicate(_ t: Txn, context: ModelContext, router: Router) {
    let copy = Txn(type: t.type, amount: t.amount, accountId: t.accountId, toAccountId: t.toAccountId,
                   categoryId: t.categoryId, payee: t.payee, note: t.note, occurredAt: .now)
    context.insert(copy)
    try? context.save()
    WidgetRefresh.now()
    router.show("Duplicated") {
      context.delete(copy)
      try? context.save()
    }
  }
}

/// Section header text with a trailing total, used by day groups.
struct DayHeader: View {
  let date: Date
  let total: Int

  var body: some View {
    HStack {
      Text(Self.label(date))
      Spacer()
      if total > 0 { Text(Money.format(total)).foregroundStyle(Color.expense) }
    }
  }

  static func label(_ d: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(d) { return "Today" }
    if cal.isDateInYesterday(d) { return "Yesterday" }
    return d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
  }
}

/// Empty state built on the system's ContentUnavailableView.
struct EmptyHint: View {
  let title: String
  let icon: String
  let message: String
  var body: some View {
    ContentUnavailableView(title, systemImage: icon, description: Text(message))
  }
}
