import SwiftData
import SwiftUI

/// Money you lent or borrowed, with due dates, part repayments and reminders. Same screens on Android (Loans.kt).
struct LoansView: View {
  @Query(sort: \Loan.startedAt, order: .reverse) private var loans: [Loan]
  @Query private var payments: [LoanPayment]
  @AppStorage(PrefKey.hideAmounts, store: AppGroup.defaults) private var hidden = false
  @State private var adding = false

  var body: some View {
    let open = loans.filter { $0.closedAt == nil }
    let closed = loans.filter { $0.closedAt != nil }
    let lent = open.filter(\.lent).reduce(0) { $0 + LoanMath.outstanding($1, payments) }
    let borrowed = open.filter { !$0.lent }.reduce(0) { $0 + LoanMath.outstanding($1, payments) }
    List {
      Section {
        HStack(spacing: 0) {
          SummaryCell(label: "You lent", value: lent, color: .income)
          SummaryCell(label: "You borrowed", value: borrowed, color: .expense)
        }
        .frame(height: 52)
      } footer: { Text("Still to come back to you, and still to pay back. Separate from split balances.") }
      if loans.isEmpty {
        EmptyHint(title: "No loans", icon: "banknote", message: "Lent a friend ₹5,000 or borrowed for a deposit? Keep track of it here with a due date.")
      }
      if !open.isEmpty {
        Section("Open") { ForEach(open) { l in NavigationLink(value: NavRoute.loan(l.id)) { LoanRow(loan: l, payments: payments, hidden: hidden) } } }
      }
      if !closed.isEmpty {
        Section("Settled") { ForEach(closed) { l in NavigationLink(value: NavRoute.loan(l.id)) { LoanRow(loan: l, payments: payments, hidden: hidden) } } }
      }
    }
    .navigationTitle("Loans")
    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add loan") } }
    .sheet(isPresented: $adding) { NavigationStack { LoanFormView(loan: nil) } }
  }
}

struct LoanRow: View {
  let loan: Loan
  let payments: [LoanPayment]
  let hidden: Bool
  var body: some View {
    let left = LoanMath.outstanding(loan, payments)
    let ratio = loan.amount > 0 ? Double(loan.amount - left) / Double(loan.amount) : 0
    let overdue = loan.closedAt == nil && (loan.dueAt.map { $0 < Calendar.current.startOfDay(for: .now) } ?? false)
    HStack(spacing: 12) {
      Avatar(name: loan.person)
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(loan.person).lineLimit(1)
          Spacer()
          Text(Money.format(left, hidden: hidden)).fontDesign(.rounded).fontWeight(.semibold)
            .foregroundStyle(loan.closedAt != nil ? Color.secondary : loan.lent ? Color.income : Color.expense)
        }
        ProgressView(value: ratio).tint(loan.lent ? Color.income : Color.expense)
        Text(subtitle(overdue)).font(.caption).foregroundStyle(overdue ? Color.expense : .secondary)
      }
    }
    .padding(.vertical, 2)
  }
  private func subtitle(_ overdue: Bool) -> String {
    if loan.closedAt != nil { return "\(loan.lent ? "Lent" : "Borrowed") \(Money.format(loan.amount, hidden: hidden)) · settled" }
    let due = loan.dueAt.map { (overdue ? " · overdue since " : " · due ") + $0.formatted(.dateTime.day().month(.abbreviated)) } ?? ""
    return "\(loan.lent ? "Lent" : "Borrowed") \(Money.format(loan.amount, hidden: hidden))\(due)"
  }
}

struct LoanDetailView: View {
  @Bindable var loan: Loan
  @Query(sort: \LoanPayment.occurredAt, order: .reverse) private var allPayments: [LoanPayment]
  @Environment(\.modelContext) private var context
  @Environment(\.dismiss) private var dismiss
  @Environment(Router.self) private var router
  @State private var recording = false
  @State private var amount = ""
  @State private var editing = false
  @State private var confirmDelete = false

  var body: some View {
    let payments = allPayments.filter { $0.loanId == loan.id }
    let left = LoanMath.outstanding(loan, payments)
    List {
      Section {
        VStack(spacing: 4) {
          Avatar(name: loan.person, size: 56)
          Text(loan.closedAt != nil ? "Settled" : loan.lent ? "\(loan.person) still owes you" : "You still owe \(loan.person)")
            .font(.subheadline).foregroundStyle(.secondary).padding(.top, 6)
          Text(Money.format(left)).font(.system(size: 40, weight: .bold, design: .rounded)).rolling(left)
            .foregroundStyle(loan.closedAt != nil ? Color.primary : loan.lent ? Color.income : Color.expense)
          Text("of \(Money.format(loan.amount)) \(loan.lent ? "lent" : "borrowed") on \(loan.startedAt.formatted(date: .abbreviated, time: .omitted))")
            .font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        if loan.closedAt == nil {
          Button { recording = true } label: { Label("Record a Repayment", systemImage: "plus.circle") }
          Button {
            if left > 0 { context.insert(LoanPayment(loanId: loan.id, amount: left, note: "Settled")) }
            loan.closedAt = .now
            try? context.save(); Notifier.refresh(context)
          } label: { Label("Mark as Settled", systemImage: "checkmark.circle") }
        } else {
          Button { loan.closedAt = nil; try? context.save(); Notifier.refresh(context) } label: { Label("Reopen", systemImage: "arrow.uturn.backward") }
        }
      }
      Section {
        if let due = loan.dueAt { LabeledContent("Due", value: due.formatted(date: .long, time: .omitted)) }
        Toggle("Remind me", isOn: $loan.remind).onChange(of: loan.remind) { try? context.save(); Notifier.refresh(context) }
        if let note = loan.note { LabeledContent("Note", value: note) }
      } footer: { if loan.dueAt != nil { Text("A reminder on the morning it's due.") } }
      if !payments.isEmpty {
        Section("Repayments") {
          ForEach(payments) { p in
            HStack {
              VStack(alignment: .leading) {
                Text(p.note ?? "Repayment")
                Text(p.occurredAt.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              Text(Money.format(p.amount)).fontDesign(.rounded)
            }
          }
          .onDelete { idx in idx.map { payments[$0] }.forEach { context.delete($0) }; loan.closedAt = nil; try? context.save() }
        }
      }
    }
    .navigationTitle(loan.person)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button { editing = true } label: { Label("Edit", systemImage: "pencil") }
          Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
        } label: { Image(systemName: "ellipsis") }
      }
    }
    .sheet(isPresented: $editing) { NavigationStack { LoanFormView(loan: loan) } }
    .alert("Record a repayment", isPresented: $recording) {
      TextField("Amount", text: $amount).keyboardType(.decimalPad)
      Button("Add") {
        if let p = Money.parse(amount) {
          context.insert(LoanPayment(loanId: loan.id, amount: p))
          if p >= left { loan.closedAt = .now }
          try? context.save(); Notifier.refresh(context)
          router.show("Recorded \(Money.format(p))")
        }
        amount = ""
      }
      Button("Cancel", role: .cancel) { amount = "" }
    } message: { Text("\(Money.format(left)) left.") }
    .confirmationDialog("Delete this loan and its repayments?", isPresented: $confirmDelete, titleVisibility: .visible) {
      Button("Delete", role: .destructive) {
        payments.forEach { context.delete($0) }
        context.delete(loan)
        try? context.save(); Notifier.refresh(context)
        dismiss()
      }
    }
  }
}

struct LoanFormView: View {
  var loan: Loan?
  @Query(sort: \Friend.name) private var friends: [Friend]
  @Environment(\.modelContext) private var context
  @Environment(\.dismiss) private var dismiss
  @State private var lent = true
  @State private var person = ""
  @State private var amount = ""
  @State private var started = Date.now
  @State private var hasDue = false
  @State private var due = Calendar.current.date(byAdding: .month, value: 1, to: .now)!
  @State private var note = ""
  @State private var remind = true

  var body: some View {
    Form {
      Picker("", selection: $lent) { Text("I lent").tag(true); Text("I borrowed").tag(false) }.pickerStyle(.segmented)
      Section {
        TextField(lent ? "Who did you lend to?" : "Who did you borrow from?", text: $person)
        if !friends.isEmpty && person.isEmpty {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack { ForEach(friends.prefix(8)) { f in Button(f.name) { person = f.name }.buttonStyle(.bordered).buttonBorderShape(.capsule) } }
          }
        }
        TextField("Amount", text: $amount).keyboardType(.decimalPad)
        DatePicker("On", selection: $started, displayedComponents: .date)
      }
      Section {
        Toggle("Due date", isOn: $hasDue)
        if hasDue {
          DatePicker("Due", selection: $due, displayedComponents: .date)
          Toggle("Remind me", isOn: $remind)
        }
      }
      Section { TextField("Note (optional)", text: $note, axis: .vertical) }
    }
    .navigationTitle(loan == nil ? "New Loan" : "Edit Loan")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(person.nilIfEmpty == nil || Money.parse(amount) == nil) }
    }
    .onAppear {
      guard let l = loan else { return }
      lent = l.lent; person = l.person; amount = Money.format(l.amount).replacingOccurrences(of: "₹", with: "").replacingOccurrences(of: ",", with: "")
      started = l.startedAt; hasDue = l.dueAt != nil; due = l.dueAt ?? due; note = l.note ?? ""; remind = l.remind
    }
  }

  private func save() {
    guard let name = person.nilIfEmpty, let paise = Money.parse(amount) else { return }
    let friendId = friends.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.id
    if let l = loan {
      l.direction = lent ? "lent" : "borrowed"; l.person = name; l.friendId = friendId; l.amount = paise; l.startedAt = started
      l.dueAt = hasDue ? due : nil; l.note = note.nilIfEmpty; l.remind = remind
    } else {
      context.insert(Loan(person: name, friendId: friendId, direction: lent ? "lent" : "borrowed", amount: paise, startedAt: started,
                          dueAt: hasDue ? due : nil, note: note.nilIfEmpty, remind: remind))
    }
    try? context.save()
    Notifier.refresh(context)
    dismiss()
  }
}
