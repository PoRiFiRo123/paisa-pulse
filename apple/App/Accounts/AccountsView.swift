import SwiftData
import SwiftUI

struct AccountsView: View {
  @Query(sort: \Account.sortOrder) private var accounts: [Account]
  @Query(filter: #Predicate<Txn> { $0.deletedAt == nil }) private var txns: [Txn]
  @AppStorage(PrefKey.hideAmounts, store: AppGroup.defaults) private var hidden = false
  @State private var adding = false

  var body: some View {
    let balances = Ledger.balances(accounts: accounts, txns: txns)
    let active = accounts.filter { $0.archivedAt == nil }
    let net = Ledger.netWorth(accounts: accounts, balances: balances)
    List {
      Section {
        VStack(alignment: .leading, spacing: 6) {
          Text("Net worth").font(.subheadline).foregroundStyle(.secondary)
          Text(Money.format(net, hidden: hidden))
            .font(.system(size: 36, weight: .bold, design: .rounded)).monospacedDigit()
            .foregroundStyle(net < 0 ? Color.expense : .primary)
          Text(net < 0 ? "You owe more than you have" : "Across \(active.count) accounts")
            .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        NavigationLink { NetWorthView() } label: { Label("Net worth over time", systemImage: "chart.line.uptrend.xyaxis") }
      }
      ForEach(AccountType.allCases) { type in
        let items = active.filter { $0.type == type }
        if !items.isEmpty {
          Section(type.plural) {
            ForEach(items) { a in
              NavigationLink { AccountDetailView(account: a) } label: {
                AccountRow(account: a, balance: balances[a.id] ?? 0)
              }
            }
          }
        }
      }
      let archived = accounts.filter { $0.archivedAt != nil }
      if !archived.isEmpty {
        Section("Archived") {
          ForEach(archived) { a in
            NavigationLink { AccountDetailView(account: a) } label: { AccountRow(account: a, balance: balances[a.id] ?? 0) }
          }
        }
      }
    }
    .navigationTitle("Accounts")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add account")
      }
    }
    .sheet(isPresented: $adding) { NavigationStack { AccountFormView(account: nil) } }
    .overlay {
      if accounts.isEmpty {
        EmptyHint(title: "No accounts", icon: "creditcard", message: "Add your bank account, card or cash to start.")
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
  @State private var editing = false
  @State private var confirmDelete = false

  var body: some View {
    let lookups = Lookups(accounts: accounts, categories: categories)
    let balance = Ledger.balances(accounts: accounts, txns: txns)[account.id] ?? 0
    let mine = txns.filter { $0.accountId == account.id || $0.toAccountId == account.id }
    List {
      Section {
        HStack(spacing: 14) {
          CategoryBadge(icon: account.icon, color: account.color, size: 52)
          VStack(alignment: .leading) {
            Text(account.type.label).font(.subheadline).foregroundStyle(.secondary)
            BalanceText(account: account, balance: balance, font: .system(size: 32, weight: .bold))
          }
        }
        .padding(.vertical, 6)
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
    guard let a = account else { color = Palette.colors[all.count % Palette.colors.count]; return }
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
    if account == nil { context.insert(a) }
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
