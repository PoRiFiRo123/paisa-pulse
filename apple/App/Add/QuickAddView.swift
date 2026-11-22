import SwiftData
import SwiftUI

struct QuickAddView: View {
  let request: AddRequest
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @Environment(Router.self) private var router
  @Query(filter: #Predicate<Account> { $0.archivedAt == nil }, sort: \Account.sortOrder) private var accounts: [Account]
  @Query(filter: #Predicate<Category> { $0.archivedAt == nil }, sort: \Category.sortOrder) private var categories: [Category]
  @Query(sort: \Friend.name) private var friends: [Friend]
  @Query(filter: #Predicate<PaymentCard> { $0.archivedAt == nil }) private var cards: [PaymentCard]
  @AppStorage(PrefKey.lastAccountId, store: AppGroup.defaults) private var lastAccountId = ""

  @State private var type: TxnType
  @State private var expr: String
  @State private var payee: String
  @State private var note: String
  @State private var categoryId: String?
  @State private var accountId: String?
  @State private var toAccountId: String?
  @State private var date: Date
  @State private var split = SplitSetup()
  @State private var cardId: String?
  @State private var currency: String
  @State private var rate: Double?
  @State private var editingRate = false
  @State private var rateText = ""
  @State private var detent: PresentationDetent = .large
  @State private var pickingCategory = false
  @State private var error: String?

  init(request: AddRequest) {
    self.request = request
    let e = request.editing
    _type = State(initialValue: e?.type ?? request.type)
    _expr = State(initialValue: e.map { Self.exprText($0.amount) } ?? "0")
    _payee = State(initialValue: e?.payee ?? "")
    _note = State(initialValue: e?.note ?? "")
    _categoryId = State(initialValue: e?.categoryId)
    _accountId = State(initialValue: e?.accountId ?? request.accountId)
    _toAccountId = State(initialValue: e?.toAccountId)
    _date = State(initialValue: e?.occurredAt ?? request.date ?? .now)
    _cardId = State(initialValue: e?.cardId)
    _currency = State(initialValue: e?.currency ?? "INR")
    if let e, let orig = e.originalAmount, e.currency != nil, e.currency != "INR" {
      _expr = State(initialValue: orig % 100 == 0 ? String(orig / 100) : String(format: "%.2f", Double(orig) / 100))
      _rate = State(initialValue: Double(e.amount) / Double(orig))
    }
  }

  private static func exprText(_ paise: Int) -> String {
    paise % 100 == 0 ? String(paise / 100) : String(format: "%.2f", Double(paise) / 100)
  }

  /// What was typed, in the chosen currency's minor units.
  private var enteredMinor: Int? {
    guard let d = KeypadMath.evaluate(expr) else { return nil }
    return Money.paise(from: d)
  }
  /// Always INR paise (converted when a foreign currency is picked).
  private var amountPaise: Int? {
    guard let m = enteredMinor else { return nil }
    if currency == "INR" { return m }
    guard let rate else { return nil }
    return Currency.toPaise(m, rate: rate)
  }

  @FocusState private var typing: Bool

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        Picker("Type", selection: $type) {
          ForEach(TxnType.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal).padding(.top, 4)

        amountDisplay.padding(.vertical, detent == .large ? 14 : 6)

        if detent == .large {
          details
            .scrollDismissesKeyboard(.interactively)
            // Fade the list into the keypad instead of cutting rows off.
            .mask(VStack(spacing: 0) { Color.black; LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 18) })
        } else { Spacer(minLength: 0) }

        if !typing {
          Keypad(expr: $expr)
            .padding(.horizontal).padding(.top, 10).padding(.bottom, 8)
            .background {
              UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous)
                .fill(Color(.systemGroupedBackground))
                .shadow(color: .black.opacity(0.12), radius: 10, y: -2)
                .ignoresSafeArea(edges: .bottom)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
      }
      .animation(.snappy, value: typing)
      .background(Color(.systemGroupedBackground))
      .navigationTitle(request.editing == nil ? "New \(type.label)" : "Edit \(type.label)")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
          Button { save() } label: { Image(systemName: "checkmark") }
            .buttonStyle(.borderedProminent)
            .disabled((amountPaise ?? 0) <= 0)
            .accessibilityLabel("Save")
        }
      }
      .sheet(isPresented: $pickingCategory) {
        CategoryPicker(kind: type == .income ? .income : .expense, selection: $categoryId)
      }
      .alert("Rupees per 1 \(currency)", isPresented: $editingRate) {
        TextField("e.g. 83.25", text: $rateText).keyboardType(.decimalPad)
        Button("Use") { if let r = Double(rateText), r > 0 { rate = r } }
        Button("Cancel", role: .cancel) {}
      } message: { Text("Use the rate on your card statement or forex card for an exact match.") }
      .alert("Can't save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
        Button("OK", role: .cancel) {}
      } message: { Text(error ?? "") }
      .onAppear(perform: defaults)
      .onChange(of: type) { _, _ in
        if let c = categoryId, categories.first(where: { $0.id == c })?.kind != (type == .income ? .income : .expense) { categoryId = nil }
      }
    }
    .presentationDetents([.medium, .large], selection: $detent)
    .presentationDragIndicator(.visible)
    .sensoryFeedback(.success, trigger: router.toast?.id)
  }

  private var amountDisplay: some View {
    VStack(spacing: 2) {
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Menu {
          ForEach(Currency.common, id: \.code) { c in
            Button { pickCurrency(c.code) } label: { Text("\(c.code) · \(c.name)") }
          }
        } label: {
          Text(Currency.symbol(currency)).font(.system(size: currency == "INR" ? 30 : 22, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
        }
        .accessibilityLabel("Currency \(currency)")
        Text(expr)
          .font(.system(size: 56, weight: .bold, design: .rounded))
          .foregroundStyle(type.color)
          .lineLimit(1).minimumScaleFactor(0.4)
          .contentTransition(.numericText())
          .animation(.snappy, value: expr)
      }
      if currency != "INR" {
        Button {
          rateText = rate.map { String(format: "%.4f", $0) } ?? ""; editingRate = true
        } label: {
          Text(amountPaise.map { "≈ \(Money.format($0)) · 1 \(currency) = ₹\(String(format: "%.2f", rate ?? 0))" } ?? "Tap to set the rate for \(currency)")
            .font(.subheadline)
        }
      } else if KeypadMath.isExpression(expr), let p = amountPaise {
        Text("= \(Money.format(p))").font(.subheadline).foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Amount \(amountPaise.map { Money.format($0) } ?? "zero")")
  }

  private var kindCategories: [Category] {
    let kind: CategoryKind = type == .income ? .income : .expense
    return categories.filter { $0.kind == kind && $0.parentId == nil }
  }

  private var details: some View {
    Form {
      Section {
        TextField(type == .transfer ? "Note (optional)" : "Payee, e.g. Swiggy", text: $payee)
          .textInputAutocapitalization(.words)
          .focused($typing)
          .submitLabel(.done)
          .onSubmit { typing = false }
        if type != .transfer {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
              if let c = categoryId.flatMap({ id in categories.first { $0.id == id } }), c.parentId != nil {
                chip(c, selected: true)
              }
              ForEach(kindCategories) { c in chip(c, selected: categoryId == c.id) }
              Button { pickingCategory = true } label: {
                Label("More", systemImage: "ellipsis").font(.subheadline).padding(.vertical, 7).padding(.horizontal, 12)
                  .background(Color(.tertiarySystemFill), in: Capsule())
              }
              .buttonStyle(.plain)
            }
          }
          .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        }
      }
      Section {
        Picker(type == .transfer ? "From" : "Account", selection: $accountId) {
          ForEach(accounts) { Text($0.displayName).tag(String?.some($0.id)) }
        }
        if type == .transfer {
          Picker("To", selection: $toAccountId) {
            Text("Choose").tag(String?.none)
            ForEach(accounts.filter { $0.id != accountId }) { Text($0.displayName).tag(String?.some($0.id)) }
          }
        }
        let accountCards = cards.filter { $0.accountId == accountId }
        if type != .income, !accountCards.isEmpty {
          Picker("Paid with", selection: $cardId) {
            Text("Account").tag(String?.none)
            ForEach(accountCards) { Text($0.title).tag(String?.some($0.id)) }
          }
        }
        DatePicker("Date", selection: $date, in: ...Date.now.addingTimeInterval(86_400 * 366))
        if type == .expense {
          NavigationLink {
            SplitEditorView(setup: $split, total: amountPaise ?? 0)
          } label: {
            LabeledContent("Split") {
              if split.isEmpty { Text("No") } else {
                let r = SplitMath.compute(total: amountPaise ?? 0, split)
                Text(split.payer == nil ? "\(split.people.count + (split.includeMe ? 1 : 0)) people · yours \(Money.format(r.myShare))"
                     : "\(friends.first { $0.id == split.payer }?.name ?? "They") paid · you owe \(Money.format(r.myShare))")
              }
            }
          }
        }
      }
    }
    .scrollContentBackground(.hidden)
    .contentMargins(.top, 0, for: .scrollContent)
  }

  private func chip(_ c: Category, selected: Bool) -> some View {
    Button {
      categoryId = selected ? nil : c.id
    } label: {
      HStack(spacing: 6) {
        Image(systemName: c.icon).font(.caption.weight(.semibold))
        Text(c.name).font(.subheadline).lineLimit(1)
      }
      .padding(.vertical, 7).padding(.horizontal, 12)
      .foregroundStyle(selected ? .white : .primary)
      .background(selected ? Color(hex: c.color) : Color(.tertiarySystemFill), in: Capsule())
    }
    .buttonStyle(.plain)
    .sensoryFeedback(.selection, trigger: selected)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private func pickCurrency(_ code: String) {
    currency = code
    rate = nil
    guard code != "INR" else { return }
    Task { if let r = await Currency.rates(), let v = r.inrPer[code] { rate = v } else { rateText = ""; editingRate = true } }
  }

  private func defaults() {
    if accountId == nil || !accounts.contains(where: { $0.id == accountId }) {
      accountId = accounts.first(where: { $0.id == lastAccountId })?.id ?? accounts.first?.id
    }
    if let t = request.editing {
      let old = ((try? context.fetch(FetchDescriptor<SplitEntry>())) ?? []).filter { $0.txnId == t.id }
      if !old.isEmpty {
        split.people = old.map(\.friendId)
        split.groupId = old.first?.groupId
        if let share = t.splitShare, share != SplitMath.compute(total: t.amount, split).myShare {
          split.mode = .amount
          split.values = Dictionary(uniqueKeysWithValues: old.map { ($0.friendId, $0.amount) })
          split.values["me"] = share
          split.includeMe = share > 0
        }
      }
    }
  }

  private func save() {
    guard let amount = amountPaise, amount > 0 else { error = "Enter an amount."; return }
    guard let accountId else { error = "Add an account first (Accounts tab)."; return }
    if type == .transfer, toAccountId == nil || toAccountId == accountId { error = "Pick a different account to move money to."; return }
    let name = payee.trimmingCharacters(in: .whitespaces)
    let result = SplitMath.compute(total: amount, split)
    if type == .expense, !split.isEmpty, !result.valid { error = "The split amounts don't add up to the total."; return }
    // A friend paid: nothing left your account yet, so it's only "you owe them" (settle up later).
    if type == .expense, let payer = split.payer, request.editing == nil {
      for (f, v) in result.entries {
        context.insert(SplitEntry(friendId: f, amount: v, note: name.isEmpty ? note.nilIfEmpty : name, groupId: split.groupId, occurredAt: date))
      }
      try? context.save()
      let who = friends.first { $0.id == payer }?.name ?? "them"
      router.show("You owe \(who) \(Money.format(result.myShare))")
      dismiss()
      return
    }
    let txn: Txn
    if let t = request.editing {
      txn = t
      t.type = type; t.amount = amount; t.accountId = accountId
      t.toAccountId = type == .transfer ? toAccountId : nil
      t.categoryId = type == .transfer ? nil : categoryId
      t.payee = name.isEmpty ? nil : name; t.occurredAt = date; t.updatedAt = .now
    } else {
      txn = Txn(type: type, amount: amount, accountId: accountId, toAccountId: toAccountId, categoryId: categoryId,
                payee: name.isEmpty ? nil : name, note: note.isEmpty ? nil : note, occurredAt: date)
      context.insert(txn)
    }
    txn.cardId = type == .income ? nil : cardId
    txn.currency = currency == "INR" ? nil : currency
    txn.originalAmount = currency == "INR" ? nil : enteredMinor
    // Splits: recreate this expense's shares.
    let old = ((try? context.fetch(FetchDescriptor<SplitEntry>())) ?? []).filter { $0.txnId == txn.id }
    old.forEach { context.delete($0) }
    var owed: [String: Int] = [:]
    if type == .expense, !split.isEmpty, split.payer == nil {
      txn.splitShare = result.myShare
      for (f, v) in result.entries {
        context.insert(SplitEntry(friendId: f, txnId: txn.id, amount: v, note: txn.payee, groupId: split.groupId, occurredAt: date))
      }
      owed = result.entries
    } else {
      txn.splitShare = nil
    }
    lastAccountId = accountId
    try? context.save()
    WidgetRefresh.now()
    Notifier.checkBudgets(context)
    let editing = request.editing != nil
    router.show(editing ? "Saved" : "Added \(Money.format(amount))", undo: editing ? nil : { [txn] in
      txn.deletedAt = .now
      try? context.save()
      WidgetRefresh.now()
    })
    dismiss()
    if !editing, !owed.isEmpty {
      let note = txn.payee ?? txn.categoryId.flatMap { id in categories.first { $0.id == id }?.name }
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(600))
        router.request = SplitRequest(note: note, amounts: owed)
      }
    }
  }
}

/// 4×3 keypad with a + − × ÷ strip. Tap the result to see the total.
struct Keypad: View {
  @Binding var expr: String
  private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"]

  var body: some View {
    VStack(spacing: 8) {
      HStack(spacing: 8) {
        ForEach(["+", "−", "×", "÷"], id: \.self) { op in
          key(op, height: 36, tint: true) { append(op) }
        }
      }
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
        ForEach(keys, id: \.self) { k in
          key(k, height: 52) {
            if k == "⌫" { backspace() } else { append(k) }
          }
          .accessibilityLabel(k == "⌫" ? "Delete" : k == "." ? "Point" : k)
        }
      }
    }
    .sensoryFeedback(.selection, trigger: expr)
  }

  private func key(_ label: String, height: CGFloat, tint: Bool = false, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Group {
        if label == "⌫" { Image(systemName: "delete.left") } else { Text(label) }
      }
      .font(.system(size: tint ? 20 : 26, weight: tint ? .semibold : .regular, design: .rounded))
      .frame(maxWidth: .infinity, minHeight: height)
      .foregroundStyle(tint ? Color.accentColor : .primary)
      .background(tint ? Color.accentColor.opacity(0.12) : Color(.secondarySystemGroupedBackground),
                  in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(.plain)
    .buttonRepeatBehavior(label == "⌫" ? .enabled : .disabled)
  }

  private func append(_ k: String) {
    let ops = "+−×÷"
    if ops.contains(k) {
      if let last = expr.last, ops.contains(last) { expr.removeLast() }
      if expr == "0" { return }
      expr += k
      return
    }
    // Current number (after the last operator).
    let current = expr.split(whereSeparator: { ops.contains($0) }).last.map(String.init) ?? ""
    let endsWithOp = expr.last.map { ops.contains($0) } ?? false
    let number = endsWithOp ? "" : current
    if k == "." {
      if number.contains(".") { return }
      expr += number.isEmpty ? "0." : "."
      return
    }
    if let dot = number.firstIndex(of: "."), number.distance(from: dot, to: number.endIndex) > 2 { return }
    if number.count >= 9 { return }
    if expr == "0" { expr = k } else { expr += k }
  }

  private func backspace() {
    guard expr != "0" else { return }
    expr.removeLast()
    if expr.isEmpty { expr = "0" }
  }
}

struct CategoryPicker: View {
  let kind: CategoryKind
  @Binding var selection: String?
  @Environment(\.dismiss) private var dismiss
  @Query(filter: #Predicate<Category> { $0.archivedAt == nil }, sort: \Category.sortOrder) private var categories: [Category]
  @State private var query = ""

  var body: some View {
    NavigationStack {
      List {
        Button {
          selection = nil; dismiss()
        } label: { Label("Uncategorised", systemImage: "questionmark.circle") }
        ForEach(categories.filter { $0.kind == kind && $0.parentId == nil && matches($0) }) { parent in
          Section {
            row(parent)
            ForEach(categories.filter { $0.parentId == parent.id }) { row($0, indent: true) }
          }
        }
      }
      .searchable(text: $query)
      .navigationTitle("Category")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }
    .presentationDetents([.large])
  }

  private func matches(_ c: Category) -> Bool {
    query.isEmpty || c.name.localizedCaseInsensitiveContains(query)
      || categories.contains { $0.parentId == c.id && $0.name.localizedCaseInsensitiveContains(query) }
  }

  private func row(_ c: Category, indent: Bool = false) -> some View {
    Button {
      selection = c.id; dismiss()
    } label: {
      HStack {
        CategoryBadge(icon: c.icon, color: c.color, size: indent ? 26 : 30)
        Text(c.name).foregroundStyle(.primary)
        Spacer()
        if selection == c.id { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
      }
      .padding(.leading, indent ? 24 : 0)
    }
  }
}

