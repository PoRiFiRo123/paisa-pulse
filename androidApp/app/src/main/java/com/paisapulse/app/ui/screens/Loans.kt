package com.paisapulse.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.paisapulse.app.data.*
import com.paisapulse.app.logic.*
import com.paisapulse.app.ui.*
import com.paisapulse.app.work.BackupOps
import com.paisapulse.app.work.Services
import java.time.LocalDate

// Loans and data clean-up, mirroring the iPhone LoansView.swift and CleanupView.swift.

@Composable fun LoansScreen() {
  val db by Store.db.collectAsState()
  val open = db.loans.filter { it.closedAt == null }.sortedByDescending { it.startedAt }
  val closed = db.loans.filter { it.closedAt != null }.sortedByDescending { it.startedAt }
  val lent = open.filter { it.lent }.sumOf { LoanMath.outstanding(it, db.loanPayments) }
  val borrowed = open.filter { !it.lent }.sumOf { LoanMath.outstanding(it, db.loanPayments) }
  PScreen("Loans", back = true, actions = { GlassIcon("plus", "Add loan") { Ui.sheet = Sheet.LoanForm(null) } }) {
    group(footer = "Still to come back to you, and still to pay back. Separate from split balances.") {
      SummaryCells("You lent" to (lent to C.income), "You borrowed" to (borrowed to C.expense))
    }
    if (db.loans.isEmpty()) item { EmptyHint("No loans", "banknote.fill", "Lent a friend ₹5,000 or borrowed for a deposit? Keep track of it here with a due date.") }
    if (open.isNotEmpty()) group("Open") { open.forEachIndexed { i, l -> if (i > 0) Divider(64.dp); LoanRow(l, db.loanPayments) } }
    if (closed.isNotEmpty()) group("Settled") { closed.forEachIndexed { i, l -> if (i > 0) Divider(64.dp); LoanRow(l, db.loanPayments) } }
  }
}

@Composable private fun LoanRow(l: Loan, payments: List<LoanPayment>) {
  val left = LoanMath.outstanding(l, payments)
  val ratio = if (l.amount > 0) (l.amount - left).toDouble() / l.amount else 0.0
  val overdue = l.closedAt == null && (l.dueAt?.let { it < LocalDate.now().ms() } ?: false)
  val tint = if (l.lent) C.income else C.expense
  Row(Modifier.fillMaxWidth().combinedClickableCompat({ Ui.push(Route.LoanDetail(l.id)) }, {}).padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
    Avatar(l.person)
    Spacer(Modifier.width(12.dp))
    Column(Modifier.weight(1f)) {
      Row(verticalAlignment = Alignment.CenterVertically) {
        Text(l.person, style = T.body, color = C.label, maxLines = 1, modifier = Modifier.weight(1f))
        Text(Money.format(left, Prefs.hideAmounts), style = T.amount(17), color = if (l.closedAt != null) C.secondary else tint)
      }
      ProgressBar(ratio, tint, Modifier.padding(vertical = 5.dp))
      val due = l.dueAt?.let { (if (overdue) " · overdue since " else " · due ") + shortDate.format(it.toDate()) } ?: ""
      Text(if (l.closedAt != null) "${if (l.lent) "Lent" else "Borrowed"} ${Money.format(l.amount, Prefs.hideAmounts)} · settled"
        else "${if (l.lent) "Lent" else "Borrowed"} ${Money.format(l.amount, Prefs.hideAmounts)}$due", style = T.caption, color = if (overdue) C.expense else C.secondary)
    }
    Icon(Sym.of("chevron.right"), null, tint = C.tertiary, modifier = Modifier.padding(start = 6.dp).size(13.dp))
  }
}

@Composable fun LoanDetailScreen(id: String) {
  val db by Store.db.collectAsState()
  val l = db.loans.firstOrNull { it.id == id } ?: run { LaunchedEffect(Unit) { Ui.pop() }; return }
  val payments = db.loanPayments.filter { it.loanId == id }.sortedByDescending { it.occurredAt }
  val left = LoanMath.outstanding(l, db.loanPayments)
  var recording by remember { mutableStateOf(false) }
  var menu by remember { mutableStateOf(false) }
  var confirmDelete by remember { mutableStateOf(false) }
  fun update(f: (Loan) -> Loan) { Store.update { d -> d.copy(loans = d.loans.map { if (it.id == id) f(it) else it }) }; Services.refreshNotifications() }
  PScreen(l.person, back = true, actions = {
    Box {
      GlassIcon("ellipsis", "More") { menu = true }
      DropdownMenu(menu, { menu = false }, modifier = Modifier.background(C.card)) {
        DropdownMenuItem({ Text("Edit", style = T.body) }, { menu = false; Ui.sheet = Sheet.LoanForm(id) })
        DropdownMenuItem({ Text("Delete", style = T.body, color = C.expense) }, { menu = false; confirmDelete = true })
      }
    }
  }) {
    group {
      Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Avatar(l.person, 56.dp)
        Text(if (l.closedAt != null) "Settled" else if (l.lent) "${l.person} still owes you" else "You still owe ${l.person}", style = T.subhead, color = C.secondary, modifier = Modifier.padding(top = 6.dp))
        Text(Money.format(left), style = T.amount(40, FontWeight.Bold), color = if (l.closedAt != null) C.label else if (l.lent) C.income else C.expense)
        Text("of ${Money.format(l.amount)} ${if (l.lent) "lent" else "borrowed"} on ${shortDate.format(l.startedAt.toDate())} ${l.startedAt.toDate().year}", style = T.footnote, color = C.secondary)
      }
      if (l.closedAt == null) {
        Divider(); PRow("Record a Repayment", titleColor = C.accent, leading = { Icon2("plus") }, onClick = { recording = true })
        Divider(56.dp); PRow("Mark as Settled", titleColor = C.accent, leading = { Icon2("checkmark.circle") }, onClick = {
          if (left > 0) Store.update { it.copy(loanPayments = it.loanPayments + LoanPayment(loanId = id, amount = left, note = "Settled")) }
          update { it.copy(closedAt = now()) }
        })
      } else { Divider(); PRow("Reopen", titleColor = C.accent, leading = { Icon2("arrow.uturn.backward") }, onClick = { update { it.copy(closedAt = null) } }) }
    }
    group(footer = if (l.dueAt != null) "A reminder on the morning it's due." else null) {
      l.dueAt?.let { PRow("Due", value = "${shortDate.format(it.toDate())} ${it.toDate().year}"); Divider() }
      ToggleRow("Remind me", l.remind != false) { v -> update { it.copy(remind = v) } }
      l.note?.let { Divider(); PRow("Note", value = it) }
    }
    if (payments.isNotEmpty()) group("Repayments") {
      payments.forEachIndexed { i, p ->
        if (i > 0) Divider()
        PRow(p.note ?: "Repayment", subtitle = shortDate.format(p.occurredAt.toDate()) + " · hold to delete",
          onLongClick = { Store.update { d -> d.copy(loanPayments = d.loanPayments.filterNot { it.id == p.id }, loans = d.loans.map { if (it.id == id) it.copy(closedAt = null) else it }) } }) {
          Text(Money.format(p.amount), style = T.amount(17), color = C.label)
        }
      }
    }
  }
  if (recording) NameDialog("Record a repayment", "Amount (${Money.format(left)} left)", keyboard = KeyboardType.Decimal, onDismiss = { recording = false }) { t ->
    Money.parse(t)?.let { p ->
      Store.update { d -> d.copy(loanPayments = d.loanPayments + LoanPayment(loanId = id, amount = p), loans = d.loans.map { if (it.id == id && p >= left) it.copy(closedAt = now()) else it }) }
      Services.refreshNotifications(); Ui.show("Recorded ${Money.format(p)}")
    }
    recording = false
  }
  if (confirmDelete) AlertDialog(onDismissRequest = { confirmDelete = false }, containerColor = C.card,
    title = { Text("Delete this loan and its repayments?", style = T.headline, color = C.label) },
    confirmButton = { TextButton({
      Store.update { d -> d.copy(loans = d.loans.filterNot { it.id == id }, loanPayments = d.loanPayments.filterNot { it.loanId == id }) }
      confirmDelete = false; Ui.pop()
    }) { Text("Delete", color = C.expense, style = T.headline) } },
    dismissButton = { TextButton({ confirmDelete = false }) { Text("Cancel", color = C.accent, style = T.body) } })
}

@Composable fun LoanFormSheet(id: String?) {
  val db = Store.value
  val e = id?.let { lid -> db.loans.firstOrNull { it.id == lid } }
  var lent by remember { mutableStateOf(e?.lent ?: true) }
  var person by remember { mutableStateOf(e?.person ?: "") }
  var amount by remember { mutableStateOf(e?.amount?.let { if (it % 100 == 0L) (it / 100).toString() else "%.2f".format(it / 100.0) } ?: "") }
  var started by remember { mutableStateOf(e?.startedAt?.toDate() ?: LocalDate.now()) }
  var due by remember { mutableStateOf(e?.dueAt?.toDate()) }
  var note by remember { mutableStateOf(e?.note ?: "") }
  var remind by remember { mutableStateOf(e?.remind != false) }
  var picking by remember { mutableStateOf<Int?>(null) }
  val valid = person.isNotBlank() && Money.parse(amount) != null
  PSheet({ Ui.sheet = null }) {
    SheetHeader(if (e == null) "New Loan" else "Edit Loan", canSave = valid, onCancel = { Ui.sheet = null }) {
      val paise = Money.parse(amount) ?: return@SheetHeader
      val name = person.trim()
      val friendId = db.friends.firstOrNull { it.name.equals(name, true) }?.id
      val loan = (e ?: Loan(person = name, amount = paise)).copy(person = name, friendId = friendId, direction = if (lent) "lent" else "borrowed", amount = paise,
        startedAt = started.atTime(12, 0).atZone(zone).toInstant().toEpochMilli(), dueAt = due?.atTime(12, 0)?.atZone(zone)?.toInstant()?.toEpochMilli(),
        note = note.trim().ifBlank { null }, remind = remind)
      Store.update { d -> d.copy(loans = if (e != null) d.loans.map { if (it.id == e.id) loan else it } else d.loans + loan) }
      Services.refreshNotifications()
      Ui.sheet = null
    }
    LazyColumn(Modifier.fillMaxWidth().padding(bottom = 24.dp)) {
      item { Segmented(listOf("I lent", "I borrowed"), if (lent) 0 else 1, Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) { lent = it == 0 } }
      group {
        FieldRow(person, { person = it }, if (lent) "Who did you lend to?" else "Who did you borrow from?")
        if (person.isBlank() && db.friends.isNotEmpty()) Row(Modifier.horizontalScroll(rememberScrollState()).padding(10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
          db.friends.take(8).forEach { f -> Text(f.name, style = T.subhead, color = C.label, modifier = Modifier.clip(CircleShape).background(C.fill).combinedClickableCompat({ person = f.name }, {}).padding(horizontal = 12.dp, vertical = 7.dp)) }
        }
        Divider(); FieldRow(amount, { amount = it }, "Amount", number = true)
        Divider(); PRow("On", value = "${shortDate.format(started)} ${started.year}", valueColor = C.accent, onClick = { picking = 0 })
      }
      group {
        ToggleRow("Due date", due != null) { due = if (it) LocalDate.now().plusMonths(1) else null }
        due?.let { d ->
          Divider(); PRow("Due", value = "${shortDate.format(d)} ${d.year}", valueColor = C.accent, onClick = { picking = 1 })
          Divider(); ToggleRow("Remind me", remind) { remind = it }
        }
      }
      group { FieldRow(note, { note = it }, "Note (optional)") }
    }
  }
  picking?.let { which ->
    DayPickerDialog(if (which == 0) started else due ?: LocalDate.now(), onDismiss = { picking = null }) { d -> if (which == 0) started = d else due = d; picking = null }
  }
}

@Composable fun CleanupScreen() {
  val ctx = androidx.compose.ui.platform.LocalContext.current
  val db by Store.db.collectAsState()
  var confirmNow by remember { mutableStateOf(false) }
  var confirmAll by remember { mutableIntStateOf(0) }
  val months = Cleanup.months(Prefs.autoCleanup, Prefs.autoCleanupMonths)
  val cutoff = months?.let { Cleanup.cutoff(it) }
  val old = cutoff?.let { c -> db.transactions.count { it.occurredAt < c } } ?: 0
  PScreen("Clean Up Data", back = true) {
    group("Auto clean-up", footer = "Transactions older than this are removed to save space. Account balances stay right: what they added up to moves into each account's starting balance. A backup is saved first.") {
      PickerRow("Keep transactions", Cleanup.options.map { it.first to it.second }, Prefs.autoCleanup) { Prefs.set("autoCleanup", it) }
      if (Prefs.autoCleanup == "custom") {
        Divider()
        PRow("Keep ${Prefs.autoCleanupMonths} months") {
          Text("−", style = T.title3, color = C.accent, modifier = Modifier.combinedClickableCompat({ if (Prefs.autoCleanupMonths > 1) Prefs.set("autoCleanupMonths", Prefs.autoCleanupMonths - 1) }, {}).padding(horizontal = 14.dp))
          Text("+", style = T.title3, color = C.accent, modifier = Modifier.combinedClickableCompat({ if (Prefs.autoCleanupMonths < 120) Prefs.set("autoCleanupMonths", Prefs.autoCleanupMonths + 1) }, {}).padding(horizontal = 14.dp))
        }
      }
    }
    if (cutoff != null) group(footer = if (Prefs.lastCleanupAt > 0) "Last clean-up ${shortDate.format(Prefs.lastCleanupAt.toDate())}." else null) {
      PRow("Older than", value = "${shortDate.format(cutoff.toDate())} ${cutoff.toDate().year}")
      Divider(); PRow("Transactions", value = "$old")
      Divider(); PRow("Clean Up Now", titleColor = if (old > 0) C.accent else C.tertiary, onClick = { if (old > 0) confirmNow = true })
    }
    group(footer = "Removes every account, transaction, budget, split and loan from this phone. A backup is saved first.") {
      PRow("Delete All Data", titleColor = C.expense, onClick = { confirmAll = 1 })
    }
  }
  if (confirmNow) AlertDialog(onDismissRequest = { confirmNow = false }, containerColor = C.card,
    title = { Text("Remove $old transactions?", style = T.headline, color = C.label) },
    text = { Text("From before ${cutoff?.let { shortDate.format(it.toDate()) }}. A backup is saved first.", style = T.body, color = C.secondary) },
    confirmButton = { TextButton({ val n = DataCleanup.run(ctx, months ?: 0); confirmNow = false; Ui.show("Removed $n old transactions") }) { Text("Back Up and Clean Up", color = C.expense, style = T.headline) } },
    dismissButton = { TextButton({ confirmNow = false }) { Text("Cancel", color = C.accent, style = T.body) } })
  if (confirmAll > 0) AlertDialog(onDismissRequest = { confirmAll = 0 }, containerColor = C.card,
    title = { Text(if (confirmAll == 1) "Delete everything?" else "Are you sure?", style = T.headline, color = C.label) },
    text = { Text(if (confirmAll == 1) "This can't be undone, except by restoring the backup." else "Paisa Pulse will start fresh.", style = T.body, color = C.secondary) },
    confirmButton = { TextButton({ if (confirmAll == 1) confirmAll = 2 else { DataCleanup.deleteAll(ctx); confirmAll = 0 } }) {
      Text(if (confirmAll == 1) "Delete All Data" else "Delete Everything", color = C.expense, style = T.headline) } },
    dismissButton = { TextButton({ confirmAll = 0 }) { Text("Cancel", color = C.accent, style = T.body) } })
}

object DataCleanup {
  /** Backs up, folds transactions older than `months` into opening balances, removes them. Returns how many live ones went. */
  fun run(ctx: android.content.Context, months: Int): Int {
    if (months <= 0) return 0
    BackupOps.write(ctx)
    val d = Store.value
    val (delta, remove) = Cleanup.plan(d.transactions, Cleanup.cutoff(months))
    if (remove.isEmpty()) return 0
    val removed = d.transactions.count { it.id in remove && it.deletedAt == null }
    Store.update { db -> db.copy(
      accounts = db.accounts.map { a -> delta[a.id]?.let { a.copy(openingBalance = a.openingBalance + it, updatedAt = now()) } ?: a },
      transactions = db.transactions.filterNot { it.id in remove }) }
    Prefs.set("lastCleanupAt", now())
    Services.refreshWidget()
    return removed
  }

  /** Auto clean-up, at most once a day (from maintenance). */
  fun runIfDue(ctx: android.content.Context) {
    val months = Cleanup.months(Prefs.autoCleanup, Prefs.autoCleanupMonths) ?: return
    if (now() - Prefs.lastCleanupAt < 86_400_000L) return
    run(ctx, months)
  }

  fun deleteAll(ctx: android.content.Context) {
    BackupOps.write(ctx)
    Store.replace(Db())
    Prefs.set("onboarded", false)
    Services.refreshWidget()
  }
}
