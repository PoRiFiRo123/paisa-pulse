import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The same JSON backup format as the Android app (src/features/backup/backup.ts, v4), so you can
/// move your data between phones. iPhone-only data (splits, goals) rides along in extra keys that
/// the Android app ignores.
struct BackupFile: Codable {
  var format = "paisa-pulse-backup"
  var version = 4
  var exportedAt: Int64
  var accounts: [AccountDTO]
  var categories: [CategoryDTO]
  var transactions: [TxnDTO]
  var settings: [SettingDTO]
  var recurringRules: [RuleDTO]?
  var budgets: [BudgetDTO]?
  var savedFilters: [FilterDTO]?
  var importBatches: [BatchDTO]?
  var friends: [FriendDTO]?
  var splitEntries: [SplitDTO]?
  var goals: [GoalDTO]?
  var txnSplitShares: [ShareDTO]?
  var cards: [CardDTO]?
  var splitGroups: [GroupDTO]?
  var loans: [LoanDTO]?
  var loanPayments: [LoanPaymentDTO]?
  var templates: [TemplateDTO]?
  var valuations: [ValuationDTO]?

  struct Empty: Codable {}
  struct AccountDTO: Codable {
    var id, name, type: String; var institution, last4: String?; var openingBalance: Int; var currency: String?
    var creditLimit, statementDay, dueDay: Int?; var color, icon: String; var sortOrder: Int
    var excludeFromTotals: Bool?; var archivedAt: Int64?; var createdAt, updatedAt: Int64
  }
  struct CategoryDTO: Codable {
    var id: String; var parentId: String?; var kind, name, icon, color: String; var sortOrder: Int
    var archivedAt: Int64?; var createdAt, updatedAt: Int64?
  }
  struct TxnDTO: Codable {
    var id, type: String; var amount: Int; var accountId: String; var toAccountId, categoryId, payee, note: String?
    var occurredAt: Int64; var source: String?; var importBatchId, externalId, currency: String?; var originalAmount: Int?
    var recurringId: String?; var deletedAt: Int64?; var createdAt, updatedAt: Int64; var cardId: String?
    var tags: [String]?
  }
  struct TemplateDTO: Codable {
    var id, name, type: String; var amount: Int; var accountId, toAccountId, categoryId, payee: String?; var sortOrder: Int?; var createdAt: Int64
  }
  struct ValuationDTO: Codable { var id, accountId: String; var value: Int; var at: Int64 }
  struct SettingDTO: Codable { var key: String; var value: String }
  struct RuleDTO: Codable {
    var id, type: String; var amount: Int; var accountId: String; var toAccountId, categoryId, payee, note: String?
    var frequency: String; var interval: Int; var startAt, nextAt: Int64; var endAt, pausedAt: Int64?; var createdAt, updatedAt: Int64
  }
  struct BudgetDTO: Codable { var id: String; var categoryId: String?; var period: String?; var amount: Int; var createdAt, updatedAt: Int64 }
  struct FriendDTO: Codable { var id, name: String; var upiId: String?; var createdAt: Int64; var phone: String? }
  struct SplitDTO: Codable { var id, friendId: String; var txnId: String?; var amount: Int; var note: String?; var occurredAt, createdAt: Int64; var groupId: String? }
  struct GroupDTO: Codable { var id, name: String; var memberIds: [String]; var createdAt: Int64 }
  struct LoanDTO: Codable {
    var id, person: String; var friendId: String?; var direction: String; var amount: Int; var startedAt: Int64; var dueAt: Int64?
    var note: String?; var remind: Bool?; var closedAt: Int64?; var createdAt: Int64
  }
  struct LoanPaymentDTO: Codable { var id, loanId: String; var amount: Int; var occurredAt: Int64; var note: String? }
  struct GoalDTO: Codable {
    var id, name, icon, color: String; var target, saved: Int; var deadline, archivedAt: Int64?; var createdAt: Int64
  }
  struct ShareDTO: Codable { var id: String; var share: Int }
  struct FilterDTO: Codable { var id, name, filters: String; var sortOrder: Int?; var createdAt, updatedAt: Int64 }
  struct BatchDTO: Codable {
    var id, accountId, fileName: String; var template: String?; var count: Int; var createdAt: Int64; var undoneAt: Int64?
  }
  struct CardDTO: Codable {
    var id, accountId, kind, network, last4: String; var expiryMonth, expiryYear: Int?; var nameOnCard, label, color: String?
    var archivedAt: Int64?; var createdAt: Int64
  }
}

enum BackupError: LocalizedError {
  case notBackup, newer, badAmount
  var errorDescription: String? {
    switch self {
    case .notBackup: "This file is not a Paisa Pulse backup."
    case .newer: "This backup was made by a newer version of Paisa Pulse."
    case .badAmount: "This backup contains an invalid amount."
    }
  }
}

private func ms(_ d: Date) -> Int64 { Int64((d.timeIntervalSince1970 * 1000).rounded()) }
private func msOpt(_ d: Date?) -> Int64? { d.map { ms($0) } }
private func date(_ v: Int64) -> Date { Date(timeIntervalSince1970: Double(v) / 1000) }
private func dateOpt(_ v: Int64?) -> Date? { v.map { date($0) } }

enum BackupCodec {
  static let prefKeys: [(String, Any.Type)] = [
    (PrefKey.onboarded, Bool.self), (PrefKey.theme, String.self), (PrefKey.accent, String.self),
    (PrefKey.monthStartDay, Int.self), (PrefKey.weekStartDay, Int.self), (PrefKey.hideAmounts, Bool.self),
    (PrefKey.merchantLogos, Bool.self), (PrefKey.myUpiId, String.self), (PrefKey.myName, String.self),
    (PrefKey.autoCleanup, String.self), (PrefKey.autoCleanupMonths, Int.self),
  ]

  @MainActor static func export(_ context: ModelContext, now: Date = .now) throws -> Data {
    let accounts = try context.fetch(FetchDescriptor<Account>())
    let categories = try context.fetch(FetchDescriptor<Category>())
    let txns = try context.fetch(FetchDescriptor<Txn>())
    let rules = try context.fetch(FetchDescriptor<RecurringRule>())
    let budgets = try context.fetch(FetchDescriptor<Budget>())
    let friends = try context.fetch(FetchDescriptor<Friend>())
    let splits = try context.fetch(FetchDescriptor<SplitEntry>())
    let goals = try context.fetch(FetchDescriptor<Goal>())
    let cards = try context.fetch(FetchDescriptor<PaymentCard>())
    let filters = try context.fetch(FetchDescriptor<SavedFilter>())
    let batches = try context.fetch(FetchDescriptor<ImportBatch>())
    let groups = try context.fetch(FetchDescriptor<SplitGroup>())
    let loans = try context.fetch(FetchDescriptor<Loan>())
    let loanPayments = try context.fetch(FetchDescriptor<LoanPayment>())
    let templates = try context.fetch(FetchDescriptor<TxnTemplate>())
    let valuations = try context.fetch(FetchDescriptor<Valuation>())
    let d = AppGroup.defaults
    let settings: [BackupFile.SettingDTO] = prefKeys.compactMap { key, _ in
      guard let v = d.object(forKey: key),
            let data = try? JSONSerialization.data(withJSONObject: v, options: .fragmentsAllowed),
            let s = String(data: data, encoding: .utf8) else { return nil }
      return .init(key: key, value: s)
    }
    let file = BackupFile(
      exportedAt: ms(now),
      accounts: accounts.map {
        .init(id: $0.id, name: $0.name, type: $0.typeRaw, institution: $0.institution, last4: $0.last4,
              openingBalance: $0.openingBalance, currency: "INR", creditLimit: $0.creditLimit, statementDay: $0.statementDay,
              dueDay: $0.dueDay, color: $0.color, icon: $0.icon, sortOrder: $0.sortOrder, excludeFromTotals: $0.excludeFromTotals,
              archivedAt: msOpt($0.archivedAt), createdAt: ms($0.createdAt), updatedAt: ms($0.updatedAt))
      },
      categories: categories.map {
        .init(id: $0.id, parentId: $0.parentId, kind: $0.kindRaw, name: $0.name, icon: $0.icon, color: $0.color,
              sortOrder: $0.sortOrder, archivedAt: msOpt($0.archivedAt), createdAt: ms($0.createdAt), updatedAt: ms($0.updatedAt))
      },
      transactions: txns.map {
        .init(id: $0.id, type: $0.typeRaw, amount: $0.amount, accountId: $0.accountId, toAccountId: $0.toAccountId,
              categoryId: $0.categoryId, payee: $0.payee, note: $0.note, occurredAt: ms($0.occurredAt), source: $0.source,
              importBatchId: $0.importBatchId, externalId: $0.externalId, currency: $0.currency, originalAmount: $0.originalAmount,
              recurringId: $0.recurringId, deletedAt: msOpt($0.deletedAt), createdAt: ms($0.createdAt), updatedAt: ms($0.updatedAt), cardId: $0.cardId,
              tags: $0.tags.isEmpty ? nil : $0.tags)
      },
      settings: settings,
      recurringRules: rules.map {
        .init(id: $0.id, type: $0.typeRaw, amount: $0.amount, accountId: $0.accountId, toAccountId: $0.toAccountId,
              categoryId: $0.categoryId, payee: $0.payee, note: $0.note, frequency: $0.frequencyRaw, interval: $0.interval,
              startAt: ms($0.startAt), nextAt: ms($0.nextAt), endAt: msOpt($0.endAt), pausedAt: msOpt($0.pausedAt),
              createdAt: ms($0.createdAt), updatedAt: ms($0.updatedAt))
      },
      budgets: budgets.map { .init(id: $0.id, categoryId: $0.categoryId, period: $0.period, amount: $0.amount, createdAt: ms($0.createdAt), updatedAt: ms($0.updatedAt)) },
      savedFilters: filters.map { .init(id: $0.id, name: $0.name, filters: $0.filters, sortOrder: $0.sortOrder, createdAt: ms($0.createdAt), updatedAt: ms($0.updatedAt)) },
      importBatches: batches.map { .init(id: $0.id, accountId: $0.accountId, fileName: $0.fileName, template: $0.template, count: $0.count,
                                         createdAt: ms($0.createdAt), undoneAt: msOpt($0.undoneAt)) },
      friends: friends.map { .init(id: $0.id, name: $0.name, upiId: $0.upiId, createdAt: ms($0.createdAt), phone: $0.phone) },
      splitEntries: splits.map { .init(id: $0.id, friendId: $0.friendId, txnId: $0.txnId, amount: $0.amount, note: $0.note, occurredAt: ms($0.occurredAt), createdAt: ms($0.createdAt), groupId: $0.groupId) },
      goals: goals.map { .init(id: $0.id, name: $0.name, icon: $0.icon, color: $0.color, target: $0.target, saved: $0.saved, deadline: msOpt($0.deadline), archivedAt: msOpt($0.archivedAt), createdAt: ms($0.createdAt)) },
      txnSplitShares: txns.compactMap { t in t.splitShare.map { .init(id: t.id, share: $0) } },
      cards: cards.map { .init(id: $0.id, accountId: $0.accountId, kind: $0.kind, network: $0.network, last4: $0.last4, expiryMonth: $0.expiryMonth,
                               expiryYear: $0.expiryYear, nameOnCard: $0.nameOnCard, label: $0.label, color: $0.color,
                               archivedAt: msOpt($0.archivedAt), createdAt: ms($0.createdAt)) },
      splitGroups: groups.map { .init(id: $0.id, name: $0.name, memberIds: $0.memberIds, createdAt: ms($0.createdAt)) },
      loans: loans.map { .init(id: $0.id, person: $0.person, friendId: $0.friendId, direction: $0.direction, amount: $0.amount,
                               startedAt: ms($0.startedAt), dueAt: msOpt($0.dueAt), note: $0.note, remind: $0.remind,
                               closedAt: msOpt($0.closedAt), createdAt: ms($0.createdAt)) },
      loanPayments: loanPayments.map { .init(id: $0.id, loanId: $0.loanId, amount: $0.amount, occurredAt: ms($0.occurredAt), note: $0.note) },
      templates: templates.map { .init(id: $0.id, name: $0.name, type: $0.typeRaw, amount: $0.amount, accountId: $0.accountId, toAccountId: $0.toAccountId,
                                       categoryId: $0.categoryId, payee: $0.payee, sortOrder: $0.sortOrder, createdAt: ms($0.createdAt)) },
      valuations: valuations.map { .init(id: $0.id, accountId: $0.accountId, value: $0.value, at: ms($0.at)) }
    )
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys]
    return try enc.encode(file)
  }

  static func decode(_ data: Data) throws -> BackupFile {
    guard let file = try? JSONDecoder().decode(BackupFile.self, from: data), file.format == "paisa-pulse-backup" else { throw BackupError.notBackup }
    if file.version > 4 { throw BackupError.newer }
    if file.transactions.contains(where: { $0.amount <= 0 }) { throw BackupError.badAmount }
    return file
  }

  /// Replaces everything with the backup's contents.
  @MainActor static func restore(_ file: BackupFile, into context: ModelContext) throws {
    try context.delete(model: Txn.self); try context.delete(model: Account.self); try context.delete(model: Category.self)
    try context.delete(model: RecurringRule.self); try context.delete(model: Budget.self); try context.delete(model: Friend.self)
    try context.delete(model: SplitEntry.self); try context.delete(model: Goal.self); try context.delete(model: PaymentCard.self)
    try context.delete(model: SavedFilter.self); try context.delete(model: ImportBatch.self)
    try context.delete(model: SplitGroup.self); try context.delete(model: Loan.self); try context.delete(model: LoanPayment.self)
    try context.delete(model: TxnTemplate.self); try context.delete(model: Valuation.self)
    for a in file.accounts {
      context.insert(Account(id: a.id, name: a.name, type: AccountType(rawValue: a.type) ?? .bank, institution: a.institution,
                             last4: a.last4, openingBalance: a.openingBalance, creditLimit: a.creditLimit, statementDay: a.statementDay,
                             dueDay: a.dueDay, color: a.color, icon: a.icon, sortOrder: a.sortOrder, excludeFromTotals: a.excludeFromTotals ?? false,
                             archivedAt: dateOpt(a.archivedAt), createdAt: date(a.createdAt), updatedAt: date(a.updatedAt)))
    }
    for c in file.categories {
      context.insert(Category(id: c.id, parentId: c.parentId, kind: CategoryKind(rawValue: c.kind) ?? .expense, name: c.name,
                              icon: c.icon, color: c.color, sortOrder: c.sortOrder, archivedAt: dateOpt(c.archivedAt),
                              createdAt: date(c.createdAt ?? 0), updatedAt: date(c.updatedAt ?? 0)))
    }
    let shares = Dictionary((file.txnSplitShares ?? []).map { ($0.id, $0.share) }, uniquingKeysWith: { a, _ in a })
    for t in file.transactions {
      let txn = Txn(id: t.id, type: TxnType(rawValue: t.type) ?? .expense, amount: t.amount, accountId: t.accountId,
                         toAccountId: t.toAccountId, categoryId: t.categoryId, payee: t.payee, note: t.note,
                         occurredAt: date(t.occurredAt), source: t.source ?? "manual", recurringId: t.recurringId,
                         importBatchId: t.importBatchId, externalId: t.externalId, currency: t.currency,
                         originalAmount: t.originalAmount, splitShare: shares[t.id], cardId: t.cardId, deletedAt: dateOpt(t.deletedAt),
                         createdAt: date(t.createdAt), updatedAt: date(t.updatedAt))
      txn.tags = t.tags ?? []
      context.insert(txn)
    }
    for x in file.templates ?? [] {
      context.insert(TxnTemplate(id: x.id, name: x.name, type: TxnType(rawValue: x.type) ?? .expense, amount: x.amount, accountId: x.accountId,
                                 toAccountId: x.toAccountId, categoryId: x.categoryId, payee: x.payee, sortOrder: x.sortOrder ?? 0, createdAt: date(x.createdAt)))
    }
    for v in file.valuations ?? [] { context.insert(Valuation(id: v.id, accountId: v.accountId, value: v.value, at: date(v.at))) }
    for r in file.recurringRules ?? [] {
      context.insert(RecurringRule(id: r.id, type: TxnType(rawValue: r.type) ?? .expense, amount: r.amount, accountId: r.accountId,
                                   toAccountId: r.toAccountId, categoryId: r.categoryId, payee: r.payee, note: r.note,
                                   frequency: Frequency(rawValue: r.frequency) ?? .monthly, interval: r.interval,
                                   startAt: date(r.startAt), nextAt: date(r.nextAt), endAt: dateOpt(r.endAt), pausedAt: dateOpt(r.pausedAt),
                                   createdAt: date(r.createdAt), updatedAt: date(r.updatedAt)))
    }
    for b in file.budgets ?? [] {
      context.insert(Budget(id: b.id, categoryId: b.categoryId, period: b.period ?? "monthly", amount: b.amount, createdAt: date(b.createdAt), updatedAt: date(b.updatedAt)))
    }
    for f in file.friends ?? [] { context.insert(Friend(id: f.id, name: f.name, upiId: f.upiId, phone: f.phone, createdAt: date(f.createdAt))) }
    for s in file.splitEntries ?? [] {
      context.insert(SplitEntry(id: s.id, friendId: s.friendId, txnId: s.txnId, amount: s.amount, note: s.note, groupId: s.groupId,
                                occurredAt: date(s.occurredAt), createdAt: date(s.createdAt)))
    }
    for g in file.splitGroups ?? [] { context.insert(SplitGroup(id: g.id, name: g.name, memberIds: g.memberIds, createdAt: date(g.createdAt))) }
    for l in file.loans ?? [] {
      context.insert(Loan(id: l.id, person: l.person, friendId: l.friendId, direction: l.direction, amount: l.amount, startedAt: date(l.startedAt),
                          dueAt: dateOpt(l.dueAt), note: l.note, remind: l.remind ?? true, closedAt: dateOpt(l.closedAt), createdAt: date(l.createdAt)))
    }
    for p in file.loanPayments ?? [] {
      context.insert(LoanPayment(id: p.id, loanId: p.loanId, amount: p.amount, occurredAt: date(p.occurredAt), note: p.note))
    }
    for g in file.goals ?? [] {
      context.insert(Goal(id: g.id, name: g.name, icon: g.icon, color: g.color, target: g.target, saved: g.saved, deadline: dateOpt(g.deadline), archivedAt: dateOpt(g.archivedAt), createdAt: date(g.createdAt)))
    }
    for c in file.cards ?? [] {
      context.insert(PaymentCard(id: c.id, accountId: c.accountId, kind: c.kind, network: c.network, last4: c.last4, expiryMonth: c.expiryMonth,
                                 expiryYear: c.expiryYear, nameOnCard: c.nameOnCard, label: c.label, color: c.color,
                                 archivedAt: dateOpt(c.archivedAt), createdAt: date(c.createdAt)))
    }
    for f in file.savedFilters ?? [] {
      context.insert(SavedFilter(id: f.id, name: f.name, filters: f.filters, sortOrder: f.sortOrder ?? 0, createdAt: date(f.createdAt), updatedAt: date(f.updatedAt)))
    }
    for b in file.importBatches ?? [] {
      context.insert(ImportBatch(id: b.id, accountId: b.accountId, fileName: b.fileName, template: b.template, count: b.count,
                                 createdAt: date(b.createdAt), undoneAt: dateOpt(b.undoneAt)))
    }
    let d = AppGroup.defaults
    for s in file.settings {
      guard let data = s.value.data(using: .utf8), let v = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) else { continue }
      if prefKeys.contains(where: { $0.0 == s.key }) { d.set(v, forKey: s.key) }
    }
    d.set(true, forKey: PrefKey.onboarded)
    try context.save()
  }

  /// CSV of every transaction, newest first (amounts in rupees, no minus signs: see the Type column).
  @MainActor static func csv(_ context: ModelContext) throws -> String {
    let accounts = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Account>()).map { ($0.id, $0.name) })
    let cats = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Category>()).map { ($0.id, $0.name) })
    let txns = try context.fetch(FetchDescriptor<Txn>(sortBy: [SortDescriptor(\.occurredAt, order: .reverse)])).filter { $0.deletedAt == nil }
    func q(_ s: String?) -> String { "\"" + (s ?? "").replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
    let f = ISO8601DateFormatter()
    var lines = ["Date,Type,Amount,Your share,Account,To account,Category,Payee,Note"]
    for t in txns {
      lines.append([f.string(from: t.occurredAt), t.typeRaw, String(format: "%.2f", Double(t.amount) / 100),
                    t.splitShare.map { String(format: "%.2f", Double($0) / 100) } ?? "",
                    q(accounts[t.accountId]), q(t.toAccountId.flatMap { accounts[$0] }), q(t.categoryId.flatMap { cats[$0] }),
                    q(t.payee), q(t.note)].joined(separator: ","))
    }
    return lines.joined(separator: "\n")
  }
}

/// Daily automatic backups in Files › On My iPhone › Paisa Pulse › backups (keeps 14).
enum AutoBackup {
  static var folder: URL { URL.documentsDirectory.appending(path: "backups", directoryHint: .isDirectory) }

  @MainActor static func runIfDue(_ context: ModelContext) {
    let d = AppGroup.defaults
    guard d.object(forKey: PrefKey.autoBackup) as? Bool ?? true else { return }
    let last = d.double(forKey: PrefKey.lastBackupAt)
    guard Date.now.timeIntervalSince1970 - last > 20 * 3600 else { return }
    let count = (try? context.fetchCount(FetchDescriptor<Txn>())) ?? 0
    guard count > 0 else { return }
    try? write(context)
  }

  @MainActor @discardableResult static func write(_ context: ModelContext) throws -> URL {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let name = "paisa-pulse-\(Date.now.formatted(.iso8601.year().month().day())).json"
    let url = folder.appending(path: name)
    let plain = try BackupCodec.export(context)
    try (BackupPassword.value.map { try BackupCrypto.encrypt(plain, password: $0) } ?? plain).write(to: url, options: .atomic)
    AppGroup.defaults.set(Date.now.timeIntervalSince1970, forKey: PrefKey.lastBackupAt)
    let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    for old in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).dropFirst(14) {
      try? FileManager.default.removeItem(at: old)
    }
    return url
  }

  static func list() -> [URL] {
    ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
      .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
  }
}

struct BackupDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.json] }
  var data: Data
  init(data: Data) { self.data = data }
  init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct BackupView: View {
  @Environment(\.modelContext) private var context
  @Environment(Router.self) private var router
  @AppStorage(PrefKey.autoBackup, store: AppGroup.defaults) private var auto = true
  @AppStorage(PrefKey.lastBackupAt, store: AppGroup.defaults) private var lastAt = 0.0
  @State private var exporting: BackupDocument?
  @State private var importing = false
  @State private var pending: BackupFile?
  @State private var error: String?
  @State private var files: [URL] = []
  @State private var locked: Data?
  @State private var unlock = ""
  @State private var settingPassword = false
  @State private var newPassword = ""
  @State private var hasPassword = BackupPassword.value != nil

  var body: some View {
    List {
      Section {
        Toggle("Protect with a password", isOn: Binding(get: { hasPassword }, set: { on in
          if on { settingPassword = true } else { BackupPassword.value = nil; hasPassword = false }
        }))
      } footer: {
        Text("Backups (daily ones and saved copies) are encrypted with AES-256. Without the password nobody can open them, not even you, so keep it somewhere safe. Android uses the same format.")
      }
      Section {
        Toggle("Daily backup", isOn: $auto)
        Button("Back Up Now") {
          do { try AutoBackup.write(context); files = AutoBackup.list(); router.show("Backed up") } catch { self.error = error.localizedDescription }
        }
      } footer: {
        Text("Backups are saved in the Files app › On My iPhone › Paisa Pulse › backups. The last 14 are kept." +
             (lastAt > 0 ? " Last: \(Date(timeIntervalSince1970: lastAt).formatted(.relative(presentation: .named)))." : ""))
      }
      Section {
        Button {
          if let data = try? BackupCodec.export(context) {
            exporting = BackupDocument(data: (BackupPassword.value.flatMap { try? BackupCrypto.encrypt(data, password: $0) }) ?? data)
          }
        } label: { Label("Save to Google Drive or Files…", systemImage: "square.and.arrow.up.on.square") }
        Button { importing = true } label: { Label("Restore from a File…", systemImage: "square.and.arrow.down") }
      } header: { Text("Google Drive") } footer: {
        Text("With the Google Drive app installed, pick Drive in the list to keep a copy off your phone. The same file restores on Android.")
      }
      if !files.isEmpty {
        Section("On this iPhone") {
          ForEach(files, id: \.self) { url in
            Button(url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "paisa-pulse-", with: "")) {
              load(url)
            }
          }
        }
      }
    }
    .navigationTitle("Backup & Restore")
    .onAppear { files = AutoBackup.list() }
    .fileExporter(isPresented: Binding(get: { exporting != nil }, set: { if !$0 { exporting = nil } }), document: exporting,
                  contentType: .json, defaultFilename: "paisa-pulse-\(Date.now.formatted(.iso8601.year().month().day())).json") { result in
      if case .success = result { router.show("Backup saved") }
    }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
      if case .success(let url) = result { load(url) }
    }
    .confirmationDialog("Replace everything with this backup?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
      Button("Restore", role: .destructive) {
        guard let file = pending else { return }
        do { try BackupCodec.restore(file, into: context); router.show("Restored \(file.transactions.count) transactions"); WidgetRefresh.now() }
        catch { self.error = error.localizedDescription }
      }
    } message: {
      Text("\(pending?.transactions.count ?? 0) transactions and \(pending?.accounts.count ?? 0) accounts from \(pending.map { Date(timeIntervalSince1970: Double($0.exportedAt) / 1000).formatted(date: .abbreviated, time: .shortened) } ?? ""). Your current data on this iPhone is replaced.")
    }
    .alert("Couldn't do that", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
    .alert("Backup password", isPresented: $settingPassword) {
      SecureField("Password", text: $newPassword)
      Button("Save") {
        if newPassword.count >= 4 { BackupPassword.value = newPassword; hasPassword = true; try? AutoBackup.write(context); files = AutoBackup.list() }
        newPassword = ""
      }
      Button("Cancel", role: .cancel) { newPassword = "" }
    } message: { Text("At least 4 characters. It's kept in this iPhone's Keychain for daily backups.") }
    .alert("This backup has a password", isPresented: Binding(get: { locked != nil }, set: { if !$0 { locked = nil } })) {
      SecureField("Password", text: $unlock)
      Button("Open") {
        guard let data = locked else { return }
        do { pending = try BackupCodec.decode(try BackupCrypto.decrypt(data, password: unlock)) }
        catch { self.error = "That password didn't open the backup." }
        unlock = ""
      }
      Button("Cancel", role: .cancel) { unlock = "" }
    }
  }

  private func load(_ url: URL) {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    do {
      let data = try Data(contentsOf: url)
      if BackupCrypto.isEncrypted(data) {
        if let pw = BackupPassword.value, let plain = try? BackupCrypto.decrypt(data, password: pw) { pending = try BackupCodec.decode(plain) }
        else { locked = data }
      } else { pending = try BackupCodec.decode(data) }
    } catch { self.error = error.localizedDescription }
  }
}
