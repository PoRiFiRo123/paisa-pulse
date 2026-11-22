package com.paisapulse.app.logic

import com.paisapulse.app.data.Account
import com.paisapulse.app.data.Category
import com.paisapulse.app.data.ImportBatch
import com.paisapulse.app.data.Txn
import com.paisapulse.app.data.newId
import java.time.Instant

/** One statement row ready for review: everything the user can change before importing. Same as iOS PlannedRow. */
data class PlannedRow(
  val key: String, val row: StatementRow, val narration: Narration,
  /** "expense" | "income" | "transfer" */
  val type: String, val otherAccountId: String?, val categoryId: String?, val payee: String?, val note: String?,
  /** "new" | "duplicate" | "possible-duplicate" */
  val status: String, val duplicateOf: String?, val include: Boolean, val hint: String?,
)

object ImportPlan {
  /** 64-bit FNV-1a-ish hex, identical to the RN and iOS fingerprint (re-imports are recognised across apps). */
  fun fingerprint(text: String): String {
    var h1 = 0x811c9dc5L; var h2 = 0xcbf29ce4L
    val p1 = 0x01000193L; val p2 = (0x01000193L xor 0x5bd1e995L)
    for (ch in text) {
      val c = ch.code.toLong()
      h1 = ((h1 xor c) * p1) and 0xffffffffL
      h2 = ((h2 xor c) * p2) and 0xffffffffL
    }
    return h1.toString(16).padStart(8, '0') + h2.toString(16).padStart(8, '0')
  }

  private fun ymd(ms: Long): String { val d = Instant.ofEpochMilli(ms).atZone(zone).toLocalDate(); return "${d.year}-${d.monthValue}-${d.dayOfMonth}" }
  private fun dayIndex(ms: Long) = Instant.ofEpochMilli(ms).atZone(zone).toLocalDate().toEpochDay()

  /** Fingerprint input: amounts in paise and the balance as JS would print them. */
  fun rowKeys(accountId: String, rows: List<StatementRow>): List<String> {
    val seen = HashMap<String, Int>()
    return rows.map { r ->
      val base = fingerprint(listOf(accountId, ymd(r.date), if (r.out) "out" else "in", r.amount.toString(),
        r.description.lowercase().replace(Regex("\\s+"), " "), r.reference, r.balance?.toString() ?: "").joinToString("|"))
      val n = (seen[base] ?: 0) + 1; seen[base] = n
      if (n == 1) base else "$base#$n"
    }
  }

  private fun mentioned(text: String, account: Account, all: List<Account>): Account? {
    val t = text.lowercase()
    return all.firstOrNull { a ->
      a.id != account.id && ((a.last4 != null && Regex("(x|\\*|\\b)${Regex.escape(a.last4)}\\b", RegexOption.IGNORE_CASE).containsMatchIn(text)) ||
        (a.name.length > 5 && t.contains(a.name.lowercase())))
    }
  }

  fun plan(accountId: String, rows: List<StatementRow>, accounts: List<Account>, categories: List<Category>, txns: List<Txn>): List<PlannedRow> {
    val all = accounts.filter { it.archivedAt == null }
    val account = accounts.first { it.id == accountId }
    val cats = categories.filter { it.archivedAt == null }
    fun byName(name: String, kind: String) = cats.firstOrNull { it.kind == kind && it.name == name }?.id
    val cards = all.filter { it.type == "card" && it.id != account.id }
    val banks = all.filter { it.type == "bank" && it.id != account.id }
    val cash = all.firstOrNull { it.type == "cash" && it.id != account.id }
    val live = txns.filter { it.deletedAt == null }
    // Categories learned from your past payees (most used wins).
    val learned = live.filter { it.payee != null && it.categoryId != null }.groupBy { it.payee!!.lowercase() }
      .mapValues { (_, v) -> v.groupingBy { it.categoryId!! }.eachCount().maxByOrNull { it.value }!!.key }
    val keys = rowKeys(account.id, rows)

    val planned = rows.mapIndexed { i, row ->
      val n = Narrations.parse(row.description)
      var type = if (row.out) "expense" else "income"
      var other: Account? = null; var hint: String? = null; var include = true
      val m = mentioned(row.description, account, all)
      if (n.channel == "CARD_PAYMENT") {
        if (account.type == "card" && !row.out) {
          other = m ?: banks.firstOrNull()
          hint = other?.let { "Card bill paid from ${it.name}" } ?: "Card bill payment: add your bank account to pair it"
          if (other == null) include = false
        } else if (row.out) {
          other = cards.firstOrNull { it.last4 != null && row.description.contains(it.last4) } ?: m ?: cards.firstOrNull()
          hint = other?.let { "Paid your ${it.name} bill" }
        }
      } else if (n.channel == "ATM" && row.out && cash != null) {
        other = cash; hint = "Cash withdrawal → Cash"
      } else if (m != null && account.type != "card") {
        other = m; hint = if (row.out) "Moved to ${m.name}" else "Moved from ${m.name}"
      }
      if (other != null) type = "transfer"
      var categoryId: String? = null
      if (type != "transfer") {
        val kind = if (type == "income") "income" else "expense"
        val hist = n.payee?.let { learned[it.lowercase()] }?.takeIf { id -> cats.any { it.id == id && it.kind == kind } }
        categoryId = hist ?: Narrations.suggestCategory(row.description, n.payee, row.out)?.let { byName(it, kind) }
      }
      PlannedRow(keys[i], row, n, type, other?.id, categoryId, n.payee, n.note, "new", null, include, hint)
    }.toMutableList()

    val existing = live.mapNotNull { it.externalId }.toSet()
    for (i in planned.indices) if (planned[i].key in existing) planned[i] = planned[i].copy(status = "duplicate", include = false, hint = "Already imported")

    if (rows.isNotEmpty()) {
      val from = rows.minOf { it.date } - 2 * 86_400_000L; val to = rows.maxOf { it.date } + 2 * 86_400_000L
      val candidates = live.filter { it.occurredAt in from..to && (it.accountId == account.id || it.toAccountId == account.id) }
      val used = HashSet<String>()
      for (i in planned.indices) {
        val p = planned[i]
        if (p.status != "new") continue
        var best: Pair<String, Long>? = null
        for (t in candidates) {
          if (t.id in used || t.amount != p.row.amount) continue
          val out = t.accountId == account.id && t.type != "income"
          if (out != p.row.out) continue
          val d = Math.abs(dayIndex(t.occurredAt) - dayIndex(p.row.date))
          if (d <= 1 && (best == null || d < best.second)) best = t.id to d
        }
        if (best != null) { used.add(best.first); planned[i] = p.copy(status = "possible-duplicate", duplicateOf = best.first, include = false, hint = "Looks like one you already added") }
      }
    }
    return planned
  }

  /** The transactions to add for the included rows, plus the batch record. */
  fun commit(accountId: String, fileName: String, template: String?, rows: List<PlannedRow>, now: Long = System.currentTimeMillis()): Pair<ImportBatch, List<Txn>> {
    val chosen = rows.filter { it.include }
    val batch = ImportBatch(newId(), accountId, fileName, template, chosen.size, now)
    val txns = chosen.map { r ->
      val transfer = r.type == "transfer" && r.otherAccountId != null
      val intoThis = !r.row.out
      Txn(
        type = if (transfer) "transfer" else if (r.type == "transfer") (if (intoThis) "income" else "expense") else r.type,
        amount = r.row.amount,
        accountId = if (transfer && intoThis) r.otherAccountId!! else accountId,
        toAccountId = if (transfer) (if (intoThis) accountId else r.otherAccountId) else null,
        categoryId = if (transfer) null else r.categoryId,
        payee = r.payee, note = r.note, occurredAt = r.row.date, source = "import", importBatchId = batch.id, externalId = r.key,
        createdAt = now, updatedAt = now,
      )
    }
    return batch to txns
  }
}
