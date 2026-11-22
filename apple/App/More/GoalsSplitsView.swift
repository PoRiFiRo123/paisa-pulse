import SwiftData
import SwiftUI

struct GoalsView: View {
  @Query(sort: \Goal.createdAt) private var goals: [Goal]
  @Environment(\.modelContext) private var context
  @State private var editing: Goal?
  @State private var adding = false

  var body: some View {
    List {
      if goals.isEmpty {
        EmptyHint(title: "No goals yet", icon: "target", message: "A trip, a new phone, an emergency fund. Save towards it bit by bit.")
      }
      ForEach(goals.filter { $0.archivedAt == nil }) { g in
        Button { editing = g } label: { GoalRow(goal: g).foregroundStyle(.primary) }
          .swipeActions {
            Button(role: .destructive) { context.delete(g); try? context.save() } label: { Label("Delete", systemImage: "trash") }
          }
      }
    }
    .navigationTitle("Goals")
    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") } } }
    .sheet(item: $editing) { g in NavigationStack { GoalFormView(goal: g) } }
    .sheet(isPresented: $adding) { NavigationStack { GoalFormView(goal: nil) } }
  }
}

struct GoalRow: View {
  let goal: Goal
  var body: some View {
    let ratio = goal.target > 0 ? Double(goal.saved) / Double(goal.target) : 0
    HStack(spacing: 12) {
      CategoryBadge(icon: goal.icon, color: goal.color)
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text(goal.name).font(.subheadline.weight(.medium))
          Spacer()
          Text("\(Money.format(goal.saved)) of \(Money.format(goal.target))").font(.footnote).foregroundStyle(.secondary)
        }
        ProgressView(value: min(ratio, 1)).tint(Color(hex: goal.color))
        if let d = goal.deadline, goal.saved < goal.target {
          let months = max(1, Calendar.current.dateComponents([.month], from: .now, to: d).month ?? 1)
          Text("Save \(Money.format((goal.target - goal.saved) / months)) a month to make it by \(d.formatted(.dateTime.month(.abbreviated).year()))")
            .font(.caption).foregroundStyle(.secondary)
        } else if goal.saved >= goal.target {
          Text("Done! 🎉").font(.caption).foregroundStyle(Color.income)
        }
      }
    }
    .padding(.vertical, 4)
  }
}

struct GoalFormView: View {
  let goal: Goal?
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @State private var name = ""
  @State private var target = ""
  @State private var saved = ""
  @State private var add = ""
  @State private var hasDeadline = false
  @State private var deadline = Date.now.addingTimeInterval(180 * 86_400)
  @State private var color = "#5E5CE6"
  @State private var icon = "star.fill"

  var body: some View {
    Form {
      Section {
        HStack { CategoryBadge(icon: icon, color: color, size: 40); TextField("Goal, e.g. Germany trip", text: $name) }
        TextField("Target amount", text: $target).keyboardType(.decimalPad)
        if goal == nil { TextField("Already saved (optional)", text: $saved).keyboardType(.decimalPad) }
        Toggle("By a date", isOn: $hasDeadline)
        if hasDeadline { DatePicker("Date", selection: $deadline, in: Date.now..., displayedComponents: .date) }
      }
      if let g = goal {
        Section("Add money") {
          LabeledContent("Saved so far", value: Money.format(g.saved))
          TextField("Amount to add", text: $add).keyboardType(.decimalPad)
          HStack {
            Button("Add") { if let p = Money.parse(add) { g.saved += p; add = ""; try? context.save() } }
              .buttonStyle(.borderedProminent)
            Button("Take out") { if let p = Money.parse(add) { g.saved = max(0, g.saved - p); add = ""; try? context.save() } }
              .buttonStyle(.bordered)
          }
        }
      }
      Section("Look") {
        ColorRow(selection: $color)
        Picker("Icon", selection: $icon) {
          ForEach(["star.fill", "airplane", "iphone", "car.fill", "house.fill", "graduationcap.fill", "heart.fill", "gift.fill", "shield.fill", "laptopcomputer", "camera.fill", "bicycle"], id: \.self) {
            Label($0, systemImage: $0).labelStyle(.iconOnly).tag($0)
          }
        }
      }
    }
    .navigationTitle(goal == nil ? "New Goal" : goal!.name)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          guard let t = Money.parse(target) else { return }
          let g = goal ?? Goal(name: name, target: t, saved: Money.parse(saved) ?? 0)
          g.name = name; g.target = t; g.deadline = hasDeadline ? deadline : nil; g.color = color; g.icon = icon
          if goal == nil { context.insert(g) }
          try? context.save(); dismiss()
        }
        .disabled(name.isEmpty || Money.parse(target) == nil)
      }
    }
    .onAppear {
      if let g = goal {
        name = g.name; target = String(g.target / 100); hasDeadline = g.deadline != nil
        deadline = g.deadline ?? deadline; color = g.color; icon = g.icon
      }
    }
  }
}

/// Splitwise-style: who owes you, who you owe, settle up (with a UPI link when you owe them).
struct SplitsView: View {
  @Query(sort: \Friend.name) private var friends: [Friend]
  @Query(sort: \SplitEntry.occurredAt, order: .reverse) private var entries: [SplitEntry]
  @Environment(\.modelContext) private var context
  @State private var newName = ""
  @State private var addingFriend = false

  var body: some View {
    let balances = Splits.balances(entries)
    let owedToYou = balances.values.filter { $0 > 0 }.reduce(0, +)
    let youOwe = -balances.values.filter { $0 < 0 }.reduce(0, +)
    List {
      Section {
        HStack(spacing: 0) {
          SummaryCell(label: "You're owed", value: owedToYou, color: .income)
          SummaryCell(label: "You owe", value: youOwe, color: .expense)
        }
        .frame(height: 52)
      } footer: {
        Text("Split an expense from Quick Add › Split. Your share is what counts in your spending.")
      }
      Section("People") {
        if friends.isEmpty { Text("Add the people you split with").foregroundStyle(.secondary) }
        ForEach(friends) { f in
          NavigationLink { FriendDetailView(friend: f) } label: {
            HStack {
              Text(String(f.name.prefix(1)).uppercased())
                .font(.headline).foregroundStyle(.white).frame(width: 34, height: 34)
                .background(Color.accentColor.gradient, in: Circle())
              Text(f.name)
              Spacer()
              let b = balances[f.id] ?? 0
              if b == 0 { Text("settled").foregroundStyle(.secondary).font(.subheadline) }
              else {
                VStack(alignment: .trailing, spacing: 0) {
                  Text(Money.format(b)).fontDesign(.rounded).foregroundStyle(b > 0 ? Color.income : Color.expense)
                  Text(b > 0 ? "owes you" : "you owe").font(.caption2).foregroundStyle(.secondary)
                }
              }
            }
          }
        }
      }
    }
    .navigationTitle("Splits")
    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { addingFriend = true } label: { Image(systemName: "person.badge.plus") } } }
    .alert("Add person", isPresented: $addingFriend) {
      TextField("Name", text: $newName)
      Button("Add") {
        let n = newName.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { context.insert(Friend(name: n)); try? context.save() }
        newName = ""
      }
      Button("Cancel", role: .cancel) { newName = "" }
    }
  }
}

struct FriendDetailView: View {
  @Bindable var friend: Friend
  @Query(sort: \SplitEntry.occurredAt, order: .reverse) private var entries: [SplitEntry]
  @Environment(\.modelContext) private var context
  @Environment(\.openURL) private var openURL
  @State private var upi = ""

  var body: some View {
    let mine = entries.filter { $0.friendId == friend.id }
    let balance = mine.reduce(0) { $0 + $1.amount }
    List {
      Section {
        VStack(spacing: 4) {
          Text(balance == 0 ? "All settled" : balance > 0 ? "\(friend.name) owes you" : "You owe \(friend.name)")
            .font(.subheadline).foregroundStyle(.secondary)
          Text(Money.format(balance)).font(.system(size: 40, weight: .bold, design: .rounded))
            .foregroundStyle(balance > 0 ? Color.income : balance < 0 ? Color.expense : .primary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        if balance != 0 {
          Button {
            context.insert(SplitEntry(friendId: friend.id, amount: -balance, note: "Settled up"))
            try? context.save()
          } label: { Label("Mark as Settled", systemImage: "checkmark.circle") }
          if balance < 0, let id = friend.upiId, !id.isEmpty,
             let url = URL(string: "upi://pay?pa=\(id)&pn=\(friend.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&am=\(String(format: "%.2f", Double(-balance) / 100))&cu=INR") {
            Button { openURL(url) } label: { Label("Pay \(Money.format(-balance)) with UPI", systemImage: "indianrupeesign.circle") }
          }
        }
      }
      Section {
        TextField("UPI ID (optional), e.g. name@okaxis", text: $upi)
          .textInputAutocapitalization(.never).keyboardType(.emailAddress)
          .onSubmit { friend.upiId = upi.isEmpty ? nil : upi; try? context.save() }
      } footer: { Text("Lets you pay them from any UPI app when you owe them.") }
      Section("History") {
        ForEach(mine) { e in
          HStack {
            VStack(alignment: .leading) {
              Text(e.note ?? (e.txnId == nil ? "Settle up" : "Split"))
              Text(e.occurredAt.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.format(e.amount)).fontDesign(.rounded).foregroundStyle(e.amount > 0 ? Color.income : Color.expense)
          }
        }
        .onDelete { idx in idx.map { mine[$0] }.forEach { context.delete($0) }; try? context.save() }
      }
    }
    .navigationTitle(friend.name)
    .onAppear { upi = friend.upiId ?? "" }
    .onDisappear { friend.upiId = upi.isEmpty ? nil : upi; try? context.save() }
  }
}
