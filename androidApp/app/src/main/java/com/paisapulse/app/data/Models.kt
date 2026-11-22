package com.paisapulse.app.data

import kotlinx.serialization.Serializable
import kotlinx.serialization.Transient
import kotlinx.serialization.json.JsonObject
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
  val occurredAt: Long = now(), val createdAt: Long = now(),
)

@Serializable data class Goal(
  val id: String = newId(), val name: String, val icon: String = "star.fill", val color: String = "#5E5CE6",
  val target: Long, val saved: Long = 0, val deadline: Long? = null, val archivedAt: Long? = null, val createdAt: Long = now(),
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
  val savedFilters: List<JsonObject> = emptyList(),
  val importBatches: List<JsonObject> = emptyList(),
  val friends: List<Friend> = emptyList(),
  val splitEntries: List<SplitEntry> = emptyList(),
  val goals: List<Goal> = emptyList(),
  val txnSplitShares: List<Share> = emptyList(),
) {
  val liveTxns get() = transactions.filter { it.deletedAt == null }
}
