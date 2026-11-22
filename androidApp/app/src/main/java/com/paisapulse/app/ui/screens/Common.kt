package com.paisapulse.app.ui.screens

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.paisapulse.app.data.*
import com.paisapulse.app.logic.Money
import com.paisapulse.app.logic.toDate
import com.paisapulse.app.ui.*
import com.paisapulse.app.work.Services
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

class Lookups(db: Db) {
  val accounts = db.accounts.associateBy { it.id }
  val categories = db.categories.associateBy { it.id }
  fun title(t: Txn) = t.payee?.takeIf { it.isNotBlank() } ?: when (t.kind) {
    TxnType.Transfer -> "Transfer"; else -> t.categoryId?.let { categories[it]?.name } ?: t.kind.label
  }
  fun subtitle(t: Txn): String {
    val a = accounts[t.accountId]?.name ?: "Account"
    if (t.kind == TxnType.Transfer) return "$a → ${t.toAccountId?.let { accounts[it]?.name } ?: "Account"}"
    return "${t.categoryId?.let { categories[it]?.name } ?: "Uncategorised"} · $a"
  }
  fun badge(t: Txn): Pair<String, String> = when {
    t.kind == TxnType.Transfer -> "arrow.left.arrow.right" to "#8E8E93"
    t.categoryId != null && categories[t.categoryId] != null -> categories.getValue(t.categoryId).let { it.icon to it.color }
    else -> (if (t.kind == TxnType.Income) "arrow.down.left" else "questionmark") to "#8E8E93"
  }
}

val timeFmt: DateTimeFormatter = DateTimeFormatter.ofPattern("h:mm a", Locale.ENGLISH)
val dayFmt: DateTimeFormatter = DateTimeFormatter.ofPattern("EEE, d MMM", Locale.ENGLISH)
val shortDate: DateTimeFormatter = DateTimeFormatter.ofPattern("d MMM", Locale.ENGLISH)
fun Long.time(): String = java.time.Instant.ofEpochMilli(this).atZone(java.time.ZoneId.systemDefault()).format(timeFmt)
fun dayLabel(d: LocalDate) = when (d) { LocalDate.now() -> "Today"; LocalDate.now().minusDays(1) -> "Yesterday"; else -> dayFmt.format(d) }

/** A transaction row with swipe (delete / duplicate) and long-press menu, like iOS. */
@OptIn(ExperimentalFoundationApi::class, ExperimentalMaterial3Api::class)
@Composable fun TxnRow(t: Txn, l: Lookups, showTime: Boolean = true) {
  var menu by remember { mutableStateOf(false) }
  val state = rememberSwipeToDismissBoxState(confirmValueChange = { v ->
    when (v) {
      SwipeToDismissBoxValue.EndToStart -> TxnOps.delete(t)
      SwipeToDismissBoxValue.StartToEnd -> TxnOps.duplicate(t)
      else -> {}
    }
    false
  })
  SwipeToDismissBox(state, backgroundContent = {
    val d = state.dismissDirection
    Box(Modifier.fillMaxSize().background(if (d == SwipeToDismissBoxValue.StartToEnd) hex("#5E5CE6") else C.expense).padding(horizontal = 24.dp),
      contentAlignment = if (d == SwipeToDismissBoxValue.StartToEnd) Alignment.CenterStart else Alignment.CenterEnd) {
      Icon(Sym.of(if (d == SwipeToDismissBoxValue.StartToEnd) "plus.square.on.square" else "trash"), null, tint = Color.White)
    }
  }) {
    Box {
      val (icon, color) = l.badge(t)
      Row(Modifier.fillMaxWidth().background(C.card).combinedClickable(onClick = { Ui.push(Route.TxnDetail(t.id)) }, onLongClick = { menu = true })
        .padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        CategoryBadge(icon, color)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
          Text(l.title(t), style = T.body, color = C.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
          Text(l.subtitle(t) + if (showTime) " · " + t.occurredAt.time() else "", style = T.footnote, color = C.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Column(horizontalAlignment = Alignment.End) {
          AmountText(t.amount, t.kind)
          t.splitShare?.let { Text("yours ${Money.format(it)}", style = T.caption2, color = C.secondary) }
        }
        Icon(Sym.of("chevron.right"), null, tint = C.tertiary, modifier = Modifier.padding(start = 6.dp).size(13.dp))
      }
      DropdownMenu(menu, { menu = false }, modifier = Modifier.background(C.card)) {
        DropdownMenuItem({ Text("Edit", style = T.body) }, { menu = false; Ui.sheet = Sheet.Add(t.kind, editId = t.id) }, leadingIcon = { Icon(Sym.of("pencil"), null) })
        DropdownMenuItem({ Text("Duplicate", style = T.body) }, { menu = false; TxnOps.duplicate(t) }, leadingIcon = { Icon(Sym.of("plus.square.on.square"), null) })
        DropdownMenuItem({ Text("Delete", style = T.body, color = C.expense) }, { menu = false; TxnOps.delete(t) }, leadingIcon = { Icon(Sym.of("trash"), null, tint = C.expense) })
      }
    }
  }
}

object TxnOps {
  fun delete(t: Txn) {
    Store.update { db -> db.copy(transactions = db.transactions.map { if (it.id == t.id) it.copy(deletedAt = now()) else it }) }
    Services.refreshWidget()
    Ui.show("Deleted") { Store.update { db -> db.copy(transactions = db.transactions.map { if (it.id == t.id) it.copy(deletedAt = null) else it }) } }
  }
  fun duplicate(t: Txn) {
    val c = t.copy(id = newId(), occurredAt = now(), createdAt = now(), updatedAt = now(), splitShare = null, recurringId = null, source = "manual")
    Store.update { it.copy(transactions = it.transactions + c) }
    Ui.show("Duplicated") { Store.update { db -> db.copy(transactions = db.transactions.filterNot { it.id == c.id }) } }
  }
}

@Composable fun AddButton() {
  var menu by remember { mutableStateOf(false) }
  Box {
    Box(Modifier.size(44.dp).glass().combinedClickableCompat(onClick = { Ui.sheet = Sheet.Add() }, onLongClick = { menu = true }), contentAlignment = Alignment.Center) {
      Icon(Sym.of("plus"), "Add expense", tint = C.accent)
    }
    DropdownMenu(menu, { menu = false }, modifier = Modifier.background(C.card)) {
      DropdownMenuItem({ Text("Income", style = T.body) }, { menu = false; Ui.sheet = Sheet.Add(TxnType.Income) })
      DropdownMenuItem({ Text("Transfer", style = T.body) }, { menu = false; Ui.sheet = Sheet.Add(TxnType.Transfer) })
      DropdownMenuItem({ Text("Expense", style = T.body) }, { menu = false; Ui.sheet = Sheet.Add(TxnType.Expense) })
    }
  }
}

@OptIn(ExperimentalFoundationApi::class)
fun Modifier.combinedClickableCompat(onClick: () -> Unit, onLongClick: () -> Unit) = this.combinedClickable(onClick = onClick, onLongClick = onLongClick)

@Composable fun SummaryCells(a: Pair<String, Pair<Long, Color>>, b: Pair<String, Pair<Long, Color>>) {
  Row(Modifier.fillMaxWidth().padding(vertical = 10.dp)) {
    listOf(a, b).forEach { (label, v) ->
      Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(label, style = T.caption, color = C.secondary)
        Text(Money.format(v.first, Prefs.hideAmounts), style = T.amount(17), color = v.second)
      }
    }
  }
}
