package com.paisapulse.app.ui.screens

import androidx.compose.animation.AnimatedContent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.paisapulse.app.data.*
import com.paisapulse.app.logic.*
import com.paisapulse.app.ui.*
import com.paisapulse.app.work.Services
import java.time.Instant
import java.time.LocalTime

@OptIn(ExperimentalMaterial3Api::class)
@Composable fun QuickAddSheet(req: Sheet.Add) {
  val db = Store.value
  val editing = req.editId?.let { id -> db.transactions.firstOrNull { it.id == id } }
  var type by remember { mutableStateOf(editing?.kind ?: req.type) }
  var expr by remember { mutableStateOf(editing?.let { if (it.amount % 100 == 0L) (it.amount / 100).toString() else "%.2f".format(it.amount / 100.0) } ?: "0") }
  var payee by remember { mutableStateOf(editing?.payee ?: "") }
  var categoryId by remember { mutableStateOf(editing?.categoryId) }
  val accounts = db.accounts.filter { it.archivedAt == null }.sortedBy { it.sortOrder }
  var accountId by remember { mutableStateOf(editing?.accountId ?: req.accountId ?: accounts.firstOrNull { it.id == Prefs.lastAccountId }?.id ?: accounts.firstOrNull()?.id) }
  var toAccountId by remember { mutableStateOf(editing?.toAccountId) }
  var at by remember { mutableLongStateOf(editing?.occurredAt ?: req.date ?: now()) }
  var splitWith by remember { mutableStateOf(editing?.let { e -> db.splitEntries.filter { it.txnId == e.id }.map { it.friendId }.toSet() } ?: emptySet()) }
  var pickCategory by remember { mutableStateOf(false) }
  var pickSplit by remember { mutableStateOf(false) }
  var pickDate by remember { mutableStateOf(false) }
  var error by remember { mutableStateOf<String?>(null) }
  val amount = KeypadMath.evaluate(expr)?.let { Money.paise(it) }
  val kindCats = db.categories.filter { it.archivedAt == null && it.parentId == null && it.kind == (if (type == TxnType.Income) "income" else "expense") }.sortedBy { it.sortOrder }

  fun save() {
    val amt = amount ?: return run { error = "Enter an amount." }
    val acc = accountId ?: return run { error = "Add an account first (Accounts tab)." }
    if (type == TxnType.Transfer && (toAccountId == null || toAccountId == acc)) { error = "Pick a different account to move money to."; return }
    val name = payee.trim().ifEmpty { null }
    val shares = if (type == TxnType.Expense && splitWith.isNotEmpty()) Splits.equalShares(amt, splitWith.size) else null
    val txn = (editing ?: Txn(amount = amt, accountId = acc)).copy(type = type.key, amount = amt, accountId = acc,
      toAccountId = if (type == TxnType.Transfer) toAccountId else null, categoryId = if (type == TxnType.Transfer) null else categoryId,
      payee = name, occurredAt = at, updatedAt = now(), splitShare = shares?.first)
    Store.update { d ->
      val txns = if (editing != null) d.transactions.map { if (it.id == txn.id) txn else it } else d.transactions + txn
      val entries = d.splitEntries.filterNot { it.txnId == txn.id } + (shares?.let { s -> splitWith.map { SplitEntry(friendId = it, txnId = txn.id, amount = s.second, note = name, occurredAt = at) } } ?: emptyList())
      d.copy(transactions = txns, splitEntries = entries)
    }
    Prefs.set("lastAccountId", acc)
    Services.refreshWidget(); Services.checkBudgets()
    Ui.sheet = null
    if (editing != null) Ui.show("Saved") else Ui.show("Added ${Money.format(amt)}") {
      Store.update { d -> d.copy(transactions = d.transactions.map { if (it.id == txn.id) it.copy(deletedAt = now()) else it }) }
    }
  }

  PSheet({ Ui.sheet = null }) {
    Column(Modifier.fillMaxHeight(0.94f)) {
      SheetHeader(if (editing == null) "New ${type.label}" else "Edit ${type.label}", canSave = (amount ?: 0) > 0, onCancel = { Ui.sheet = null }, onSave = ::save)
      Segmented(TxnType.entries.map { it.label }, TxnType.entries.indexOf(type), Modifier.padding(horizontal = 16.dp)) { type = TxnType.entries[it]
        if (categoryId != null && db.categories.firstOrNull { c -> c.id == categoryId }?.kind != (if (type == TxnType.Income) "income" else "expense")) categoryId = null }
      // Amount
      Column(Modifier.fillMaxWidth().padding(vertical = 14.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Row(verticalAlignment = Alignment.Bottom) {
          Text("₹", style = T.amount(30), color = C.secondary, modifier = Modifier.padding(bottom = 8.dp, end = 4.dp))
          AnimatedContent(expr, label = "amt") { e -> Text(e, style = T.amount(56, FontWeight.Bold), color = type.color(C), maxLines = 1) }
        }
        if (KeypadMath.isExpression(expr) && amount != null) Text("= ${Money.format(amount)}", style = T.subhead, color = C.secondary)
      }
      LazyColumn(Modifier.weight(1f)) {
        group {
          FieldRow(payee, { payee = it }, if (type == TxnType.Transfer) "Note (optional)" else "Payee, e.g. Swiggy")
          if (type != TxnType.Transfer) {
            Divider()
            Row(Modifier.horizontalScroll(rememberScrollState()).padding(10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
              categoryId?.let { id -> db.categories.firstOrNull { it.id == id && it.parentId != null } }?.let { Chip(it, true) { categoryId = null } }
              kindCats.forEach { c -> Chip(c, categoryId == c.id) { categoryId = if (categoryId == c.id) null else c.id } }
              Row(Modifier.clip(CircleShape).background(C.fill).clickable { pickCategory = true }.padding(horizontal = 12.dp, vertical = 7.dp)) {
                Text("••• More", style = T.subhead, color = C.label)
              }
            }
          }
        }
        group {
          PickerRow(if (type == TxnType.Transfer) "From" else "Account", accounts.map { it.id to it.displayName }, accountId ?: "") { accountId = it }
          if (type == TxnType.Transfer) { Divider(); PickerRow("To", listOf("" to "Choose") + accounts.filter { it.id != accountId }.map { it.id to it.displayName }, toAccountId ?: "") { toAccountId = it.ifEmpty { null } } }
          Divider()
          PRow("Date", onClick = { pickDate = true }) {
            Text(shortDate.format(at.toDate()) + " " + at.toDate().year + ", " + at.time(), style = T.body, color = C.label,
              modifier = Modifier.clip(RoundedCornerShape(8.dp)).background(C.fill).padding(horizontal = 10.dp, vertical = 5.dp))
          }
          if (type == TxnType.Expense && db.friends.isNotEmpty()) {
            Divider()
            PRow("Split", value = if (splitWith.isEmpty()) "No" else amount?.let { "${splitWith.size + 1} people · yours ${Money.format(Splits.equalShares(it, splitWith.size).first)}" } ?: "${splitWith.size + 1} people",
              chevron = true, onClick = { pickSplit = true })
          }
        }
      }
      Keypad(expr) { expr = it }
    }
  }

  if (pickCategory) CategoryPickerDialog(if (type == TxnType.Income) "income" else "expense", categoryId, { categoryId = it; pickCategory = false }) { pickCategory = false }
  if (pickSplit) AlertDialog({ pickSplit = false }, confirmButton = { TextButton({ pickSplit = false }) { Text("Done") } }, containerColor = C.card,
    title = { Text("Split with", style = T.headline) }, text = {
      Column {
        Store.value.friends.sortedBy { it.name }.forEach { f ->
          val on = f.id in splitWith
          PRow(f.name, leading = { Icon(Sym.of(if (on) "checkmark.circle.fill" else "circle"), null, tint = if (on) C.accent else C.secondary) },
            onClick = { splitWith = if (on) splitWith - f.id else splitWith + f.id })
        }
        Text("Split equally between you and the people you pick. They'll owe you their share; settle up in Splits.", style = T.footnote, color = C.secondary)
      }
    })
  if (pickDate) {
    val st = rememberDatePickerState(initialSelectedDateMillis = at + java.util.TimeZone.getDefault().getOffset(at))
    DatePickerDialog({ pickDate = false }, confirmButton = { TextButton({
      st.selectedDateMillis?.let { utc ->
        val d = Instant.ofEpochMilli(utc).atZone(java.time.ZoneOffset.UTC).toLocalDate()
        val t = Instant.ofEpochMilli(at).atZone(zone).toLocalTime()
        at = d.atTime(t).atZone(zone).toInstant().toEpochMilli()
      }; pickDate = false }) { Text("OK") } }) { DatePicker(st) }
  }
  error?.let { e -> AlertDialog({ error = null }, confirmButton = { TextButton({ error = null }) { Text("OK") } }, title = { Text("Can't save") }, text = { Text(e) }) }
}

@Composable private fun Chip(c: Category, selected: Boolean, onClick: () -> Unit) {
  Row(Modifier.clip(CircleShape).background(if (selected) hex(c.color) else C.fill).clickable(onClick = onClick).padding(horizontal = 12.dp, vertical = 7.dp),
    verticalAlignment = Alignment.CenterVertically) {
    Icon(Sym.of(c.icon), null, tint = if (selected) Color.White else C.label, modifier = Modifier.size(15.dp))
    Spacer(Modifier.width(6.dp))
    Text(c.name, style = T.subhead, color = if (selected) Color.White else C.label, maxLines = 1)
  }
}

/** 4×3 keypad with a + − × ÷ strip, like iOS. */
@Composable fun Keypad(expr: String, onChange: (String) -> Unit) {
  val haptics = LocalHapticFeedback.current
  val ops = "+−×÷"
  fun append(k: String) {
    haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
    if (k == "⌫") { onChange(if (expr.length <= 1) "0" else expr.dropLast(1)); return }
    if (k in listOf("+", "−", "×", "÷")) {
      var e = expr; if (e.last() in ops) e = e.dropLast(1); if (e == "0") return; onChange(e + k); return
    }
    val endsOp = expr.last() in ops
    val number = if (endsOp) "" else expr.split(*ops.map { it.toString() }.toTypedArray()).last()
    if (k == ".") { if ("." in number) return; onChange(expr + if (number.isEmpty()) "0." else "."); return }
    val dot = number.indexOf('.'); if (dot >= 0 && number.length - dot > 2) return
    if (number.length >= 9) return
    onChange(if (expr == "0") k else expr + k)
  }
  Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 12.dp).navigationBarsPadding(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
      listOf("+", "−", "×", "÷").forEach { k ->
        Box(Modifier.weight(1f).height(36.dp).clip(RoundedCornerShape(14.dp)).background(C.accent.copy(alpha = 0.12f)).clickable { append(k) }, contentAlignment = Alignment.Center) {
          Text(k, style = T.amount(20), color = C.accent)
        }
      }
    }
    listOf(listOf("1", "2", "3"), listOf("4", "5", "6"), listOf("7", "8", "9"), listOf(".", "0", "⌫")).forEach { row ->
      Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        row.forEach { k ->
          Box(Modifier.weight(1f).height(52.dp).clip(RoundedCornerShape(14.dp)).background(C.card).clickable { append(k) }, contentAlignment = Alignment.Center) {
            if (k == "⌫") Icon(Sym.of("delete.left"), "Delete", tint = C.label) else Text(k, style = T.amount(26, FontWeight.Normal), color = C.label)
          }
        }
      }
    }
  }
}

@Composable fun CategoryPickerDialog(kind: String, selected: String?, onPick: (String?) -> Unit, onDismiss: () -> Unit) {
  val cats = Store.value.categories.filter { it.archivedAt == null && it.kind == kind }.sortedBy { it.sortOrder }
  AlertDialog(onDismiss, confirmButton = { TextButton(onDismiss) { Text("Cancel") } }, containerColor = C.card, title = { Text("Category", style = T.headline) }, text = {
    LazyColumn(Modifier.heightIn(max = 480.dp)) {
      item { PRow("Uncategorised", leading = { CategoryBadge("questionmark", "#8E8E93", 30.dp) }, onClick = { onPick(null) }) }
      cats.filter { it.parentId == null }.forEach { p ->
        item { PRow(p.name, leading = { CategoryBadge(p.icon, p.color, 30.dp) }, onClick = { onPick(p.id) }) { if (selected == p.id) Icon(Sym.of("checkmark"), null, tint = C.accent) } }
        cats.filter { it.parentId == p.id }.forEach { c ->
          item { PRow(c.name, modifier = Modifier.padding(start = 24.dp), leading = { CategoryBadge(c.icon, c.color, 26.dp) }, onClick = { onPick(c.id) }) { if (selected == c.id) Icon(Sym.of("checkmark"), null, tint = C.accent) } }
        }
      }
    }
  })
}
