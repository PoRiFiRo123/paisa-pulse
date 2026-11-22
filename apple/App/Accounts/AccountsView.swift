import SwiftData
import SwiftUI

struct AccountsView: View {
  @Query(sort: \Account.sortOrder) private var accounts: [Account]
  @Query(filter: #Predicate<Txn> { $0.deletedAt == nil }) private var txns: [Txn]
  @Query(filter: #Predicate<PaymentCard> { $0.archivedAt == nil }) private var cards: [PaymentCard]
  @AppStorage(PrefKey.hideAmounts, store: AppGroup.defaults) private var hidden = false
  @State private var adding: AccountType?
  @Namespace private var ns

  var body: some View {
    let balances = Ledger.balances(accounts: accounts, txns: txns)
    let active = accounts.filter { $0.archivedAt == nil }.sorted { ($0.type.order, $0.sortOrder) < ($1.type.order, $1.sortOrder) }
    let net = Ledger.netWorth(accounts: accounts, balances: balances)
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Net worth").font(.subheadline).foregroundStyle(.secondary)
          Text(Money.format(net, hidden: hidden)).font(.system(size: 36, weight: .bold, design: .rounded)).monospacedDigit()
            .foregroundStyle(net < 0 ? Color.expense : .primary)
          NavigationLink { NetWorthView() } label: {
            Label("Net worth over time", systemImage: "chart.line.uptrend.xyaxis").font(.subheadline.weight(.medium))
          }
        }
        .padding(.horizontal, 4)

        if active.isEmpty {
          EmptyHint(title: "No accounts", icon: "creditcard", message: "Add your bank account, card or cash to start.")
        }
        // Wallet: cards overlap like Apple Wallet; tap one to open it.
        VStack(spacing: -128) {
          ForEach(Array(active.enumerated()), id: \.element.id) { i, a in
            NavigationLink {
              AccountDetailView(account: a).modifier(ZoomDestination(id: a.id, ns: ns))
            } label: {
              WalletCard(account: a, balance: balances[a.id] ?? 0, cards: cards.filter { $0.accountId == a.id })
                .shadow(color: .black.opacity(0.18), radius: 10, y: -4)
            }
            .buttonStyle(.plain)
            .modifier(ZoomSource(id: a.id, ns: ns))
            .zIndex(Double(i))
          }
        }
        .padding(.bottom, 8)

        let archived = accounts.filter { $0.archivedAt != nil }
        if !archived.isEmpty {
          Text("Archived").font(.headline).foregroundStyle(.secondary).padding(.top, 8)
          ForEach(archived) { a in
            NavigationLink { AccountDetailView(account: a) } label: {
              AccountRow(account: a, balance: balances[a.id] ?? 0).padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
          }
        }
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 120)
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle("Accounts")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button { adding = .bank } label: { Label("Bank account", systemImage: "building.columns.fill") }
          Button { adding = .card } label: { Label("Credit card", systemImage: "creditcard.fill") }
          Button { adding = .cash } label: { Label("Cash", systemImage: "banknote.fill") }
          Button { adding = .wallet } label: { Label("Wallet (Paytm, Amazon Pay…)", systemImage: "wallet.bifold.fill") }
        } label: { Image(systemName: "plus") }
        .accessibilityLabel("Add account")
      }
    }
    .sheet(item: $adding) { type in NavigationStack { AccountFormView(account: nil, initialType: type) } }
  }
}

/// iOS 18 zoom transition from a wallet card into its account.
struct ZoomSource: ViewModifier {
  let id: String; let ns: Namespace.ID
  func body(content: Content) -> some View { content.matchedTransitionSource(id: id, in: ns) }
}
struct ZoomDestination: ViewModifier {
  let id: String; let ns: Namespace.ID
  func body(content: Content) -> some View { content.navigationTransition(.zoom(sourceID: id, in: ns)) }
}

extension AccountType {
  var order: Int { switch self { case .bank: 0; case .card: 1; case .wallet: 2; case .cash: 3 } }
}

/// An account drawn as a card: gradient in the account colour, balance, and a peek of its linked cards.
struct WalletCard: View {
  let account: Account
  let balance: Int
  let cards: [PaymentCard]
  @AppStorage(PrefKey.hideAmounts, store: AppGroup.defaults) private var hidden = false

  var body: some View {
    let base = Color(hex: account.color)
    let primary = cards.first { $0.kind == "credit" } ?? cards.first
    ZStack(alignment: .topLeading) {
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .fill(LinearGradient(colors: [base, base.mix(with: .black, by: 0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
      // Soft light sweeps give the card some depth.
      Circle().fill(.white.opacity(0.10)).frame(width: 260).offset(x: 170, y: -120)
      Circle().fill(.white.opacity(0.06)).frame(width: 200).offset(x: -60, y: 110)
      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .top) {
          Image(systemName: account.icon).font(.system(size: 18, weight: .semibold))
            .frame(width: 34, height: 34).background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
          VStack(alignment: .leading, spacing: 1) {
            Text(account.name).font(.headline).lineLimit(1)
            Text(account.institution ?? account.type.label).font(.caption).opacity(0.75).lineLimit(1)
          }
          Spacer()
          if let p = primary { NetworkMark(network: p.network) }
          else if account.type == .cash { Image(systemName: "banknote").font(.title3).opacity(0.8) }
        }
        Spacer(minLength: 0)
        Text(balance < 0 ? (account.type == .card ? "Due" : "Overdrawn") : "Balance").font(.caption).opacity(0.75)
        Text(Money.format(balance, hidden: hidden)).font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
        HStack {
          if let l = account.last4 ?? primary?.last4 {
            Text("•••• \(l)").font(.system(.subheadline, design: .monospaced).weight(.medium)).opacity(0.85)
          }
          Spacer()
          if account.type != .card, !cards.isEmpty {
            HStack(spacing: -10) {
              ForEach(cards.prefix(3)) { c in
                RoundedRectangle(cornerRadius: 4).fill(Color(hex: c.color ?? account.color).mix(with: .white, by: 0.25))
                  .frame(width: 30, height: 20).overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.6), lineWidth: 1))
              }
            }
            Text("\(cards.count) card\(cards.count == 1 ? "" : "s")").font(.caption.weight(.semibold)).opacity(0.85)
          }
          if account.type == .card, let limit = account.creditLimit, limit > 0 {
            Text("\(Int(Double(max(0, -balance)) / Double(limit) * 100))% used").font(.caption.weight(.semibold)).opacity(0.85)
          }
        }
      }
      .padding(18)
    }
    .foregroundStyle(.white)
    .frame(height: 200)
    .contentShape(RoundedRectangle(cornerRadius: 24))
    .accessibilityElement(children: .combine)
  }
}

/// Network wordmark drawn in type (no logos copied).
struct NetworkMark: View {
  let network: String
  var body: some View {
    switch network {
    case "mastercard":
      HStack(spacing: -8) { Circle().fill(Color(hex: "#EB001B")).frame(width: 22); Circle().fill(Color(hex: "#F79E1B").opacity(0.9)).frame(width: 22) }
    case "visa": Text("VISA").font(.system(size: 20, weight: .heavy)).italic()
    case "rupay": Text("RuPay").font(.system(size: 17, weight: .heavy)).italic()
    case "amex": Text("AMEX").font(.system(size: 15, weight: .heavy)).padding(.horizontal, 5).background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
    default: Text(CardNumber.networkName(network).uppercased()).font(.system(size: 13, weight: .bold))
    }
  }
}

/// A payment card face (debit or credit), used in the account's card stack.
struct PaymentCardFace: View {
  let card: PaymentCard
  let accountColor: String
  var body: some View {
    let base = Color(hex: card.color ?? accountColor)
    ZStack(alignment: .topLeading) {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(LinearGradient(colors: [base.mix(with: .white, by: 0.12), base.mix(with: .black, by: 0.3)], startPoint: .topLeading, endPoint: .bottomTrailing))
      RoundedRectangle(cornerRadius: 5).fill(LinearGradient(colors: [Color(hex: "#E8C77A"), Color(hex: "#B8913F")], startPoint: .top, endPoint: .bottom))
        .frame(width: 38, height: 28).offset(x: 18, y: 52)
      VStack(alignment: .leading) {
        HStack {
          Text(card.kind == "credit" ? "CREDIT" : "DEBIT").font(.caption2.weight(.bold)).tracking(1.5).opacity(0.8)
          Spacer()
          NetworkMark(network: card.network)
        }
        Spacer()
        Text("••••  ••••  ••••  \(card.last4)").font(.system(.body, design: .monospaced).weight(.semibold))
        HStack {
          Text(card.nameOnCard ?? card.label ?? "").font(.caption.weight(.medium)).lineLimit(1).opacity(0.85)
          Spacer()
          if let e = card.expiryText { Text(e).font(.caption.monospacedDigit()).opacity(0.85) }
        }
      }
      .padding(16)
    }
    .foregroundStyle(.white)
    .frame(height: 170)
  }
}

/// Linked cards as a fanned stack; tap to spread them out.
struct CardStack: View {
  let cards: [PaymentCard]
  let accountColor: String
  @Binding var editing: PaymentCard?
  @Environment(\.modelContext) private var context
  @State private var spread = false

  var body: some View {
    VStack(spacing: spread ? 12 : -150) {
      ForEach(Array(cards.enumerated()), id: \.element.id) { i, c in
        PaymentCardFace(card: c, accountColor: accountColor)
          .scaleEffect(spread ? 1 : 1 - CGFloat(cards.count - 1 - i) * 0.04)
          .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
          .zIndex(Double(i))
          .onTapGesture { withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { if spread { editing = c } else { spread = true } } }
          .contextMenu {
            Button { editing = c } label: { Label("Edit", systemImage: "pencil") }
            Button(role: .destructive) { c.archivedAt = .now; try? context.save() } label: { Label("Remove Card", systemImage: "trash") }
          }
      }
    }
    .padding(.top, spread ? 0 : CGFloat(max(0, cards.count - 1)) * 0)
    .sensoryFeedback(.impact(weight: .light), trigger: spread)
    .overlay(alignment: .topTrailing) {
      if spread, cards.count > 1 {
        Button { withAnimation(.spring) { spread = false } } label: { Image(systemName: "rectangle.stack.fill") }
          .buttonStyle(.bordered).clipShape(Circle()).offset(x: 6, y: -14)
      }
    }
  }
}

/// Balance shown without a minus sign: a card you owe on says "due".
struct BalanceText: View {
  let account: Account
  let balance: Int
  var font: Font = .body.weight(.semibold)
  @AppStorage(PrefKey.hideAmounts, store: AppGroup.defaults) private var hidden = false

  var body: some View {
    VStack(alignment: .trailing, spacing: 0) {
      Text(Money.format(balance, hidden: hidden)).font(font).fontDesign(.rounded).monospacedDigit()
        .foregroundStyle(balance < 0 ? Color.expense : .primary)
      if balance < 0 {
        Text(account.type == .card ? "due" : "overdrawn").font(.caption2).foregroundStyle(Color.expense)
      }
    }
  }
}

struct AccountRow: View {
  let account: Account
  let balance: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 12) {
        CategoryBadge(icon: account.icon, color: account.color)
        VStack(alignment: .leading, spacing: 2) {
          Text(account.name).lineLimit(1)
          Text(subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
        }
        Spacer()
        BalanceText(account: account, balance: balance)
      }
      if account.type == .card, let limit = account.creditLimit, limit > 0 {
        let used = max(0, -balance)
        ProgressView(value: min(Double(used) / Double(limit), 1))
          .tint(Double(used) / Double(limit) > 0.3 ? .orange : Color(hex: account.color))
          .padding(.leading, 48)
      }
    }
  }

  private var subtitle: String {
    var parts: [String] = []
    if let i = account.institution, !i.isEmpty { parts.append(i) }
    if let l = account.last4 { parts.append("••\(l)") }
    if account.type == .card, let due = account.dueDay {
      parts.append("due " + Cards.nextDue(dueDay: due).formatted(.dateTime.day().month(.abbreviated)))
    }
    return parts.isEmpty ? account.type.label : parts.joined(separator: " · ")
  }
}

struct AccountDetailView: View {
  @Bindable var account: Account
  @Environment(Router.self) private var router
  @Environment(\.modelContext) private var context
  @Environment(\.dismiss) private var dismiss
  @Query(filter: #Predicate<Txn> { $0.deletedAt == nil }, sort: \Txn.occurredAt, order: .reverse) private var txns: [Txn]
  @Query private var accounts: [Account]
  @Query private var categories: [Category]
  @Query(filter: #Predicate<PaymentCard> { $0.archivedAt == nil }) private var allCards: [PaymentCard]
  @State private var editing = false
  @State private var confirmDelete = false
  @State private var editingCard: PaymentCard?
  @State private var addingCard = false

  var body: some View {
    let lookups = Lookups(accounts: accounts, categories: categories)
    let balance = Ledger.balances(accounts: accounts, txns: txns)[account.id] ?? 0
    let mine = txns.filter { $0.accountId == account.id || $0.toAccountId == account.id }
    let cards = allCards.filter { $0.accountId == account.id }.sorted { $0.createdAt < $1.createdAt }
    List {
      Section {
        WalletCard(account: account, balance: balance, cards: cards)
          .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
      }
      if account.type != .cash {
        Section {
          if !cards.isEmpty {
            CardStack(cards: cards, accountColor: account.color, editing: $editingCard)
              .padding(.vertical, 8).listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
          }
          Button { addingCard = true } label: {
            Label(account.type == .card ? (cards.isEmpty ? "Add Card Details" : "Add Add-on Card") : "Add Debit Card", systemImage: "creditcard.and.123")
          }
        } header: { Text(account.type == .card ? "Card" : "Linked cards") } footer: {
          Text(cards.isEmpty ? "Scan the card with the camera or type it in. Only the last 4 digits, network and expiry are kept." : "Tap the stack to spread it. Long-press a card to edit or remove it.")
        }
      }
      if account.type == .card { CardSection(account: account, balance: balance, txns: mine) }
      Section("Transactions") {
        if mine.isEmpty { Text("No transactions yet").foregroundStyle(.secondary) }
        ForEach(mine.prefix(100)) { t in
          NavigationLink { TransactionDetailView(txn: t) } label: { TxnRow(txn: t, lookups: lookups) }.txnActions(t)
        }
      }
    }
    .navigationTitle(account.name)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button { editing = true } label: { Label("Edit", systemImage: "pencil") }
          Button { router.add = AddRequest(type: .expense, accountId: account.id) } label: { Label("Add Transaction", systemImage: "plus") }
          Button {
            account.archivedAt = account.archivedAt == nil ? .now : nil
            try? context.save()
          } label: { Label(account.archivedAt == nil ? "Archive" : "Unarchive", systemImage: "archivebox") }
          Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
        } label: { Image(systemName: "ellipsis") }
      }
    }
    .sheet(isPresented: $editing) { NavigationStack { AccountFormView(account: account) } }
    .sheet(isPresented: $addingCard) { NavigationStack { CardFormView(card: nil, account: account) } }
    .sheet(item: $editingCard) { c in NavigationStack { CardFormView(card: c, account: account) } }
    .confirmationDialog(mine.isEmpty ? "Delete \(account.name)?" : "\(account.name) has transactions. Archive it instead?",
                        isPresented: $confirmDelete, titleVisibility: .visible) {
      if mine.isEmpty {
        Button("Delete", role: .destructive) { context.delete(account); try? context.save(); dismiss() }
      } else {
        Button("Archive") { account.archivedAt = .now; try? context.save(); dismiss() }
      }
    }
  }
}

/// Credit card tracking: this cycle's spend, due date, how much of the limit is used, Pay Bill.
struct CardSection: View {
  let account: Account
  let balance: Int
  let txns: [Txn]
  @Environment(Router.self) private var router

  var body: some View {
    let owed = max(0, -balance)
    Section("Card") {
      if let limit = account.creditLimit, limit > 0 {
        VStack(alignment: .leading, spacing: 6) {
          HStack {
            Text("Limit used")
            Spacer()
            Text("\(Money.format(owed)) of \(Money.format(limit))").foregroundStyle(.secondary)
          }
          ProgressView(value: min(Double(owed) / Double(limit), 1)).tint(Double(owed) / Double(limit) > 0.3 ? .orange : .accentColor)
          if Double(owed) / Double(limit) > 0.3 {
            Text("Keeping it under 30% helps your credit score.").font(.caption).foregroundStyle(.secondary)
          }
        }
        LabeledContent("Available", value: Money.format(max(0, limit - owed)))
      }
      if let s = account.statementDay {
        let cycle = Cards.cycle(statementDay: s)
        let spent = txns.filter { $0.type == .expense && $0.accountId == account.id && cycle.contains($0.occurredAt) }.reduce(0) { $0 + $1.amount }
        LabeledContent("This cycle", value: Money.format(spent))
        LabeledContent("Statement on", value: Calendar.current.date(byAdding: .day, value: -1, to: cycle.end)!.formatted(.dateTime.day().month(.abbreviated)))
      }
      if let d = account.dueDay {
        let due = Cards.nextDue(dueDay: d)
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: due).day ?? 0
        LabeledContent("Bill due") {
          Text(due.formatted(.dateTime.day().month(.abbreviated)) + (days <= 5 ? " · in \(days) days" : ""))
            .foregroundStyle(days <= 3 && owed > 0 ? Color.expense : .secondary)
        }
      }
      if owed > 0 {
        Button {
          router.add = AddRequest(type: .transfer)
        } label: { Label("Pay Bill (\(Money.format(owed)))", systemImage: "indianrupeesign.circle") }
      }
    }
  }
}

struct AccountFormView: View {
  let account: Account?
  var initialType: AccountType = .bank
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @Query private var all: [Account]
  @State private var name = ""
  @State private var type: AccountType = .bank
  @State private var institution = ""
  @State private var last4 = ""
  @State private var opening = ""
  @State private var owesOpening = false
  @State private var limit = ""
  @State private var statementDay = 0
  @State private var dueDay = 0
  @State private var color = "#5E5CE6"
  @State private var exclude = false

  var body: some View {
    Form {
      Section {
        TextField("Name, e.g. Axis Salary", text: $name)
        Picker("Type", selection: $type) { ForEach(AccountType.allCases) { Text($0.label).tag($0) } }
        TextField("Bank (optional)", text: $institution)
        if type == .bank || type == .card {
          TextField("Last 4 digits (optional)", text: $last4).keyboardType(.numberPad)
        }
      }
      Section {
        TextField(type == .card ? "Amount owed now" : "Current balance", text: $opening).keyboardType(.decimalPad)
        if type != .card { Toggle("Overdrawn (negative)", isOn: $owesOpening) }
      } footer: {
        Text(account == nil ? "Your balance today. Transactions you add change it from here." : "Balance before your first transaction.")
      }
      if type == .card {
        Section("Card") {
          TextField("Credit limit", text: $limit).keyboardType(.decimalPad)
          Picker("Statement day", selection: $statementDay) {
            Text("Not set").tag(0)
            ForEach(1...28, id: \.self) { Text("\($0)").tag($0) }
          }
          Picker("Bill due day", selection: $dueDay) {
            Text("Not set").tag(0)
            ForEach(1...31, id: \.self) { Text("\($0)").tag($0) }
          }
        }
      }
      Section("Colour") {
        ColorRow(selection: $color)
        Toggle("Leave out of net worth", isOn: $exclude)
      }
    }
    .navigationTitle(account == nil ? "New Account" : "Edit Account")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
      }
    }
    .onAppear(perform: load)
  }

  private func load() {
    guard let a = account else { color = Palette.colors[all.count % Palette.colors.count]; type = initialType; return }
    name = a.name; type = a.type; institution = a.institution ?? ""; last4 = a.last4 ?? ""
    let ob = a.type == .card ? -a.openingBalance : a.openingBalance
    opening = ob == 0 ? "" : String(Double(abs(ob)) / 100)
    owesOpening = a.type != .card && a.openingBalance < 0
    limit = a.creditLimit.map { String($0 / 100) } ?? ""
    statementDay = a.statementDay ?? 0; dueDay = a.dueDay ?? 0; color = a.color; exclude = a.excludeFromTotals
  }

  private func save() {
    let paise = Money.parse(opening) ?? 0
    let signed = type == .card ? -paise : (owesOpening ? -paise : paise)
    let digits = String(last4.filter(\.isNumber).suffix(4))
    let a = account ?? Account(name: name, type: type, color: color, icon: type.defaultIcon, sortOrder: all.count)
    a.name = name.trimmingCharacters(in: .whitespaces); a.type = type
    a.institution = institution.isEmpty ? nil : institution
    a.last4 = digits.count == 4 ? digits : nil
    a.openingBalance = signed
    a.creditLimit = type == .card ? Money.parse(limit) : nil
    a.statementDay = type == .card && statementDay > 0 ? statementDay : nil
    a.dueDay = type == .card && dueDay > 0 ? dueDay : nil
    a.color = color; a.icon = type.defaultIcon; a.excludeFromTotals = exclude; a.updatedAt = .now
    if account == nil {
      context.insert(a)
      if type == .card, let l = a.last4 { context.insert(PaymentCard(accountId: a.id, kind: "credit", last4: l, color: a.color)) }
    }
    try? context.save()
    Notifier.refresh(context)
    dismiss()
  }
}

struct ColorRow: View {
  @Binding var selection: String
  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 10) {
        ForEach(Palette.colors, id: \.self) { hex in
          Circle().fill(Color(hex: hex)).frame(width: 30, height: 30)
            .overlay { if selection == hex { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) } }
            .onTapGesture { selection = hex }
            .accessibilityLabel("Colour \(hex)")
            .accessibilityAddTraits(selection == hex ? .isSelected : [])
        }
      }
      .padding(.vertical, 4)
    }
  }
}
