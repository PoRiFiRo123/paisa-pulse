package com.paisapulse.app.logic

import com.paisapulse.app.data.*
import java.security.SecureRandom
import java.time.Instant
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

// Batch 4 logic, the same rules as the iPhone app's Shared/Batch4.swift.

object PayeeMemory {
  data class Suggestion(val payee: String, val categoryId: String?, val accountId: String, val count: Int)

  fun suggestions(prefix: String, txns: List<Txn>, type: TxnType, limit: Int = 4): List<Suggestion> {
    val q = prefix.trim().lowercase()
    if (q.isEmpty()) return emptyList()
    data class G(val payee: String, var latest: Txn, var count: Int)
    val groups = LinkedHashMap<String, G>()
    for (t in txns) {
      if (t.deletedAt != null || t.kind != type) continue
      val p = t.payee?.trim()?.takeIf { it.isNotEmpty() } ?: continue
      val key = p.lowercase()
      if (!(key.startsWith(q) || key.contains(" $q")) || key == q) continue
      val g = groups[key]
      if (g == null) groups[key] = G(p, t, 1) else { g.count++; if (t.occurredAt > g.latest.occurredAt) g.latest = t }
    }
    return groups.values.sortedWith(compareByDescending<G> { it.count }.thenByDescending { it.latest.occurredAt }).take(limit)
      .map { Suggestion(it.payee, it.latest.categoryId, it.latest.accountId, it.count) }
  }
}

object Tags {
  fun parse(text: String): List<String> = text.split(',', '#').map { it.trim().lowercase().split(Regex("\\s+")).filter { w -> w.isNotEmpty() }.joinToString("-") }
    .filter { it.isNotEmpty() }.distinct()
  fun text(tags: List<String>?) = tags.orEmpty().joinToString(", ")
}

object Forecast {
  data class Result(val now: Long, val incoming: Long, val outgoing: Long, val dailySpend: Long, val daysLeft: Int, val projected: Long)

  fun monthEnd(accounts: List<Account>, txns: List<Txn>, valuations: List<Valuation>, rules: List<RecurringRule>, month: Range,
               now: Long = System.currentTimeMillis()): Result {
    val liquid = accounts.filter { it.archivedAt == null && it.excludeFromTotals != true && it.kind in setOf(AccountType.Bank, AccountType.Cash, AccountType.Wallet) }
    val ids = liquid.map { it.id }.toSet()
    val b = Ledger.balances(accounts, txns, valuations)
    val current = liquid.sumOf { b[it.id] ?: 0 }
    var incoming = 0L; var outgoing = 0L
    for (r in rules) {
      if (r.pausedAt != null) continue
      var next = r.nextAt; var guard = 0
      while (next < month.end && next >= now && guard < 40) {
        if (r.endAt != null && next > r.endAt) break
        when (r.type) {
          "income" -> if (r.accountId in ids) incoming += r.amount
          "expense" -> if (r.accountId in ids) outgoing += r.amount
          "transfer" -> r.toAccountId?.let { to ->
            if (r.accountId in ids && to !in ids) outgoing += r.amount
            if (r.accountId !in ids && to in ids) incoming += r.amount
          }
        }
        next = Recurrence.next(next, r); guard++
      }
    }
    val since = now - 90L * 86_400_000
    val everyday = txns.filter { it.deletedAt == null && it.kind == TxnType.Expense && it.recurringId == null && it.occurredAt in since..now }.sumOf { it.effectiveAmount }
    val daily = Math.round(everyday / 90.0 / 100.0) * 100
    val today = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
    val end = Instant.ofEpochMilli(month.end).atZone(zone).toLocalDate()
    val daysLeft = maxOf(0, java.time.temporal.ChronoUnit.DAYS.between(today, end).toInt())
    return Result(current, incoming, outgoing, daily, daysLeft, Math.round((current + incoming - outgoing - daily * daysLeft) / 100.0) * 100)
  }
}

object Recap {
  data class Result(
    val spent: Long, val income: Long, val previousSpent: Long, val count: Int, val topCategoryId: String?, val topCategoryAmount: Long,
    val biggestId: String?, val topPayee: String?, val topPayeeCount: Int, val noSpendDays: Int, val longestNoSpendStreak: Int, val days: Int,
  ) {
    val change: Double? get() = if (previousSpent > 0) (spent - previousSpent).toDouble() / previousSpent else null
    val saved get() = income - spent
  }

  fun make(txns: List<Txn>, categories: Map<String, Category>, month: Range, previous: Range, now: Long = System.currentTimeMillis()): Result {
    val s = Ledger.summary(txns, month); val p = Ledger.summary(txns, previous)
    val inMonth = txns.filter { it.deletedAt == null && it.occurredAt in month }
    val expenses = inMonth.filter { it.kind == TxnType.Expense }
    val top = Ledger.byCategory(txns, month, categories).firstOrNull()
    val biggest = expenses.maxByOrNull { it.effectiveAmount }
    val payees = expenses.mapNotNull { it.payee?.trim()?.takeIf { p -> p.isNotEmpty() } }.groupBy { it.lowercase() }
    val topPayee = payees.values.maxByOrNull { it.size }
    val spendDays = expenses.map { it.occurredAt.toDate() }.toSet()
    var day = month.start.toDate()
    val last = minOf(month.end.toDate(), now.toDate().plusDays(1))
    var days = 0; var free = 0; var streak = 0; var best = 0
    while (day.isBefore(last)) {
      days++
      if (day in spendDays) streak = 0 else { free++; streak++; best = maxOf(best, streak) }
      day = day.plusDays(1)
    }
    return Result(s.spent, s.income, p.spent, inMonth.size, top?.first?.ifEmpty { null }, top?.second ?: 0, biggest?.id,
      topPayee?.first(), topPayee?.size ?: 0, free, best, days)
  }
}

object CardStatement {
  data class Result(val cycle: Range, val billed: Long, val paid: Long) { val due get() = maxOf(0L, billed - paid) }

  fun last(account: Account, txns: List<Txn>, now: Long = System.currentTimeMillis()): Result? {
    val s = account.statementDay ?: return null
    val current = Cards.cycle(s, now.toDate())
    val previous = Range(current.start.toDate().minusMonths(1).ms(), current.start)
    val live = txns.filter { it.deletedAt == null }
    val billed = live.filter { it.accountId == account.id && it.occurredAt in previous }.sumOf {
      when (it.kind) { TxnType.Expense -> it.amount; TxnType.Income -> -it.amount; TxnType.Transfer -> if (it.toAccountId == null) 0 else it.amount }
    }
    val paid = live.filter { it.kind == TxnType.Transfer && it.toAccountId == account.id && it.occurredAt >= current.start }.sumOf { it.amount }
    return Result(previous, maxOf(0L, billed), paid)
  }
}

object HomeSections {
  val all = listOf(
    Triple("hero", "This month", "indianrupeesign.circle.fill"), Triple("trips", "Planning", "airplane"), Triple("templates", "Quick add", "bolt.fill"),
    Triple("forecast", "Month-end forecast", "chart.line.uptrend.xyaxis"), Triple("cards", "Card bills", "creditcard.fill"),
    Triple("categories", "Where it went", "chart.pie.fill"), Triple("budgets", "Budgets", "gauge.with.dots.needle.67percent"),
    Triple("goals", "Goals", "target"), Triple("upcoming", "Next 7 days", "calendar"), Triple("recap", "Monthly recap", "sparkles"),
    Triple("recent", "Recent", "clock.fill"),
  )
  fun order(saved: String): List<String> {
    val known = all.map { it.first }.toSet()
    val s = saved.split(',').filter { it in known }
    return s + all.map { it.first }.filter { it !in s }
  }
  fun hidden(saved: String) = saved.split(',').filter { it.isNotEmpty() }.toSet()
}

/** Password-protected backups: AES-256-GCM with a PBKDF2-SHA256 key; the same file format as iOS. */
object BackupCrypto {
  class WrongPassword : Exception("wrong password")
  private val b64 = Base64.getEncoder(); private val d64 = Base64.getDecoder()

  fun isEncrypted(text: String) = text.trimStart().startsWith("{") && text.contains("\"paisaEncrypted\"")

  private fun key(password: String, salt: ByteArray, iterations: Int) =
    SecretKeySpec(SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(PBEKeySpec(password.toCharArray(), salt, iterations, 256)).encoded, "AES")

  fun encrypt(plain: ByteArray, password: String, iterations: Int = 200_000): String {
    val rnd = SecureRandom(); val salt = ByteArray(16).also(rnd::nextBytes); val iv = ByteArray(12).also(rnd::nextBytes)
    val c = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key(password, salt, iterations), GCMParameterSpec(128, iv)) }
    val out = c.doFinal(plain) // ciphertext + 16-byte tag, like iOS
    return """{"paisaEncrypted":1,"kdf":"pbkdf2-sha256","iterations":$iterations,"salt":"${b64.encodeToString(salt)}","iv":"${b64.encodeToString(iv)}","data":"${b64.encodeToString(out)}"}"""
  }

  fun decrypt(text: String, password: String): ByteArray {
    fun field(k: String) = Regex("\"$k\"\\s*:\\s*\"?([^\",}]*)\"?").find(text)?.groupValues?.get(1)?.replace("\\/", "/") ?: throw IllegalArgumentException("not encrypted")
    val iterations = field("iterations").toInt(); val salt = d64.decode(field("salt")); val iv = d64.decode(field("iv")); val data = d64.decode(field("data"))
    return try {
      Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.DECRYPT_MODE, key(password, salt, iterations), GCMParameterSpec(128, iv)) }.doFinal(data)
    } catch (e: javax.crypto.AEADBadTagException) { throw WrongPassword() }
  }
}
