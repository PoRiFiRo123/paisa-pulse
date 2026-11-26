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
  @AppStorage(PrefKey.merchantLogos, store: AppGroup.defaults) private var merchantLogos = false
  @Environment(Router.self) private var router
  @State private var updates = UpdateChecker.shared
  @State private var checking = false
  @State private var upToDate = false
  @State private var csvURL: URL?

  var body: some View {
    Form {
      Section { NavigationLink { AccountView() } label: { AccountRowLabel() } }
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
        NavigationLink { AppearanceColorsView() } label: {
          HStack {
            row("Accent colour", "paintpalette.fill", "#FF2D55")
            Spacer()
            Circle().fill(Color.accentColor).frame(width: 18, height: 18)
          }
        }
        NavigationLink { AppIconPickerView() } label: {
          HStack {
            row("App icon", "app.badge.fill", "#007AFF")
            Spacer()
            Image(AppIcons.preview(AppIcons.current)).resizable().frame(width: 28, height: 28)
              .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
          }
        }
      }

      Section("Money") {
        NavigationLink { CategoriesView() } label: { row("Categories", "square.grid.2x2.fill", "#FF9500") }
        NavigationLink { BudgetsView() } label: { row("Budgets", "gauge.with.dots.needle.33percent", "#5E5CE6") }
        NavigationLink { BillsView() } label: { row("Bills", "calendar.badge.clock", "#FF3B30") }
        NavigationLink { RecurringView() } label: { row("Recurring", "repeat", "#30B0C7") }
        NavigationLink { SubscriptionsView() } label: { row("Subscriptions", "creditcard.and.123", "#32ADE6") }
        NavigationLink { TemplatesView() } label: { row("Templates", "bolt.fill", "#FFB800") }
        NavigationLink { GoalsView() } label: { row("Goals", "target", "#1E9E5A") }
        NavigationLink { SplitsView() } label: { row("Splits", "person.2.fill", "#007AFF") }
        NavigationLink { LoansView() } label: { row("Loans", "banknote.fill", "#E5484D") }
        Picker(selection: $monthStartDay) { ForEach(1...28, id: \.self) { Text(ordinal($0)).tag($0) } } label: {
          row("Month starts on", "calendar", "#FF3B30")
        }
        Picker(selection: $weekStartDay) { Text("Sunday").tag(1); Text("Monday").tag(2) } label: {
          row("Week starts on", "calendar.day.timeline.left", "#FF9500")
        }
      }

      Section {
        NavigationLink { HomeLayoutView() } label: { row("Home Screen", "square.grid.2x2.fill", "#5E5CE6") }
      }

      Section {
        NavigationLink { AutoCaptureView() } label: { row("Auto-capture", "message.badge.filled.fill", "#34C759") }
      } footer: {
        Text("Turn bank SMS into transactions with a Shortcuts automation.")
      }

      Section("See") {
        NavigationLink { PlanningView() } label: { row("Planning", "airplane", "#2563EB") }
        NavigationLink { InsightsView() } label: { row("Insights", "chart.bar.xaxis", "#AF52DE") }
        NavigationLink { CalendarView() } label: { row("Calendar", "calendar", "#FF2D55") }
        NavigationLink { NetWorthView() } label: { row("Net Worth", "chart.line.uptrend.xyaxis", "#34C759") }
        NavigationLink { RecapView(offset: -1) } label: { row("Monthly Recap", "sparkles", "#5E5CE6") }
        NavigationLink { TagsView() } label: { row("Tags", "number", "#FF9500") }
        NavigationLink { ConverterView() } label: { row("Currency Converter", "dollarsign.arrow.circlepath", "#30B0C7") }
        NavigationLink { MainCurrencyView() } label: {
          row("Main Currency", "banknote.fill", "#34C759", value: Money.base)
        }
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

      Section {
        Toggle(isOn: $appLock) { row("Face ID Lock", "faceid", "#34C759") }
        Toggle(isOn: $hideAmounts) { row("Hide amounts", "eye.slash.fill", "#8E8E93") }
        Toggle(isOn: $merchantLogos) { row("Merchant logos", "photo.circle.fill", "#FF9500") }
      } header: { Text("Privacy") } footer: {
        Text("Merchant logos load from Google's icon service: only the shop's website (like swiggy.com) is sent. Off, rows show a coloured letter.")
      }

      Section {
        NavigationLink { ImportView() } label: { row("Import Statement", "doc.text.viewfinder", "#007AFF") }
        Button { router.capture = true } label: { row("Add from Screenshots", "photo.on.rectangle", "#AF52DE") }
        NavigationLink { BackupView() } label: { row("Backup & Restore", "externaldrive.fill", "#5E5CE6") }
        NavigationLink { CleanupView() } label: { row("Clean Up Data", "trash.fill", "#8E8E93") }
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
      } header: { Text("Data") }

      Section {
        VStack(spacing: 4) {
          Text("Paisa Pulse \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (build \(UpdateChecker.currentBuild))")
            .font(.footnote).foregroundStyle(.secondary)
          if UpdateChecker.currentBuild > 1 && !Distribution.isAppStore {
            Button(checking ? "Checking…" : upToDate ? "You're up to date" : "Check for Updates") {
              Task { checking = true; upToDate = !(await updates.check()); checking = false }
            }
            .font(.footnote).disabled(checking)
          }
          Text("No account needed. Your data stays on this phone.").font(.footnote).foregroundStyle(.secondary)
          Link("Privacy Policy", destination: URL(string: "https://paisa-pulse-sigma.vercel.app/privacy")!).font(.footnote)
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


/// A filled circle image that keeps its colour inside menus.
enum Swatch {
  static func image(_ hex: String, size: CGFloat = 20) -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
      UIColor(Color(hex: hex)).setFill()
      UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: size - 2, height: size - 2)).fill()
    }.withRenderingMode(.alwaysOriginal)
  }
}

/// Alternate app icons (asset catalog sets AppIcon-<Name>, included via ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS).
enum AppIcons {
  static let all: [(key: String, name: String, swatch: String)] = [
    ("", "Default", "#5E5CE6"), ("AppIcon-Midnight", "Midnight", "#1C1C3A"), ("AppIcon-Saffron", "Saffron", "#FF9933"),
    ("AppIcon-Mint", "Mint", "#34C7A0"), ("AppIcon-Mono", "Mono", "#8E8E93"), ("AppIcon-Ocean", "Ocean", "#1D4ED8"),
    ("AppIcon-Rose", "Rose", "#BE185D"), ("AppIcon-Forest", "Forest", "#166534"), ("AppIcon-Gold", "Gold", "#B45309"),
    ("AppIcon-Sunset", "Sunset", "#DB2777"), ("AppIcon-Graphite", "Graphite", "#111827"),
  ]
  /// The preview picture in the asset catalog for an icon key.
  static func preview(_ key: String) -> String { "IconPreview-" + (all.first { $0.key == key }?.name ?? "Default") }
  static var current: String { UIApplication.shared.alternateIconName ?? "" }
  static func set(_ key: String) {
    guard UIApplication.shared.supportsAlternateIcons else { return }
    UIApplication.shared.setAlternateIconName(key.isEmpty ? nil : key)
  }
}

