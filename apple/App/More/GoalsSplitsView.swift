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

