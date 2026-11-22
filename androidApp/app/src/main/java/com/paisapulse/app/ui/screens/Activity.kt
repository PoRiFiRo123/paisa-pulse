package com.paisapulse.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.paisapulse.app.data.*
import com.paisapulse.app.logic.*
import com.paisapulse.app.ui.*

object Search {
  fun matches(t: Txn, q: String, l: Lookups): Boolean {
    val s = q.trim().lowercase(); if (s.isEmpty()) return true
    if (Money.parse(s)?.let { it == t.amount } == true) return true
    return listOf(t.payee, t.note, t.categoryId?.let { l.categories[it]?.name }, l.accounts[t.accountId]?.name).any { it?.lowercase()?.contains(s) == true }
  }
}

@Composable fun SearchField(q: String, onChange: (String) -> Unit, hint: String) {
  Row(Modifier.padding(horizontal = 16.dp, vertical = 4.dp).fillMaxWidth().height(44.dp).clip(CircleShape).background(C.fill).padding(horizontal = 14.dp),
    verticalAlignment = Alignment.CenterVertically) {
    Icon(Sym.of("magnifyingglass"), null, tint = C.secondary, modifier = Modifier.size(20.dp))
    Spacer(Modifier.width(8.dp))
    FieldRow(q, onChange, hint, modifier = Modifier.padding(0.dp))
  }
}

@Composable fun ActivityScreen() {
  val db by Store.db.collectAsState()
  val l = remember(db) { Lookups(db) }
  var offset by remember { mutableIntStateOf(0) }
  var q by remember { mutableStateOf("") }
  var type by remember { mutableStateOf<TxnType?>(null) }
  var accountId by remember { mutableStateOf<String?>(null) }
  var categoryId by remember { mutableStateOf<String?>(null) }
  var filters by remember { mutableStateOf(false) }
  val range = Periods.month(offset, Prefs.monthStartDay)
  val rows = db.liveTxns.filter { t ->
    t.occurredAt in range && (type == null || t.kind == type) && (accountId == null || t.accountId == accountId || t.toAccountId == accountId) &&
      (categoryId == null || t.categoryId == categoryId || Ledger.topLevel(t.categoryId, l.categories) == categoryId) && Search.matches(t, q, l)
  }.sortedByDescending { it.occurredAt }
  val days = rows.groupBy { it.occurredAt.toDate() }.toSortedMap(compareByDescending { it })
  val s = Ledger.summary(rows, range)

  PScreen("Activity", leading = {
    Row(Modifier.height(44.dp).glass(CircleShape).padding(horizontal = 6.dp), verticalAlignment = Alignment.CenterVertically) {
      IconButton({ offset-- }) { Icon(Sym.of("chevron.left"), "Previous month", tint = C.accent, modifier = Modifier.size(16.dp)) }
      Text(Periods.label(range, Prefs.monthStartDay), style = T.subhead.copy(fontWeight = FontWeight.SemiBold), color = C.label)
      IconButton({ if (offset < 0) offset++ }, enabled = offset < 0) { Icon(Sym.of("chevron.right"), "Next month", tint = if (offset < 0) C.accent else C.tertiary, modifier = Modifier.size(16.dp)) }
    }
  }, actions = {
    Box {
      GlassIcon("line.3.horizontal.decrease", "Filters", tint = if (type != null || accountId != null || categoryId != null) C.expense else C.accent) { filters = true }
      DropdownMenu(filters, { filters = false }, modifier = Modifier.background(C.card)) {
        Text("Type", style = T.footnote, color = C.secondary, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
        (listOf<TxnType?>(null) + TxnType.entries).forEach { v ->
          DropdownMenuItem({ Text(v?.label ?: "All types", style = T.body) }, { type = v }, trailingIcon = { if (type == v) Icon(Sym.of("checkmark"), null, tint = C.accent) })
        }
        HorizontalDivider(color = C.separator)
        Text("Account", style = T.footnote, color = C.secondary, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
        (listOf<Account?>(null) + db.accounts.filter { it.archivedAt == null }).forEach { a ->
          DropdownMenuItem({ Text(a?.name ?: "All accounts", style = T.body) }, { accountId = a?.id }, trailingIcon = { if (accountId == a?.id) Icon(Sym.of("checkmark"), null, tint = C.accent) })
        }
        HorizontalDivider(color = C.separator)
        Text("Category", style = T.footnote, color = C.secondary, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
        (listOf<Category?>(null) + db.categories.filter { it.parentId == null && it.archivedAt == null }).forEach { c ->
          DropdownMenuItem({ Text(c?.name ?: "All categories", style = T.body) }, { categoryId = c?.id }, trailingIcon = { if (categoryId == c?.id) Icon(Sym.of("checkmark"), null, tint = C.accent) })
        }
      }
    }
    AddButton()
  }) {
    item { SearchField(q, { q = it }, "Payee, note, category, amount") }
    group { SummaryCells("Spent" to (s.spent to C.expense), "Income" to (s.income to C.income)) }
    if (rows.isEmpty()) item { EmptyHint(if (q.isEmpty()) "Nothing here" else "No results", if (q.isEmpty()) "tray" else "magnifyingglass",
      if (q.isEmpty()) "No transactions in ${Periods.label(range, Prefs.monthStartDay)} with these filters." else "Try a payee, note, category or amount.") }
    days.forEach { (day, items) ->
      val total = items.filter { it.kind == TxnType.Expense }.sumOf { it.effectiveAmount }
      group(dayLabel(day), trailing = { if (total > 0) Text(Money.format(total, Prefs.hideAmounts), style = T.amount(17), color = C.expense) }) {
        items.forEachIndexed { i, t -> if (i > 0) Divider(64.dp); TxnRow(t, l) }
      }
    }
  }
}

@Composable fun SearchScreen() {
  val db by Store.db.collectAsState()
  val l = remember(db) { Lookups(db) }
  var q by remember { mutableStateOf("") }
  val results = if (q.isBlank()) emptyList() else db.liveTxns.filter { Search.matches(it, q, l) }.sortedByDescending { it.occurredAt }.take(200)
  PScreen("Search") {
    item { SearchField(q, { q = it }, "Search everything") }
    when {
      q.isBlank() -> item { EmptyHint("Search everything", "magnifyingglass", "Swiggy, rent, 499, a note… across every month.") }
      results.isEmpty() -> item { EmptyHint("No results for \"$q\"", "magnifyingglass", "Check the spelling or try a new search.") }
      else -> group("${results.size} results · ${Money.format(results.filter { it.kind == TxnType.Expense }.sumOf { it.effectiveAmount })} spent") {
        results.forEachIndexed { i, t -> if (i > 0) Divider(64.dp); TxnRow(t, l, showTime = false) }
      }
    }
  }
}

@Composable fun TxnDetailScreen(id: String) {
  val db by Store.db.collectAsState()
  val t = db.transactions.firstOrNull { it.id == id } ?: run { LaunchedEffect(Unit) { Ui.pop() }; return }
  val l = remember(db) { Lookups(db) }
  val (icon, color) = l.badge(t)
  val splits = db.splitEntries.filter { it.txnId == t.id }
  PScreen("", large = false, back = true, actions = {
    Text("Edit", style = T.body, color = C.accent, modifier = Modifier.glass(CircleShape).padding(horizontal = 16.dp, vertical = 11.dp)
      .then(Modifier.combinedClickableCompat({ Ui.sheet = Sheet.Add(t.kind, editId = t.id) }, {})))
  }) {
    item {
      Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        CategoryBadge(icon, color, 64.dp)
        Text(l.title(t), style = T.title3, color = C.label, modifier = Modifier.padding(top = 10.dp))
        AmountText(t.amount, t.kind, T.amount(44, FontWeight.Bold))
        Text(java.time.Instant.ofEpochMilli(t.occurredAt).atZone(zone).format(java.time.format.DateTimeFormatter.ofPattern("EEEE, d MMMM yyyy 'at' h:mm a", java.util.Locale.ENGLISH)),
          style = T.subhead, color = C.secondary)
      }
    }
    group {
      PRow("Type", value = t.kind.label)
      if (t.kind == TxnType.Transfer) {
        Divider(); PRow("From", value = l.accounts[t.accountId]?.displayName ?: "—")
        Divider(); PRow("To", value = t.toAccountId?.let { l.accounts[it]?.displayName } ?: "—")
      } else {
        Divider(); PRow("Category", value = t.categoryId?.let { l.categories[it]?.name } ?: "Uncategorised")
        Divider(); PRow("Account", value = l.accounts[t.accountId]?.displayName ?: "—")
      }
      t.note?.takeIf { it.isNotBlank() }?.let { Divider(); PRow("Note", value = it) }
      if (t.source != null && t.source != "manual") { Divider(); PRow("Added by", value = t.source.replaceFirstChar { it.uppercase() }) }
    }
    t.splitShare?.let { share ->
      group("Split") {
        PRow("Your share", value = Money.format(share))
        splits.forEach { e ->
          Divider(); PRow(db.friends.firstOrNull { it.id == e.friendId }?.name ?: "Friend",
            value = if (e.amount >= 0) "owes ${Money.format(e.amount)}" else "paid, you owe ${Money.format(e.amount)}",
            valueColor = if (e.amount >= 0) C.income else C.expense)
        }
      }
    }
    group {
      PRow("Edit", titleColor = C.accent, leading = { Icon2("pencil") }, onClick = { Ui.sheet = Sheet.Add(t.kind, editId = t.id) })
      Divider(56.dp); PRow("Duplicate", titleColor = C.accent, leading = { Icon2("plus.square.on.square") }, onClick = { TxnOps.duplicate(t) })
      if (t.recurringId == null) { Divider(56.dp); PRow("Repeat…", titleColor = C.accent, leading = { Icon2("repeat") }, onClick = { Ui.sheet = Sheet.RecurringForm(null, t.id) }) }
      Divider(56.dp); PRow("Delete", titleColor = C.expense, leading = { Icon(Sym.of("trash"), null, tint = C.expense) }, onClick = { TxnOps.delete(t); Ui.pop() })
    }
  }
}
