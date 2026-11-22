import SwiftData
import SwiftUI

struct SettingsView: View {
  @Environment(\.modelContext) private var context
  @Environment(\.openURL) private var openURL
  @AppStorage(PrefKey.theme, store: AppGroup.defaults) private var theme = "system"
  @AppStorage(PrefKey.accent, store: AppGroup.defaults) private var accent = "indigo"
  @AppStorage(PrefKey.monthStartDay, store: AppGroup.defaults) private var monthStartDay = 1
  @AppStorage(PrefKey.weekStartDay, store: AppGroup.defaults) private var weekStartDay = 2
  @AppStorage(PrefKey.hideAmounts, store: AppGroup.defaults) private var hideAmounts = false
  @AppStorage(PrefKey.appLock, store: AppGroup.defaults) private var appLock = false
  @AppStorage(PrefKey.notifyBudgets, store: AppGroup.defaults) private var notifyBudgets = false
  @AppStorage(PrefKey.notifyBills, store: AppGroup.defaults) private var notifyBills = false
  @AppStorage(PrefKey.notifyWeekly, store: AppGroup.defaults) private var notifyWeekly = false
  @State private var updates = UpdateChecker.shared
  @State private var checking = false
  @State private var upToDate = false
  @State private var csvURL: URL?

  var body: some View {
    Form {
      if let a = updates.available {
        Section {
          Button { updates.install(openURL) } label: {
            row("Software Update", "arrow.down.circle.fill", "#34C759", value: "Build \(a.build)")
          }
        } footer: { Text("Opens the new build in SideStore, which installs it over this one. Your data stays.") }
      }

      Section("Appearance") {
        Picker(selection: $theme) {
          Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
        } label: { row("Theme", "circle.lefthalf.filled", "#5856D6") }
        Picker(selection: $accent) {
          ForEach(Palette.accents, id: \.key) { a in
            Label { Text(a.name) } icon: { Image(systemName: "circle.fill").foregroundStyle(Palette.accent(a.key)) }.tag(a.key)
          }
        } label: { row("Accent colour", "paintpalette.fill", "#FF2D55") }
      }

      Section("Money") {
        NavigationLink { CategoriesView() } label: { row("Categories", "square.grid.2x2.fill", "#FF9500") }
        NavigationLink { BudgetsView() } label: { row("Budgets", "gauge.with.dots.needle.33percent", "#5E5CE6") }
        NavigationLink { RecurringView() } label: { row("Recurring", "repeat", "#30B0C7") }
        NavigationLink { GoalsView() } label: { row("Goals", "target", "#1E9E5A") }
        NavigationLink { SplitsView() } label: { row("Splits", "person.2.fill", "#007AFF") }
        Picker(selection: $monthStartDay) { ForEach(1...28, id: \.self) { Text(ordinal($0)).tag($0) } } label: {
          row("Month starts on", "calendar", "#FF3B30")
        }
        Picker(selection: $weekStartDay) { Text("Sunday").tag(1); Text("Monday").tag(2) } label: {
          row("Week starts on", "calendar.day.timeline.left", "#FF9500")
        }
      }

      Section("See") {
        NavigationLink { InsightsView() } label: { row("Insights", "chart.bar.xaxis", "#AF52DE") }
        NavigationLink { CalendarView() } label: { row("Calendar", "calendar", "#FF2D55") }
        NavigationLink { NetWorthView() } label: { row("Net Worth", "chart.line.uptrend.xyaxis", "#34C759") }
      }

      Section {
        Toggle(isOn: $notifyBudgets) { row("Budget alerts", "bell.badge.fill", "#FF9500") }
        Toggle(isOn: $notifyBills) { row("Card bill reminders", "creditcard.fill", "#007AFF") }
        Toggle(isOn: $notifyWeekly) { row("Sunday summary", "envelope.fill", "#5E5CE6") }
      } header: { Text("Notifications") } footer: {
        Text("Budget alerts at 80% and 100%. Bill reminders 3 days before a card's due day.")
      }
      .onChange(of: [notifyBudgets, notifyBills, notifyWeekly]) { _, values in
        Task {
          if values.contains(true) { _ = await Notifier.requestPermission() }
          Notifier.refresh(context)
        }
      }

      Section("Privacy") {
        Toggle(isOn: $appLock) { row("Face ID Lock", "faceid", "#34C759") }
        Toggle(isOn: $hideAmounts) { row("Hide amounts", "eye.slash.fill", "#8E8E93") }
      }

      Section {
        NavigationLink { BackupView() } label: { row("Backup & Restore", "externaldrive.fill", "#5E5CE6") }
        Button {
          if let text = try? BackupCodec.csv(context) {
            let url = URL.temporaryDirectory.appending(path: "paisa-pulse-transactions.csv")
            try? text.write(to: url, atomically: true, encoding: .utf8)
            csvURL = url
          }
        } label: { row("Export CSV", "tablecells.fill", "#1E9E5A") }
        if let csvURL {
          ShareLink(item: csvURL) { Label("Share CSV", systemImage: "square.and.arrow.up") }
        }
      } header: { Text("Data") } footer: {
        Text("Coming to iPhone next: statement import, voice and screenshot capture (they're in the Android app today).")
      }

      Section {
        VStack(spacing: 4) {
          Text("Paisa Pulse \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (build \(UpdateChecker.currentBuild))")
            .font(.footnote).foregroundStyle(.secondary)
          if UpdateChecker.currentBuild > 1 {
            Button(checking ? "Checking…" : upToDate ? "You're up to date" : "Check for Updates") {
              Task { checking = true; upToDate = !(await updates.check()); checking = false }
            }
            .font(.footnote).disabled(checking)
          }
          Text("No account. No servers. Your data stays on this phone.").font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
      }
      .listRowBackground(Color.clear)
    }
    .navigationTitle("Settings")
    .task { _ = await updates.check() }
  }

  private func row(_ title: String, _ icon: String, _ color: String, value: String? = nil) -> some View {
    HStack(spacing: 12) {
      CategoryBadge(icon: icon, color: color, size: 29)
      Text(title).foregroundStyle(.primary)
      if let value { Spacer(); Text(value).foregroundStyle(.secondary) }
    }
  }
}
