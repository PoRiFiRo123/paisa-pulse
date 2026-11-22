package com.paisapulse.app.data

import kotlinx.serialization.Serializable
import kotlinx.serialization.Transient
import java.util.UUID

// The app's storage IS the backup format (v4, shared with the iPhone app's BackupCodec), so a backup
// from either phone restores on the other. Money: Long paise, always > 0 on transactions.

fun newId(): String = UUID.randomUUID().toString().lowercase()
fun now(): Long = System.currentTimeMillis()

enum class TxnType(val key: String, val label: String) {
  Expense("expense", "Expense"), Income("income", "Income"), Transfer("transfer", "Transfer");
  companion object { fun of(k: String?) = entries.firstOrNull { it.key == k } ?: Expense }
}

enum class AccountType(val key: String, val label: String, val plural: String, val icon: String) {
  Bank("bank", "Bank account", "Bank accounts", "building.columns.fill"),
  Card("card", "Credit card", "Credit cards", "creditcard.fill"),
  Cash("cash", "Cash", "Cash", "banknote.fill"),
  Wallet("wallet", "Wallet", "Wallets", "wallet.bifold.fill");
  companion object { fun of(k: String?) = entries.firstOrNull { it.key == k } ?: Bank }
}

enum class Frequency(val key: String, val noun: String) {
  Daily("daily", "day"), Weekly("weekly", "week"), Monthly("monthly", "month"), Yearly("yearly", "year");
  companion object { fun of(k: String?) = entries.firstOrNull { it.key == k } ?: Monthly }
}

@Serializable data class Account(
  val id: String = newId(), val name: String, val type: String = "bank", val institution: String? = null,
  val last4: String? = null, val openingBalance: Long = 0, val currency: String? = "INR", val creditLimit: Long? = null,
  val statementDay: Int? = null, val dueDay: Int? = null, val color: String = "#5E5CE6", val icon: String = "building.columns.fill",
  val sortOrder: Int = 0, val excludeFromTotals: Boolean? = false, val archivedAt: Long? = null,
  val createdAt: Long = now(), val updatedAt: Long = now(),
) {
  val kind get() = AccountType.of(type)
  val displayName get() = last4?.let { "$name ••$it" } ?: name
}

@Serializable data class Category(
  val id: String = newId(), val parentId: String? = null, val kind: String = "expense", val name: String,
  val icon: String = "tag.fill", val color: String = "#5E5CE6", val sortOrder: Int = 0, val archivedAt: Long? = null,
  val createdAt: Long? = now(), val updatedAt: Long? = now(),
)

@Serializable data class Txn(
  val id: String = newId(), val type: String = "expense", val amount: Long, val accountId: String,
  val toAccountId: String? = null, val categoryId: String? = null, val payee: String? = null, val note: String? = null,
  val occurredAt: Long = now(), val source: String? = "manual", val importBatchId: String? = null,
  val externalId: String? = null, val currency: String? = null, val originalAmount: Long? = null,
  val recurringId: String? = null, val deletedAt: Long? = null, val createdAt: Long = now(), val updatedAt: Long = now(),
  /** The debit or credit card used ("Paid with"). */
  val cardId: String? = null,
  /** Your share when split (stored in BackupFile.txnSplitShares, like the iPhone app). */
  @Transient val splitShare: Long? = null,
) {
  val kind get() = TxnType.of(type)
  /** What counts towards your spending. */
  val effectiveAmount get() = splitShare ?: amount
}

@Serializable data class Budget(
  val id: String = newId(), val categoryId: String? = null, val period: String? = "monthly", val amount: Long,
  val createdAt: Long = now(), val updatedAt: Long = now(),
)

@Serializable data class RecurringRule(
  val id: String = newId(), val type: String = "expense", val amount: Long, val accountId: String,
  val toAccountId: String? = null, val categoryId: String? = null, val payee: String? = null, val note: String? = null,
  val frequency: String = "monthly", val interval: Int = 1, val startAt: Long, val nextAt: Long, val endAt: Long? = null,
  val pausedAt: Long? = null, val createdAt: Long = now(), val updatedAt: Long = now(),
) { val freq get() = Frequency.of(frequency) }

@Serializable data class Friend(
  val id: String = newId(), val name: String, val upiId: String? = null, val createdAt: Long = now(),
  val phone: String? = null,
)

/** amount > 0: they owe you; < 0: you owe them. txnId null = settle-up / manual entry. */
@Serializable data class SplitEntry(
  val id: String = newId(), val friendId: String, val txnId: String? = null, val amount: Long, val note: String? = null,
  val occurredAt: Long = now(), val createdAt: Long = now(), val groupId: String? = null,
)

/** A saved set of people you split with. */
@Serializable data class SplitGroup(val id: String = newId(), val name: String, val memberIds: List<String> = emptyList(), val createdAt: Long = now())

/** Money lent or borrowed ("lent" | "borrowed"), separate from splits. */
@Serializable data class Loan(
  val id: String = newId(), val person: String, val friendId: String? = null, val direction: String = "lent", val amount: Long,
  val startedAt: Long = now(), val dueAt: Long? = null, val note: String? = null, val remind: Boolean? = true, val closedAt: Long? = null,
  val createdAt: Long = now(),
) { val lent get() = direction == "lent" }

@Serializable data class LoanPayment(val id: String = newId(), val loanId: String, val amount: Long, val occurredAt: Long = now(), val note: String? = null)

@Serializable data class Goal(
  val id: String = newId(), val name: String, val icon: String = "star.fill", val color: String = "#5E5CE6",
  val target: Long, val saved: Long = 0, val deadline: Long? = null, val archivedAt: Long? = null, val createdAt: Long = now(),
)

/** Debit card linked to a bank account, or a credit card linked to its card account. Last 4 + network + expiry only. */
@Serializable data class PaymentCard(
  val id: String = newId(), val accountId: String, val kind: String = "debit", val network: String = "other", val last4: String,
  val expiryMonth: Int? = null, val expiryYear: Int? = null, val nameOnCard: String? = null, val label: String? = null,
  val color: String? = null, val archivedAt: Long? = null, val createdAt: Long = now(),
) {
  val expiryText get() = if (expiryMonth != null && expiryYear != null) "%02d/%02d".format(expiryMonth, expiryYear % 100) else null
  val title get() = label ?: "${com.paisapulse.app.logic.CardNumber.networkName(network)} ••$last4"
}

/** Named Activity filter; `filters` JSON is shared with iOS: {"filters":{"monthOffset":…,"accountIds":[],"categoryIds":[],"types":[]},"search":""} */
@Serializable data class SavedFilter(
  val id: String = newId(), val name: String, val filters: String, val sortOrder: Int = 0, val createdAt: Long = now(), val updatedAt: Long = now(),
)

/** One statement import (its transactions carry importBatchId), so it can be undone. */
@Serializable data class ImportBatch(
  val id: String = newId(), val accountId: String, val fileName: String, val template: String? = null, val count: Int,
  val createdAt: Long = now(), val undoneAt: Long? = null,
)

@Serializable data class Setting(val key: String, val value: String)
@Serializable data class Share(val id: String, val share: Long)

@Serializable data class Db(
  val format: String = "paisa-pulse-backup",
  val version: Int = 4,
  val exportedAt: Long = 0,
  val accounts: List<Account> = emptyList(),
  val categories: List<Category> = emptyList(),
  val transactions: List<Txn> = emptyList(),
  val settings: List<Setting> = emptyList(),
  val recurringRules: List<RecurringRule> = emptyList(),
  val budgets: List<Budget> = emptyList(),
  val savedFilters: List<SavedFilter> = emptyList(),
  val importBatches: List<ImportBatch> = emptyList(),
  val friends: List<Friend> = emptyList(),
  val splitEntries: List<SplitEntry> = emptyList(),
  val goals: List<Goal> = emptyList(),
  val txnSplitShares: List<Share> = emptyList(),
  val cards: List<PaymentCard> = emptyList(),
  val splitGroups: List<SplitGroup> = emptyList(),
  val loans: List<Loan> = emptyList(),
  val loanPayments: List<LoanPayment> = emptyList(),
) {
  val liveTxns get() = transactions.filter { it.deletedAt == null }
}
