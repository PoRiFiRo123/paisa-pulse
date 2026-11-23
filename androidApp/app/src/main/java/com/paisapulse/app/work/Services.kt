package com.paisapulse.app.work

import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.glance.appwidget.updateAll
import androidx.work.*
import com.paisapulse.app.R
import com.paisapulse.app.data.*
import com.paisapulse.app.logic.*
import com.paisapulse.app.widget.SpendingWidget
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.io.File
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import java.util.concurrent.TimeUnit

/** Launch/foreground/daily chores, notifications and widget refresh. Mirrors iOS Maintenance + Notifier. */
@SuppressLint("StaticFieldLeak")
object Services {
  lateinit var ctx: Context
  private val scope = CoroutineScope(Dispatchers.IO)
  private const val CHANNEL = "paisa"

  fun init(c: Context) {
    ctx = c.applicationContext
    ctx.getSystemService(NotificationManager::class.java).createNotificationChannel(NotificationChannel(CHANNEL, "Paisa Pulse", NotificationManager.IMPORTANCE_DEFAULT))
    WorkManager.getInstance(ctx).enqueueUniquePeriodicWork("daily", ExistingPeriodicWorkPolicy.KEEP,
      PeriodicWorkRequestBuilder<DailyWorker>(12, TimeUnit.HOURS).build())
  }

  fun runMaintenance() {
    val (due, next) = Recurrence.due(Store.value.recurringRules, now())
    val cutoff = now() - 30 * 86_400_000L
    Store.update { d ->
      d.copy(
        transactions = d.transactions.filterNot { (it.deletedAt ?: Long.MAX_VALUE) < cutoff } + due.map { (r, at) ->
          Txn(type = r.type, amount = r.amount, accountId = r.accountId, toAccountId = r.toAccountId, categoryId = r.categoryId,
            payee = r.payee, note = r.note, occurredAt = at, source = "recurring", recurringId = r.id)
        },
        recurringRules = d.recurringRules.map { r -> next[r.id]?.let { r.copy(nextAt = it) } ?: r },
      )
    }
    BackupOps.runIfDue(ctx)
    com.paisapulse.app.ui.screens.DataCleanup.runIfDue(ctx)
    refreshNotifications()
    refreshWidget()
  }

  fun refreshWidget() { scope.launch { runCatching { SpendingWidget().updateAll(ctx) } } }

  fun notify(id: Int, title: String, body: String) {
    if (!NotificationManagerCompat.from(ctx).areNotificationsEnabled()) return
    val n = NotificationCompat.Builder(ctx, CHANNEL).setSmallIcon(R.mipmap.ic_launcher).setContentTitle(title).setContentText(body).setAutoCancel(true).build()
    runCatching { NotificationManagerCompat.from(ctx).notify(id, n) }
  }

  private val sp get() = ctx.getSharedPreferences("paisa-notified", Context.MODE_PRIVATE)
  private fun once(key: String, block: () -> Unit) { if (!sp.getBoolean(key, false)) { sp.edit().putBoolean(key, true).apply(); block() } }

  /** Bill reminders 3 days before a card's due day; Sunday summary. Checked on launch and by the daily worker. */
  fun refreshNotifications() {
    val d = Store.value
    if (Prefs.notifyBills) {
      val b = Ledger.balances(d.accounts, d.transactions, d.valuations)
      d.accounts.filter { it.kind == AccountType.Card && it.archivedAt == null && it.dueDay != null }.forEach { a ->
        val owed = maxOf(0L, -(b[a.id] ?: 0)); val due = Cards.nextDue(a.dueDay!!)
        val days = ChronoUnit.DAYS.between(LocalDate.now(), due)
        if (owed > 0 && days in 0..3) once("bill-${a.id}-$due") {
          notify(a.id.hashCode(), "${a.name} bill due ${if (days == 0L) "today" else "in $days days"}", "${Money.format(owed)} to pay by ${due.dayOfMonth} ${due.month.name.lowercase().replaceFirstChar { it.uppercase() }.take(3)}. Pay on time to avoid interest.")
        }
      }
    }
    // Loans: on the day they're due.
    val today = LocalDate.now()
    d.loans.filter { it.closedAt == null && it.remind != false && it.dueAt != null }.forEach { l ->
      val left = LoanMath.outstanding(l, d.loanPayments)
      val due = Instant.ofEpochMilli(l.dueAt!!).atZone(zone).toLocalDate()
      if (left > 0 && due == today && java.time.LocalTime.now().hour >= 9) once("loan-${l.id}-$due") {
        notify(l.id.hashCode(), if (l.lent) "${l.person} is due to pay you back" else "Loan from ${l.person} is due",
          "${Money.format(left)} ${if (l.lent) "to get back" else "to pay back"} today.")
      }
    }
    if (Prefs.notifyWeekly && LocalDate.now().dayOfWeek == DayOfWeek.SUNDAY && java.time.LocalTime.now().hour >= 18) once("weekly-${LocalDate.now()}") {
      val w = Periods.week(LocalDate.now(), 2)
      notify(7, "Your week in money", "You spent ${Money.format(Ledger.summary(d.transactions, w).spent)} this week. See how your budgets look.")
    }
  }

  /** Right after a save: once per period when a budget passes 80% or 100%. */
  fun checkBudgets() {
    if (!Prefs.notifyBudgets) return
    val d = Store.value; val cats = d.categories.associateBy { it.id }
    val m = Periods.month(LocalDate.now(), Prefs.monthStartDay); val w = Periods.week(LocalDate.now(), Prefs.weekStartDay)
    Budgets.progress(d.budgets, com.paisapulse.app.logic.TripMath.budgetTxns(d.transactions, d.trips), cats, m, w).forEach { p ->
      val level = if (p.ratio >= 1) 100 else if (p.ratio >= 0.8) 80 else 0
      if (level == 0) return@forEach
      val start = if (p.budget.period == "weekly") w.start else m.start
      val name = p.budget.categoryId?.let { cats[it]?.name } ?: "Your"
      val per = if (p.budget.period == "weekly") "week" else "month"
      once("budget-${p.budget.id}-$start-$level") {
        notify(p.budget.id.hashCode() + level, if (level == 100) "$name budget used up" else "$name budget at 80%",
          if (level == 100) "You've spent ${Money.format(p.spent)} of ${Money.format(p.budget.amount)} this $per." else "${Money.format(p.left)} left this $per.")
      }
    }
  }
}

class DailyWorker(c: Context, p: WorkerParameters) : CoroutineWorker(c, p) {
  override suspend fun doWork(): Result { Services.runMaintenance(); return Result.success() }
}

/** Backups: same JSON as the iPhone app. Daily copies (keep 14) in files/backups, also covered by Android backup. */
object BackupOps {
  fun fileName() = "paisa-pulse-${LocalDate.now()}.json"
  fun export(): String = Store.encode(Store.value.copy(settings = Prefs.toSettings()))
  fun decode(text: String): Db {
    val db = Store.decode(text)
    require(db.format == "paisa-pulse-backup") { "This file is not a Paisa Pulse backup." }
    require(db.version <= 4) { "This backup was made by a newer version of Paisa Pulse." }
    require(db.transactions.all { it.amount > 0 }) { "This backup contains an invalid amount." }
    return db
  }
  class NeedsPassword : Exception("This backup is protected with a password.")
  /** What's written to files: encrypted when a backup password is set (same format as iPhone). */
  fun exportFile(c: Context): String = BackupPassword.get(c)?.let { BackupCrypto.encrypt(export().toByteArray(), it) } ?: export()
  /** Opens a plain or encrypted backup. Without a password it tries the saved one, else throws NeedsPassword. */
  fun open(c: Context, text: String, password: String? = null): Db {
    if (!BackupCrypto.isEncrypted(text)) return decode(text)
    val pw = password ?: BackupPassword.get(c) ?: throw NeedsPassword()
    val plain = try { BackupCrypto.decrypt(text, pw) } catch (e: BackupCrypto.WrongPassword) {
      if (password == null) throw NeedsPassword() else throw IllegalArgumentException("Wrong password.")
    }
    return decode(String(plain, Charsets.UTF_8))
  }
  fun restore(db: Db) { Store.replace(db.copy(settings = emptyList())); Prefs.applySettings(db.settings); Services.refreshWidget() }
  private fun dir(c: Context) = File(c.filesDir, "backups").apply { mkdirs() }
  fun list(c: Context) = dir(c).listFiles { f -> f.extension == "json" }?.sortedByDescending { it.name } ?: emptyList()
  fun write(c: Context) {
    File(dir(c), fileName()).writeText(exportFile(c)); Prefs.set("lastBackupAt", now())
    list(c).drop(14).forEach { it.delete() }
  }
  fun runIfDue(c: Context) {
    if (Prefs.autoBackup && now() - Prefs.lastBackupAt > 20 * 3_600_000L && Store.value.transactions.isNotEmpty()) runCatching { write(c) }
  }
  fun csv(db: Db): String {
    val a = db.accounts.associate { it.id to it.name }; val c = db.categories.associate { it.id to it.name }
    fun q(s: String?) = "\"" + (s ?: "").replace("\"", "\"\"") + "\""
    return (listOf("Date,Type,Amount,Your share,Account,To account,Category,Payee,Note") + db.liveTxns.sortedByDescending { it.occurredAt }.map { t ->
      listOf(java.time.Instant.ofEpochMilli(t.occurredAt).toString(), t.type, "%.2f".format(t.amount / 100.0), t.splitShare?.let { "%.2f".format(it / 100.0) } ?: "",
        q(a[t.accountId]), q(t.toAccountId?.let { a[it] }), q(t.categoryId?.let { c[it] }), q(t.payee), q(t.note)).joinToString(",")
    }).joinToString("\n")
  }
}

/** The backup password, encrypted with a key that never leaves this phone's Android Keystore. */
object BackupPassword {
  private const val ALIAS = "paisa_backup_password"
  private fun prefs(c: Context) = c.getSharedPreferences("paisa_secure", Context.MODE_PRIVATE)
  private fun key(): javax.crypto.SecretKey {
    val ks = java.security.KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    (ks.getEntry(ALIAS, null) as? java.security.KeyStore.SecretKeyEntry)?.let { return it.secretKey }
    val g = javax.crypto.KeyGenerator.getInstance(android.security.keystore.KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
    g.init(android.security.keystore.KeyGenParameterSpec.Builder(ALIAS, android.security.keystore.KeyProperties.PURPOSE_ENCRYPT or android.security.keystore.KeyProperties.PURPOSE_DECRYPT)
      .setBlockModes(android.security.keystore.KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(android.security.keystore.KeyProperties.ENCRYPTION_PADDING_NONE).build())
    return g.generateKey()
  }
  fun get(c: Context): String? = runCatching {
    val v = prefs(c).getString("pw", null) ?: return null
    val (iv, data) = v.split(':').map { java.util.Base64.getDecoder().decode(it) }
    val cipher = javax.crypto.Cipher.getInstance("AES/GCM/NoPadding").apply { init(javax.crypto.Cipher.DECRYPT_MODE, key(), javax.crypto.spec.GCMParameterSpec(128, iv)) }
    String(cipher.doFinal(data), Charsets.UTF_8)
  }.getOrNull()
  fun set(c: Context, password: String?) {
    if (password.isNullOrEmpty()) { prefs(c).edit().remove("pw").apply(); return }
    val cipher = javax.crypto.Cipher.getInstance("AES/GCM/NoPadding").apply { init(javax.crypto.Cipher.ENCRYPT_MODE, key()) }
    val data = cipher.doFinal(password.toByteArray())
    val b = java.util.Base64.getEncoder()
    prefs(c).edit().putString("pw", b.encodeToString(cipher.iv) + ":" + b.encodeToString(data)).apply()
  }
}
