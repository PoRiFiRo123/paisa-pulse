import LocalAuthentication
import SwiftData
import SwiftUI
import UserNotifications
import WidgetKit

enum WidgetRefresh {
  static func now() { WidgetCenter.shared.reloadAllTimelines() }
}

/// Local notifications: card bills, budget alerts at 80% and 100%, a Sunday summary.
enum Notifier {
  static func requestPermission() async -> Bool {
    (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
  }

  /// Reschedules bill reminders and the weekly summary.
  @MainActor static func refresh(_ context: ModelContext) {
    let center = UNUserNotificationCenter.current()
    let d = AppGroup.defaults
    // Everything scheduled ahead comes from here (bills, weekly, loans), so start clean.
    center.removeAllPendingNotificationRequests()
    // Loans: on the morning they're due.
    let loans = (try? context.fetch(FetchDescriptor<Loan>())) ?? []
    let loanPayments = (try? context.fetch(FetchDescriptor<LoanPayment>())) ?? []
    for l in loans where l.closedAt == nil && l.remind {
      guard let due = l.dueAt, let at = Calendar.current.date(bySettingHour: 9, minute: 30, second: 0, of: due), at > .now else { continue }
      let left = LoanMath.outstanding(l, loanPayments)
      guard left > 0 else { continue }
      let content = UNMutableNotificationContent()
      content.title = l.lent ? "\(l.person) is due to pay you back" : "Loan from \(l.person) is due"
      content.body = "\(Money.format(left)) \(l.lent ? "to get back" : "to pay back") today."
      content.sound = .default
      let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: at)
      center.add(UNNotificationRequest(identifier: "loan-\(l.id)", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }
    if d.bool(forKey: PrefKey.notifyBills) {
      let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
      let txns = (try? context.fetch(FetchDescriptor<Txn>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
      let balances = Ledger.balances(accounts: accounts, txns: txns)
      for a in accounts where a.type == .card && a.archivedAt == nil {
        guard let dueDay = a.dueDay else { continue }
        let owed = max(0, -(balances[a.id] ?? 0))
        let due = Cards.nextDue(dueDay: dueDay)
        guard owed > 0, var remind = Calendar.current.date(byAdding: .day, value: -3, to: due) else { continue }
        remind = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: remind) ?? remind
        guard remind > .now else { continue }
        let content = UNMutableNotificationContent()
        content.title = "\(a.name) bill due \(due.formatted(.dateTime.weekday(.wide)))"
        content.body = "\(Money.format(owed)) to pay by \(due.formatted(.dateTime.day().month())). Pay on time to avoid interest."
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: remind)
        center.add(UNNotificationRequest(identifier: "bill-\(a.id)", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
      }
    }
    if d.bool(forKey: PrefKey.notifyWeekly) {
      let content = UNMutableNotificationContent()
      content.title = "Your week in money"
      content.body = "See what you spent this week and how your budgets look."
      var comps = DateComponents(); comps.weekday = 1; comps.hour = 19
      center.add(UNNotificationRequest(identifier: "weekly", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)))
    }
  }

  /// Right after a save: tell once per period when a budget passes 80% or 100%.
  @MainActor static func checkBudgets(_ context: ModelContext) {
    let d = AppGroup.defaults
    guard d.bool(forKey: PrefKey.notifyBudgets) else { return }
    let budgets = (try? context.fetch(FetchDescriptor<Budget>())) ?? []
    guard !budgets.isEmpty else { return }
    let txns = (try? context.fetch(FetchDescriptor<Txn>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
    let cats = Dictionary(((try? context.fetch(FetchDescriptor<Category>())) ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    let month = Periods.month(containing: .now, startDay: max(1, d.integer(forKey: PrefKey.monthStartDay)))
    let week = Periods.week(containing: .now, firstWeekday: d.object(forKey: PrefKey.weekStartDay) as? Int ?? 2)
    for p in Budgets.progress(budgets, txns: txns, categories: cats, month: month, week: week) {
      let level = p.ratio >= 1 ? 100 : p.ratio >= 0.8 ? 80 : 0
      guard level > 0 else { continue }
      let start = p.budget.period == "weekly" ? week.start : month.start
      let key = "budgetNotified-\(p.budget.id)-\(Int(start.timeIntervalSince1970))-\(level)"
      guard !d.bool(forKey: key) else { continue }
      d.set(true, forKey: key)
      let name = p.budget.categoryId.flatMap { cats[$0]?.name } ?? "Your"
      let content = UNMutableNotificationContent()
      content.title = level == 100 ? "\(name) budget used up" : "\(name) budget at 80%"
      content.body = level == 100 ? "You've spent \(Money.format(p.spent)) of \(Money.format(p.budget.amount)) this \(p.budget.period == "weekly" ? "week" : "month")."
        : "\(Money.format(p.left)) left this \(p.budget.period == "weekly" ? "week" : "month")."
      content.sound = .default
      UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
    }
  }
}

/// Software Update: CI publishes each build as GitHub Release "build-<n>" (see .github/workflows/build.yml).
@Observable final class UpdateChecker {
  struct Release: Decodable {
    struct Asset: Decodable { let name: String; let browser_download_url: String }
    let tag_name: String; let html_url: String; let assets: [Asset]
  }
  static let shared = UpdateChecker()
  var available: (build: Int, ipa: URL?, page: URL)?
  static let repo = Bundle.main.object(forInfoDictionaryKey: "PaisaReleaseRepo") as? String ?? "PoRiFiRo123/paisa-pulse"
  static var currentBuild: Int { Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0 }

  @MainActor func check() async -> Bool {
    guard Self.currentBuild > 1, let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest") else { return false }
    guard let (data, _) = try? await URLSession.shared.data(from: url),
          let r = try? JSONDecoder().decode(Release.self, from: data),
          r.tag_name.hasPrefix("build-"), let n = Int(r.tag_name.dropFirst(6)), n > Self.currentBuild,
          let page = URL(string: r.html_url) else { available = nil; return false }
    available = (n, r.assets.first { $0.name.hasSuffix(".ipa") }.flatMap { URL(string: $0.browser_download_url) }, page)
    return true
  }

  /// SideStore re-signs and installs it over this app; falls back to the release page.
  func install(_ openURL: OpenURLAction) {
    guard let a = available else { return }
    if let ipa = a.ipa, let s = URL(string: "sidestore://install?url=\(ipa.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")") {
      openURL(s) { accepted in if !accepted { openURL(a.page) } }
    } else {
      openURL(a.page)
    }
  }
}

struct LockView: View {
  let unlocked: () -> Void
  @State private var failed = false

  var body: some View {
    ZStack {
      Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
      VStack(spacing: 16) {
        Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(.secondary)
        Text("Paisa Pulse is locked").font(.headline)
        Button("Unlock") { authenticate() }.buttonStyle(.borderedProminent)
        if failed { Text("Try again").font(.footnote).foregroundStyle(.secondary) }
      }
    }
    .onAppear(perform: authenticate)
  }

  private func authenticate() {
    let ctx = LAContext()
    var err: NSError?
    guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { unlocked(); return }
    ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your finances") { ok, _ in
      DispatchQueue.main.async { if ok { unlocked() } else { failed = true } }
    }
  }
}

struct OnboardingView: View {
  @Environment(\.modelContext) private var context
  @AppStorage(PrefKey.onboarded, store: AppGroup.defaults) private var onboarded = false
  @AppStorage(PrefKey.monthStartDay, store: AppGroup.defaults) private var monthStartDay = 1
  @State private var name = "Bank account"
  @State private var balance = ""
  @State private var restoring = false
  @State private var lockedBackup: Data?
  @State private var unlockText = ""
  @State private var pending: BackupFile?
  @State private var error: String?

  var body: some View {
    NavigationStack {
      Form {
        Section {
          VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "indianrupeesign.circle.fill").font(.system(size: 56)).foregroundStyle(Color.accentColor)
            Text("Paisa Pulse").font(.largeTitle.bold())
            Text("Track every rupee in two taps. No account, no ads, nothing leaves your phone.").foregroundStyle(.secondary)
          }
          .padding(.vertical, 8)
        }
        .listRowBackground(Color.clear)
        Section("Your main account") {
          TextField("Name, e.g. Axis Salary", text: $name)
          TextField("Balance today", text: $balance).keyboardType(.decimalPad)
        }
        Section {
          Picker("Month starts on", selection: $monthStartDay) { ForEach(1...28, id: \.self) { Text(ordinal($0)).tag($0) } }
        } footer: { Text("Pick your salary day if you think of months from payday to payday.") }
        Section {
          Button("Get Started") {
            context.insert(Account(name: name.isEmpty ? "Bank account" : name, type: .bank, openingBalance: Money.parse(balance) ?? 0,
                                   color: "#5E5CE6", icon: AccountType.bank.defaultIcon))
            context.insert(Account(name: "Cash", type: .cash, color: "#34C759", icon: AccountType.cash.defaultIcon, sortOrder: 1))
            try? context.save()
            onboarded = true
          }
          .frame(maxWidth: .infinity).fontWeight(.semibold)
          Button("Restore from a Backup") { restoring = true }.frame(maxWidth: .infinity)
        }
      }
      .fileImporter(isPresented: $restoring, allowedContentTypes: [.json]) { result in
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
          let data = try Data(contentsOf: url)
          if BackupCrypto.isEncrypted(data) { lockedBackup = data; return }
          try BackupCodec.restore(try BackupCodec.decode(data), into: context)
          onboarded = true
        } catch { self.error = error.localizedDescription }
      }
      .alert("This backup has a password", isPresented: Binding(get: { lockedBackup != nil }, set: { if !$0 { lockedBackup = nil } })) {
        SecureField("Password", text: $unlockText)
        Button("Restore") {
          guard let data = lockedBackup else { return }
          do {
            try BackupCodec.restore(try BackupCodec.decode(try BackupCrypto.decrypt(data, password: unlockText)), into: context)
            BackupPassword.value = unlockText
            onboarded = true
          } catch { self.error = "That password didn't open the backup." }
          unlockText = ""
        }
        Button("Cancel", role: .cancel) { unlockText = "" }
      }
      .alert("Couldn't restore", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
    }
  }
}

func ordinal(_ n: Int) -> String {
  let f = NumberFormatter(); f.numberStyle = .ordinal
  return f.string(from: NSNumber(value: n)) ?? "\(n)"
}
