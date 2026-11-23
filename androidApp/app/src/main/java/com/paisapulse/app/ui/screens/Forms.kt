package com.paisapulse.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.paisapulse.app.data.*
import com.paisapulse.app.logic.*
import com.paisapulse.app.ui.*
import com.paisapulse.app.work.Services
import java.time.LocalDate

private fun rupees(p: Long?) = p?.let { if (it % 100 == 0L) (it / 100).toString() else "%.2f".format(it / 100.0) } ?: ""

@Composable private fun FormSheet(title: String, canSave: Boolean, onSave: () -> Unit, content: androidx.compose.foundation.lazy.LazyListScope.() -> Unit) {
  PSheet({ Ui.sheet = null }) {
    SheetHeader(title, canSave, onCancel = { Ui.sheet = null }, onSave = { onSave(); Ui.sheet = null })
    LazyColumn(Modifier.fillMaxHeight(0.9f).imePadding(), contentPadding = PaddingValues(bottom = 40.dp), content = content)
  }
}

@Composable fun AccountForm(id: String?, initialType: String = "bank") {
  val db = Store.value
  val a = id?.let { i -> db.accounts.firstOrNull { it.id == i } }
  var name by remember { mutableStateOf(a?.name ?: "") }
  var type by remember { mutableStateOf(a?.kind ?: AccountType.of(initialType)) }
  var inst by remember { mutableStateOf(a?.institution ?: "") }
  var last4 by remember { mutableStateOf(a?.last4 ?: "") }
  var opening by remember { mutableStateOf(rupees(a?.openingBalance?.let { kotlin.math.abs(it) }?.takeIf { it != 0L })) }
  var overdrawn by remember { mutableStateOf(a != null && a.kind != AccountType.Card && a.openingBalance < 0) }
  var limit by remember { mutableStateOf(rupees(a?.creditLimit)) }
  var sd by remember { mutableIntStateOf(a?.statementDay ?: 0) }
  var dd by remember { mutableIntStateOf(a?.dueDay ?: 0) }
  var color by remember { mutableStateOf(a?.color ?: swatches[db.accounts.size % swatches.size]) }
  var exclude by remember { mutableStateOf(a?.excludeFromTotals == true) }
  var pickingBank by remember { mutableStateOf(false) }
  if (pickingBank) BankPickerDialog(type == AccountType.Wallet, inst, { pickingBank = false }) { picked, bank ->
    pickingBank = false; inst = picked
    bank?.let { color = it.color; if (name.isBlank()) name = it.short }
  }
  FormSheet(if (a == null) "New Account" else "Edit Account", name.isNotBlank(), onSave = {
    val p = Money.parse(opening) ?: 0
    val signed = if (type == AccountType.Card) -p else if (overdrawn) -p else p
    val d4 = last4.filter { it.isDigit() }.takeLast(4)
    val acc = (a ?: Account(name = name, sortOrder = db.accounts.size)).copy(name = name.trim(), type = type.key, institution = inst.ifBlank { null },
      last4 = d4.takeIf { it.length == 4 }, openingBalance = signed, creditLimit = if (type == AccountType.Card) Money.parse(limit) else null,
      statementDay = if (type == AccountType.Card && sd > 0) sd else null, dueDay = if (type == AccountType.Card && dd > 0) dd else null,
      color = color, icon = type.icon, excludeFromTotals = exclude, updatedAt = now())
    Store.update { d -> d.copy(accounts = if (a == null) d.accounts + acc else d.accounts.map { if (it.id == acc.id) acc else it },
      cards = if (a == null && type == AccountType.Card && acc.last4 != null) d.cards + PaymentCard(accountId = acc.id, kind = "credit", last4 = acc.last4, color = acc.color) else d.cards) }
    Services.refreshNotifications()
  }) {
    group {
      FieldRow(name, { name = it }, "Name, e.g. Axis Salary")
      Divider(); PickerRow("Type", AccountType.entries.map { it to it.label }, type) { type = it }
      if (type == AccountType.Bank || type == AccountType.Card || type == AccountType.Wallet) {
        Divider(); PRow(if (type == AccountType.Wallet) "Wallet" else "Bank", value = inst.ifBlank { "Choose" }, valueColor = if (inst.isBlank()) C.secondary else C.label,
          leading = Banks.match(inst)?.let { b -> @Composable { CategoryBadge("building.columns.fill", b.color, 26.dp) } }, chevron = true, onClick = { pickingBank = true })
      } else { Divider(); FieldRow(inst, { inst = it }, "Institution (optional)") }
      if (type == AccountType.Bank || type == AccountType.Card) { Divider(); FieldRow(last4, { last4 = it }, "Last 4 digits (optional)", number = true) }
    }
    group(footer = if (a == null) "Your balance today. Transactions you add change it from here." else "Balance before your first transaction.") {
      FieldRow(opening, { opening = it }, if (type == AccountType.Card) "Amount owed now" else "Current balance", number = true)
      if (type != AccountType.Card) { Divider(); ToggleRow("Overdrawn (negative)", overdrawn) { overdrawn = it } }
    }
    if (type == AccountType.Card) group("Card") {
      FieldRow(limit, { limit = it }, "Credit limit", number = true)
      Divider(); PickerRow("Statement day", listOf(0 to "Not set") + (1..28).map { it to "$it" }, sd) { sd = it }
      Divider(); PickerRow("Bill due day", listOf(0 to "Not set") + (1..31).map { it to "$it" }, dd) { dd = it }
    }
    group("Colour") { ColorRow(color) { color = it }; Divider(); ToggleRow("Leave out of net worth", exclude) { exclude = it } }
  }
}

val categoryIcons = listOf("fork.knife", "cart.fill", "car.fill", "fuelpump.fill", "tram.fill", "bag.fill", "doc.text.fill", "bolt.fill",
  "wifi", "tv.fill", "house.fill", "building.columns.fill", "cross.case.fill", "popcorn.fill", "repeat.circle.fill", "airplane",
  "graduationcap.fill", "gift.fill", "chart.line.uptrend.xyaxis", "sparkles", "pawprint.fill", "figure.2.and.child.holdinghands",
  "gamecontroller.fill", "dumbbell.fill", "cup.and.saucer.fill", "wineglass.fill", "tshirt.fill", "iphone", "wrench.and.screwdriver.fill",
  "book.fill", "music.note", "heart.fill", "leaf.fill", "scooter", "bicycle", "bus.fill", "banknote.fill", "laptopcomputer", "percent",
  "indianrupeesign.circle.fill", "tag.fill", "star.fill")

@Composable fun IconGrid(selected: String, color: String, icons: List<String> = categoryIcons, onPick: (String) -> Unit) {
  Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
    icons.chunked(6).forEach { row ->
      Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        row.forEach { ic ->
          Box(Modifier.size(42.dp).clip(RoundedCornerShape(10.dp)).background(if (ic == selected) hex(color) else C.fill).clickable { onPick(ic) }, contentAlignment = Alignment.Center) {
            Icon(Sym.of(ic), null, tint = if (ic == selected) Color.White else C.label)
          }
        }
      }
    }
  }
}

@Composable fun CategoryForm(id: String?, income: Boolean) {
  val db = Store.value
  val c = id?.let { i -> db.categories.firstOrNull { it.id == i } }
  val kind = c?.kind ?: if (income) "income" else "expense"
  var name by remember { mutableStateOf(c?.name ?: "") }
  var icon by remember { mutableStateOf(c?.icon ?: "tag.fill") }
  var color by remember { mutableStateOf(c?.color ?: "#5E5CE6") }
  var parent by remember { mutableStateOf(c?.parentId ?: "") }
  FormSheet(if (c == null) "New Category" else "Edit Category", name.isNotBlank(), onSave = {
    val cat = (c ?: Category(kind = kind, name = name, sortOrder = db.categories.size)).copy(name = name.trim(), icon = icon, color = color, parentId = parent.ifEmpty { null }, updatedAt = now())
    Store.update { d -> d.copy(categories = if (c == null) d.categories + cat else d.categories.map { if (it.id == cat.id) cat else it }) }
  }) {
    group {
      Row(Modifier.padding(start = 16.dp), verticalAlignment = Alignment.CenterVertically) { CategoryBadge(icon, color, 44.dp); FieldRow(name, { name = it }, "Name") }
      Divider(); PickerRow("Inside", listOf("" to "None (main category)") + db.categories.filter { it.kind == kind && it.parentId == null && it.id != c?.id }.map { it.id to it.name }, parent) { parent = it }
    }
    group("Colour") { ColorRow(color) { color = it } }
    group("Icon") { IconGrid(icon, color) { icon = it } }
    if (c != null) group(footer = "Hidden categories keep their past transactions.") {
      PRow(if (c.archivedAt == null) "Hide Category" else "Show Category", titleColor = C.accent, onClick = {
        Store.update { d -> d.copy(categories = d.categories.map { if (it.id == c.id) it.copy(archivedAt = if (c.archivedAt == null) now() else null) else it }) }; Ui.sheet = null })
    }
  }
}

@Composable fun BudgetForm(id: String?) {
  val db = Store.value
  val b = id?.let { i -> db.budgets.firstOrNull { it.id == i } }
  var cat by remember { mutableStateOf(b?.categoryId ?: "") }
  var weekly by remember { mutableStateOf(b?.period == "weekly") }
  var amount by remember { mutableStateOf(rupees(b?.amount)) }
  FormSheet(if (b == null) "New Budget" else "Edit Budget", Money.parse(amount) != null, onSave = {
    val p = Money.parse(amount) ?: return@FormSheet
    val nb = (b ?: Budget(amount = p)).copy(categoryId = cat.ifEmpty { null }, period = if (weekly) "weekly" else "monthly", amount = p, updatedAt = now())
    Store.update { d -> d.copy(budgets = if (b == null) d.budgets + nb else d.budgets.map { if (it.id == nb.id) nb else it }) }
  }) {
    group {
      PickerRow("For", listOf("" to "Everything") + db.categories.filter { it.kind == "expense" && it.parentId == null && it.archivedAt == null }.map { it.id to it.name }, cat) { cat = it }
      Divider(); Box(Modifier.padding(12.dp)) { Segmented(listOf("Month", "Week"), if (weekly) 1 else 0) { weekly = it == 1 } }
      Divider(); FieldRow(amount, { amount = it }, "Limit, e.g. 20000", number = true)
    }
    if (b != null) group { PRow("Delete Budget", titleColor = C.expense, onClick = { Store.update { d -> d.copy(budgets = d.budgets.filterNot { it.id == b.id }) }; Ui.sheet = null }) }
  }
}

@Composable fun RecurringForm(id: String?, fromTxn: String?) {
  val db = Store.value
  val r = id?.let { i -> db.recurringRules.firstOrNull { it.id == i } }
  val t = fromTxn?.let { i -> db.transactions.firstOrNull { it.id == i } }
  var type by remember { mutableStateOf(TxnType.of(r?.type ?: t?.type)) }
  var amount by remember { mutableStateOf(rupees(r?.amount ?: t?.amount)) }
  var payee by remember { mutableStateOf(r?.payee ?: t?.payee ?: "") }
  val accounts = db.accounts.filter { it.archivedAt == null }
  var acc by remember { mutableStateOf(r?.accountId ?: t?.accountId ?: accounts.firstOrNull()?.id ?: "") }
  var to by remember { mutableStateOf(r?.toAccountId ?: t?.toAccountId ?: "") }
  var cat by remember { mutableStateOf(r?.categoryId ?: t?.categoryId ?: "") }
  var freq by remember { mutableStateOf(r?.freq ?: Frequency.Monthly) }
  var interval by remember { mutableIntStateOf(r?.interval ?: 1) }
  val startDefault = r?.startAt ?: t?.let { it.occurredAt.toDate().plusMonths(1).ms() } ?: LocalDate.now().ms()
  var start by remember { mutableLongStateOf(startDefault) }
  FormSheet(if (r == null) "Repeat" else "Edit Recurring", Money.parse(amount) != null && acc.isNotEmpty(), onSave = {
    val p = Money.parse(amount) ?: return@FormSheet
    var rule = (r ?: RecurringRule(amount = p, accountId = acc, startAt = start, nextAt = start)).copy(type = type.key, amount = p, accountId = acc,
      toAccountId = if (type == TxnType.Transfer) to.ifEmpty { null } else null, categoryId = if (type == TxnType.Transfer) null else cat.ifEmpty { null },
      payee = payee.ifBlank { null }, frequency = freq.key, interval = interval, updatedAt = now())
    if (r == null || r.startAt != start) rule = rule.copy(startAt = start, nextAt = start)
    if (t != null && rule.nextAt <= t.occurredAt) rule = rule.copy(nextAt = Recurrence.next(t.occurredAt, rule))
    Store.update { d -> d.copy(recurringRules = if (r == null) d.recurringRules + rule else d.recurringRules.map { if (it.id == rule.id) rule else it },
      transactions = if (t != null) d.transactions.map { if (it.id == t.id) it.copy(recurringId = rule.id) else it } else d.transactions) }
    Services.runMaintenance()
  }) {
    group {
      Box(Modifier.padding(12.dp)) { Segmented(TxnType.entries.map { it.label }, TxnType.entries.indexOf(type)) { type = TxnType.entries[it] } }
      Divider(); FieldRow(amount, { amount = it }, "Amount", number = true)
      Divider(); FieldRow(payee, { payee = it }, "Payee, e.g. Rent")
      Divider(); PickerRow(if (type == TxnType.Transfer) "From" else "Account", accounts.map { it.id to it.displayName }, acc) { acc = it }
      Divider()
      if (type == TxnType.Transfer) PickerRow("To", listOf("" to "Choose") + accounts.filter { it.id != acc }.map { it.id to it.displayName }, to) { to = it }
      else PickerRow("Category", listOf("" to "Uncategorised") + db.categories.filter { it.kind == (if (type == TxnType.Income) "income" else "expense") }.map { it.id to it.name }, cat) { cat = it }
    }
    group("Repeats") {
      PickerRow("Every", Frequency.entries.map { it to it.noun.replaceFirstChar { c -> c.uppercase() } }, freq) { freq = it }
      Divider(); PickerRow("Interval", (1..12).map { it to "Every $it ${freq.noun}${if (it > 1) "s" else ""}" }, interval) { interval = it }
      Divider(); PickerRow("Starts", (-1..60).map { LocalDate.now().plusDays(it.toLong()).ms() }.let { days -> (listOf(start) + days).distinct().map { it to shortDate.format(it.toDate()) + " " + it.toDate().year } }, start) { start = it }
    }
    if (r != null) group {
      PRow(if (r.pausedAt == null) "Pause" else "Resume", titleColor = C.accent, onClick = {
        Store.update { d -> d.copy(recurringRules = d.recurringRules.map { if (it.id == r.id) it.copy(pausedAt = if (r.pausedAt == null) now() else null) else it }) }; Ui.sheet = null })
      Divider(); PRow("Delete", titleColor = C.expense, onClick = { Store.update { d -> d.copy(recurringRules = d.recurringRules.filterNot { it.id == r.id }) }; Ui.sheet = null })
    }
  }
}

@Composable fun GoalForm(id: String?) {
  val db = Store.value
  val g = id?.let { i -> db.goals.firstOrNull { it.id == i } }
  var name by remember { mutableStateOf(g?.name ?: "") }
  var target by remember { mutableStateOf(rupees(g?.target)) }
  var saved by remember { mutableStateOf("") }
  var add by remember { mutableStateOf("") }
  var months by remember { mutableIntStateOf(g?.deadline?.let { java.time.temporal.ChronoUnit.MONTHS.between(LocalDate.now(), it.toDate()).toInt().coerceAtLeast(0) } ?: 0) }
  var color by remember { mutableStateOf(g?.color ?: "#5E5CE6") }
  var icon by remember { mutableStateOf(g?.icon ?: "star.fill") }
  FormSheet(if (g == null) "New Goal" else g.name, name.isNotBlank() && Money.parse(target) != null, onSave = {
    val tp = Money.parse(target) ?: return@FormSheet
    val ng = (g ?: Goal(name = name, target = tp, saved = Money.parse(saved) ?: 0)).copy(name = name.trim(), target = tp, color = color, icon = icon,
      deadline = if (months > 0) LocalDate.now().plusMonths(months.toLong()).ms() else null)
    Store.update { d -> d.copy(goals = if (g == null) d.goals + ng else d.goals.map { if (it.id == ng.id) ng.copy(saved = it.saved) else it }) }
  }) {
    group {
      Row(Modifier.padding(start = 16.dp), verticalAlignment = Alignment.CenterVertically) { CategoryBadge(icon, color, 40.dp); FieldRow(name, { name = it }, "Goal, e.g. Germany trip") }
      Divider(); FieldRow(target, { target = it }, "Target amount", number = true)
      if (g == null) { Divider(); FieldRow(saved, { saved = it }, "Already saved (optional)", number = true) }
      Divider(); PickerRow("By", listOf(0 to "No date") + listOf(1, 2, 3, 6, 9, 12, 18, 24, 36).map { it to "in $it months" }, months) { months = it }
    }
    if (g != null) group("Add money") {
      PRow("Saved so far", value = Money.format(g.saved))
      Divider(); FieldRow(add, { add = it }, "Amount to add or take out", number = true)
      Divider()
      Row(Modifier.padding(12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Button({ Money.parse(add)?.let { p -> Store.update { d -> d.copy(goals = d.goals.map { if (it.id == g.id) it.copy(saved = it.saved + p) else it }) }; add = "" } },
          colors = ButtonDefaults.buttonColors(containerColor = C.accent)) { Text("Add", style = T.headline) }
        OutlinedButton({ Money.parse(add)?.let { p -> Store.update { d -> d.copy(goals = d.goals.map { if (it.id == g.id) it.copy(saved = maxOf(0, it.saved - p)) else it }) }; add = "" } }) { Text("Take out", style = T.headline, color = C.accent) }
      }
    }
    group("Look") { ColorRow(color) { color = it }; Divider(); IconGrid(icon, color, listOf("star.fill", "airplane", "iphone", "car.fill", "house.fill", "graduationcap.fill", "heart.fill", "gift.fill", "shield.fill", "laptopcomputer", "camera.fill", "bicycle")) { icon = it } }
    if (g != null) group { PRow("Delete Goal", titleColor = C.expense, onClick = { Store.update { d -> d.copy(goals = d.goals.filterNot { it.id == g.id }) }; Ui.sheet = null }) }
  }
}
