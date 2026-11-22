import Foundation
import SwiftData

// Mirrors the React Native app's tables (src/db/schema.ts) so backups move between
// Android and iPhone. Money is integer paise, always positive on transactions.

enum TxnType: String, Codable, CaseIterable, Identifiable {
  case expense, income, transfer
  var id: String { rawValue }
  var label: String { rawValue.capitalized }
}

enum AccountType: String, Codable, CaseIterable, Identifiable {
  case bank, card, cash, wallet, investment
  var id: String { rawValue }
  var label: String {
    switch self {
    case .bank: "Bank account"
    case .card: "Credit card"
    case .cash: "Cash"
    case .wallet: "Wallet"
    case .investment: "Investments"
    }
  }
  var plural: String {
    switch self {
    case .bank: "Bank accounts"
    case .card: "Credit cards"
    case .cash: "Cash"
    case .wallet: "Wallets"
    case .investment: "Investments"
    }
  }
  var defaultIcon: String {
    switch self {
    case .bank: "building.columns.fill"
    case .card: "creditcard.fill"
    case .cash: "banknote.fill"
    case .wallet: "wallet.bifold.fill"
    case .investment: "chart.line.uptrend.xyaxis"
    }
  }
}

enum CategoryKind: String, Codable, CaseIterable, Identifiable {
  case expense, income
  var id: String { rawValue }
}

enum Frequency: String, Codable, CaseIterable, Identifiable {
  case daily, weekly, monthly, yearly
  var id: String { rawValue }
  var unit: Calendar.Component {
    switch self {
    case .daily: .day
    case .weekly: .weekOfYear
    case .monthly: .month
    case .yearly: .year
    }
  }
  var noun: String {
    switch self {
    case .daily: "day"
    case .weekly: "week"
    case .monthly: "month"
    case .yearly: "year"
    }
  }
}

@Model final class Account {
  @Attribute(.unique) var id: String
  var name: String
  var typeRaw: String
  var institution: String?
  var last4: String?
  /// Signed: a credit card you owe on is negative.
  var openingBalance: Int
  var creditLimit: Int?
  var statementDay: Int?
  var dueDay: Int?
  var color: String
  var icon: String
  var sortOrder: Int
  var excludeFromTotals: Bool
  var archivedAt: Date?
  var createdAt: Date
  var updatedAt: Date

  init(id: String = UUID().uuidString.lowercased(), name: String, type: AccountType, institution: String? = nil,
       last4: String? = nil, openingBalance: Int = 0, creditLimit: Int? = nil, statementDay: Int? = nil,
       dueDay: Int? = nil, color: String, icon: String, sortOrder: Int = 0, excludeFromTotals: Bool = false,
       archivedAt: Date? = nil, createdAt: Date = .now, updatedAt: Date = .now) {
    self.id = id; self.name = name; self.typeRaw = type.rawValue; self.institution = institution
    self.last4 = last4; self.openingBalance = openingBalance; self.creditLimit = creditLimit
    self.statementDay = statementDay; self.dueDay = dueDay; self.color = color; self.icon = icon
    self.sortOrder = sortOrder; self.excludeFromTotals = excludeFromTotals; self.archivedAt = archivedAt
    self.createdAt = createdAt; self.updatedAt = updatedAt
  }

  var type: AccountType {
    get { AccountType(rawValue: typeRaw) ?? .bank }
    set { typeRaw = newValue.rawValue }
  }
  var displayName: String { last4.map { "\(name) ••\($0)" } ?? name }
}

@Model final class Category {
  @Attribute(.unique) var id: String
  var parentId: String?
  var kindRaw: String
  var name: String
  var icon: String
  var color: String
  var sortOrder: Int
  var archivedAt: Date?
  var createdAt: Date
  var updatedAt: Date

  init(id: String = UUID().uuidString.lowercased(), parentId: String? = nil, kind: CategoryKind, name: String,
       icon: String, color: String, sortOrder: Int = 0, archivedAt: Date? = nil,
       createdAt: Date = .now, updatedAt: Date = .now) {
    self.id = id; self.parentId = parentId; self.kindRaw = kind.rawValue; self.name = name
    self.icon = icon; self.color = color; self.sortOrder = sortOrder; self.archivedAt = archivedAt
    self.createdAt = createdAt; self.updatedAt = updatedAt
  }

  var kind: CategoryKind {
    get { CategoryKind(rawValue: kindRaw) ?? .expense }
    set { kindRaw = newValue.rawValue }
  }
}

@Model final class Txn {
  @Attribute(.unique) var id: String
  var typeRaw: String
  /// Paise, always > 0.
  var amount: Int
  var accountId: String
  var toAccountId: String?
  var categoryId: String?
  var payee: String?
  var note: String?
  var occurredAt: Date
  var source: String
  var recurringId: String?
  var importBatchId: String?
  var externalId: String?
  var currency: String?
  var originalAmount: Int?
  /// Split with friends: your share in paise (nil = not split). See Splits.swift.
  var splitShare: Int?
  /// The debit or credit card used ("Paid with"), if any.
  var cardId: String?
  /// Tags like "goa-trip" (no #), for trips and projects that span categories.
  var tags: [String] = []
  /// File name of a receipt photo in Documents/receipts (kept on this phone, not in backups).
  var receipt: String?
  var deletedAt: Date?
  var createdAt: Date
  var updatedAt: Date

  init(id: String = UUID().uuidString.lowercased(), type: TxnType, amount: Int, accountId: String,
       toAccountId: String? = nil, categoryId: String? = nil, payee: String? = nil, note: String? = nil,
       occurredAt: Date = .now, source: String = "manual", recurringId: String? = nil,
       importBatchId: String? = nil, externalId: String? = nil, currency: String? = nil,
       originalAmount: Int? = nil, splitShare: Int? = nil, cardId: String? = nil, deletedAt: Date? = nil,
       createdAt: Date = .now, updatedAt: Date = .now) {
    self.id = id; self.typeRaw = type.rawValue; self.amount = amount; self.accountId = accountId
    self.toAccountId = type == .transfer ? toAccountId : nil
    self.categoryId = type == .transfer ? nil : categoryId
    self.payee = payee; self.note = note; self.occurredAt = occurredAt; self.source = source
    self.recurringId = recurringId; self.importBatchId = importBatchId; self.externalId = externalId
    self.currency = currency; self.originalAmount = originalAmount; self.splitShare = splitShare; self.cardId = cardId
    self.deletedAt = deletedAt; self.createdAt = createdAt; self.updatedAt = updatedAt
  }

  var type: TxnType {
    get { TxnType(rawValue: typeRaw) ?? .expense }
    set { typeRaw = newValue.rawValue }
  }
  /// What counts towards your spending: your share when split.
  var effectiveAmount: Int { splitShare ?? amount }
}

@Model final class Budget {
  @Attribute(.unique) var id: String
  /// nil = overall budget.
  var categoryId: String?
  /// "monthly" | "weekly"
  var period: String
  var amount: Int
  var createdAt: Date
  var updatedAt: Date

  init(id: String = UUID().uuidString.lowercased(), categoryId: String? = nil, period: String = "monthly",
       amount: Int, createdAt: Date = .now, updatedAt: Date = .now) {
    self.id = id; self.categoryId = categoryId; self.period = period; self.amount = amount
    self.createdAt = createdAt; self.updatedAt = updatedAt
  }
}

@Model final class RecurringRule {
  @Attribute(.unique) var id: String
  var typeRaw: String
  var amount: Int
  var accountId: String
  var toAccountId: String?
  var categoryId: String?
  var payee: String?
  var note: String?
  var frequencyRaw: String
  var interval: Int
  var startAt: Date
  var nextAt: Date
  var endAt: Date?
  var pausedAt: Date?
  var createdAt: Date
  var updatedAt: Date

  init(id: String = UUID().uuidString.lowercased(), type: TxnType, amount: Int, accountId: String,
       toAccountId: String? = nil, categoryId: String? = nil, payee: String? = nil, note: String? = nil,
       frequency: Frequency, interval: Int = 1, startAt: Date, nextAt: Date? = nil, endAt: Date? = nil,
       pausedAt: Date? = nil, createdAt: Date = .now, updatedAt: Date = .now) {
    self.id = id; self.typeRaw = type.rawValue; self.amount = amount; self.accountId = accountId
    self.toAccountId = toAccountId; self.categoryId = categoryId; self.payee = payee; self.note = note
    self.frequencyRaw = frequency.rawValue; self.interval = max(1, interval); self.startAt = startAt
    self.nextAt = nextAt ?? startAt; self.endAt = endAt; self.pausedAt = pausedAt
    self.createdAt = createdAt; self.updatedAt = updatedAt
  }

  var type: TxnType { TxnType(rawValue: typeRaw) ?? .expense }
  var frequency: Frequency {
    get { Frequency(rawValue: frequencyRaw) ?? .monthly }
    set { frequencyRaw = newValue.rawValue }
  }
}

/// A person you split expenses with (feature: splits).
@Model final class Friend {
  @Attribute(.unique) var id: String
  var name: String
  var upiId: String?
  var phone: String?
  var createdAt: Date

  init(id: String = UUID().uuidString.lowercased(), name: String, upiId: String? = nil, phone: String? = nil, createdAt: Date = .now) {
    self.id = id; self.name = name; self.upiId = upiId; self.phone = phone; self.createdAt = createdAt
  }
}

/// One person's part of a split expense, or a settle-up payment.
/// amount > 0: they owe you. amount < 0: you owe them.
@Model final class SplitEntry {
  @Attribute(.unique) var id: String
  var friendId: String
  /// The expense it came from; nil for a settle-up.
  var txnId: String?
  var amount: Int
  var note: String?
  /// The split group it belongs to, if any.
  var groupId: String?
  var occurredAt: Date
  var createdAt: Date

  init(id: String = UUID().uuidString.lowercased(), friendId: String, txnId: String? = nil, amount: Int,
       note: String? = nil, groupId: String? = nil, occurredAt: Date = .now, createdAt: Date = .now) {
    self.id = id; self.friendId = friendId; self.txnId = txnId; self.amount = amount; self.note = note
    self.groupId = groupId; self.occurredAt = occurredAt; self.createdAt = createdAt
  }
}

/// A savings goal (feature: goals).
@Model final class Goal {
  @Attribute(.unique) var id: String
  var name: String
  var icon: String
  var color: String
  var target: Int
  var saved: Int
  var deadline: Date?
  var archivedAt: Date?
  var createdAt: Date

  init(id: String = UUID().uuidString.lowercased(), name: String, icon: String = "star.fill",
       color: String = "#5E5CE6", target: Int, saved: Int = 0, deadline: Date? = nil,
       archivedAt: Date? = nil, createdAt: Date = .now) {
    self.id = id; self.name = name; self.icon = icon; self.color = color; self.target = target
    self.saved = saved; self.deadline = deadline; self.archivedAt = archivedAt; self.createdAt = createdAt
  }
}

/// A debit card linked to a bank account, or a credit card (linked to its own card account).
/// Only the last 4 digits, network and expiry are stored: never the full number or the CVV.
@Model final class PaymentCard {
  @Attribute(.unique) var id: String
  var accountId: String
  /// "debit" | "credit"
  var kind: String
  /// visa | mastercard | rupay | amex | diners | discover | other
  var network: String
  var last4: String
  var expiryMonth: Int?
  var expiryYear: Int?
  var nameOnCard: String?
  var label: String?
  var color: String?
  var archivedAt: Date?
  var createdAt: Date

  init(id: String = UUID().uuidString.lowercased(), accountId: String, kind: String = "debit", network: String = "other",
       last4: String, expiryMonth: Int? = nil, expiryYear: Int? = nil, nameOnCard: String? = nil, label: String? = nil,
       color: String? = nil, archivedAt: Date? = nil, createdAt: Date = .now) {
    self.id = id; self.accountId = accountId; self.kind = kind; self.network = network; self.last4 = last4
    self.expiryMonth = expiryMonth; self.expiryYear = expiryYear; self.nameOnCard = nameOnCard; self.label = label
    self.color = color; self.archivedAt = archivedAt; self.createdAt = createdAt
  }

  var expiryText: String? {
    guard let m = expiryMonth, let y = expiryYear else { return nil }
    return String(format: "%02d/%02d", m, y % 100)
  }
  var title: String { label ?? "\(CardNumber.networkName(network)) ••\(last4)" }
}

/// A named Activity filter. `filters` is JSON shared with Android and the RN app:
/// {"filters":{"monthOffset":null,"accountIds":[],"categoryIds":[],"types":[]},"search":""}
@Model final class SavedFilter {
  @Attribute(.unique) var id: String
  var name: String
  var filters: String
  var sortOrder: Int
  var createdAt: Date
  var updatedAt: Date

  init(id: String = UUID().uuidString.lowercased(), name: String, filters: String, sortOrder: Int = 0,
       createdAt: Date = .now, updatedAt: Date = .now) {
    self.id = id; self.name = name; self.filters = filters; self.sortOrder = sortOrder
    self.createdAt = createdAt; self.updatedAt = updatedAt
  }
}

/// One statement import, so it can be undone (its transactions carry importBatchId).
@Model final class ImportBatch {
  @Attribute(.unique) var id: String
  var accountId: String
  var fileName: String
  var template: String?
  var count: Int
  var createdAt: Date
  var undoneAt: Date?

  init(id: String = UUID().uuidString.lowercased(), accountId: String, fileName: String, template: String? = nil,
       count: Int, createdAt: Date = .now, undoneAt: Date? = nil) {
    self.id = id; self.accountId = accountId; self.fileName = fileName; self.template = template
    self.count = count; self.createdAt = createdAt; self.undoneAt = undoneAt
  }
}

/// A saved set of people you split with (flatmates, a trip).
@Model final class SplitGroup {
  @Attribute(.unique) var id: String
  var name: String
  var memberIds: [String]
  var createdAt: Date

  init(id: String = UUID().uuidString.lowercased(), name: String, memberIds: [String], createdAt: Date = .now) {
    self.id = id; self.name = name; self.memberIds = memberIds; self.createdAt = createdAt
  }
}

/// Money you lent or borrowed, separate from split balances.
@Model final class Loan {
  @Attribute(.unique) var id: String
  var person: String
  var friendId: String?
  /// "lent" | "borrowed"
  var direction: String
  var amount: Int
  var startedAt: Date
  var dueAt: Date?
  var note: String?
  var remind: Bool
  var closedAt: Date?
  var createdAt: Date

  init(id: String = UUID().uuidString.lowercased(), person: String, friendId: String? = nil, direction: String = "lent", amount: Int,
       startedAt: Date = .now, dueAt: Date? = nil, note: String? = nil, remind: Bool = true, closedAt: Date? = nil, createdAt: Date = .now) {
    self.id = id; self.person = person; self.friendId = friendId; self.direction = direction; self.amount = amount
    self.startedAt = startedAt; self.dueAt = dueAt; self.note = note; self.remind = remind; self.closedAt = closedAt; self.createdAt = createdAt
  }
  var lent: Bool { direction == "lent" }
}

/// A part repayment of a loan.
@Model final class LoanPayment {
  @Attribute(.unique) var id: String
  var loanId: String
  var amount: Int
  var occurredAt: Date
  var note: String?

  init(id: String = UUID().uuidString.lowercased(), loanId: String, amount: Int, occurredAt: Date = .now, note: String? = nil) {
    self.id = id; self.loanId = loanId; self.amount = amount; self.occurredAt = occurredAt; self.note = note
  }
}

/// A one-tap transaction ("Metro ₹40").
@Model final class TxnTemplate {
  @Attribute(.unique) var id: String
  var name: String
  var typeRaw: String
  var amount: Int
  var accountId: String?
  var toAccountId: String?
  var categoryId: String?
  var payee: String?
  var sortOrder: Int
  var createdAt: Date

  init(id: String = UUID().uuidString.lowercased(), name: String, type: TxnType, amount: Int, accountId: String? = nil,
       toAccountId: String? = nil, categoryId: String? = nil, payee: String? = nil, sortOrder: Int = 0, createdAt: Date = .now) {
    self.id = id; self.name = name; self.typeRaw = type.rawValue; self.amount = amount; self.accountId = accountId
    self.toAccountId = toAccountId; self.categoryId = categoryId; self.payee = payee; self.sortOrder = sortOrder; self.createdAt = createdAt
  }
  var type: TxnType { TxnType(rawValue: typeRaw) ?? .expense }
}

/// The value of an investment account on a date (Groww, mutual funds, PF). Balances use the latest one.
@Model final class Valuation {
  @Attribute(.unique) var id: String
  var accountId: String
  var value: Int
  var at: Date

  init(id: String = UUID().uuidString.lowercased(), accountId: String, value: Int, at: Date = .now) {
    self.id = id; self.accountId = accountId; self.value = value; self.at = at
  }
}
