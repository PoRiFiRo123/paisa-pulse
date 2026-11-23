package com.paisapulse.app.ui.screens

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.paisapulse.app.data.*
import com.paisapulse.app.logic.*
import com.paisapulse.app.ui.*
import java.time.LocalDate
import java.time.temporal.ChronoUnit

@Composable fun BalanceText(a: Account, balance: Long, style: androidx.compose.ui.text.TextStyle = T.amount(17)) {
  Column(horizontalAlignment = Alignment.End) {
    Text(Money.format(balance, Prefs.hideAmounts), style = style, color = if (balance < 0) C.expense else C.label)
    if (balance < 0) Text(if (a.kind == AccountType.Card) "due" else "overdrawn", style = T.caption2, color = C.expense)
  }
}

@Composable fun AccountRow(a: Account, balance: Long) {
  Column(Modifier.fillMaxWidth().clickable { Ui.push(Route.AccountDetail(a.id)) }.padding(horizontal = 16.dp, vertical = 10.dp)) {
    Row(verticalAlignment = Alignment.CenterVertically) {
      CategoryBadge(a.icon, a.color)
      Spacer(Modifier.width(12.dp))
      Column(Modifier.weight(1f)) {
        Text(a.name, style = T.body, color = C.label, maxLines = 1)
        val parts = listOfNotNull(a.institution?.takeIf { it.isNotBlank() }, a.last4?.let { "••$it" },
          if (a.kind == AccountType.Card) a.dueDay?.let { "due " + shortDate.format(Cards.nextDue(it)) } else null)
        Text(parts.ifEmpty { listOf(a.kind.label) }.joinToString(" · "), style = T.footnote, color = C.secondary, maxLines = 1)
      }
      BalanceText(a, balance)
      Icon(Sym.of("chevron.right"), null, tint = C.tertiary, modifier = Modifier.padding(start = 6.dp).size(13.dp))
    }
    val limit = a.creditLimit
    if (a.kind == AccountType.Card && limit != null && limit > 0) {
      val used = maxOf(0L, -balance)
      ProgressBar(used.toDouble() / limit, if (used.toDouble() / limit > 0.3) hex("#FF9500") else hex(a.color), Modifier.padding(start = 48.dp, top = 8.dp))
    }
  }
}

@Composable fun AccountDetailScreen(id: String) {
  val db by Store.db.collectAsState()
  val a = db.accounts.firstOrNull { it.id == id } ?: run { LaunchedEffect(Unit) { Ui.pop() }; return }
  val l = remember(db) { Lookups(db) }
  val balance = Ledger.balances(db.accounts, db.transactions, db.valuations)[a.id] ?: 0
  val mine = db.liveTxns.filter { it.accountId == a.id || it.toAccountId == a.id }.sortedByDescending { it.occurredAt }
  var menu by remember { mutableStateOf(false) }
  PScreen(a.name, back = true, actions = {
    Box {
      GlassIcon("ellipsis", "More") { menu = true }
      DropdownMenu(menu, { menu = false }, modifier = Modifier.background(C.card)) {
        DropdownMenuItem({ Text("Edit") }, { menu = false; Ui.sheet = Sheet.AccountForm(a.id) })
        DropdownMenuItem({ Text("Add Transaction") }, { menu = false; Ui.sheet = Sheet.Add(accountId = a.id) })
        DropdownMenuItem({ Text("Import Statement") }, { menu = false; Ui.push(Route.Import(a.id)) })
        DropdownMenuItem({ Text(if (a.archivedAt == null) "Archive" else "Unarchive") }, { menu = false
          Store.update { d -> d.copy(accounts = d.accounts.map { if (it.id == a.id) it.copy(archivedAt = if (a.archivedAt == null) now() else null) else it }) } })
        DropdownMenuItem({ Text("Delete", color = C.expense) }, { menu = false
          if (mine.isEmpty()) { Store.update { d -> d.copy(accounts = d.accounts.filterNot { it.id == a.id }) }; Ui.pop() } else Ui.show("Has transactions: archive it instead") })
      }
    }
  }) {
    val cards = db.cards.filter { it.accountId == a.id && it.archivedAt == null }.sortedBy { it.createdAt }
    item { Box(Modifier.padding(16.dp)) { WalletCard(a, balance, cards) } }
    if (a.kind != AccountType.Cash && a.kind != AccountType.Investment) group(if (a.kind == AccountType.Card) "Card" else "Linked cards",
      footer = if (cards.isEmpty()) "Scan the card with the camera or type it in. Only the last 4 digits, network and expiry are kept." else "Tap the stack to spread it. Long-press a card to edit or remove it.") {
      if (cards.isNotEmpty()) Box(Modifier.padding(12.dp)) { CardStack(cards, a.color) { Ui.sheet = Sheet.CardForm(a.id, it.id) } }
      PRow(if (a.kind == AccountType.Card) (if (cards.isEmpty()) "Add Card Details" else "Add Add-on Card") else "Add Debit Card", titleColor = C.accent,
        leading = { Icon2("creditcard.fill") }, onClick = { Ui.sheet = Sheet.CardForm(a.id, null) })
    }
    if (a.kind == AccountType.Card) group("Card") {
      val owed = maxOf(0L, -balance)
      val limit = a.creditLimit
      if (limit != null && limit > 0) {
        Column(Modifier.padding(16.dp)) {
          Row { Text("Limit used", style = T.body, color = C.label, modifier = Modifier.weight(1f)); Text("${Money.format(owed)} of ${Money.format(limit)}", style = T.body, color = C.secondary) }
          Spacer(Modifier.height(8.dp)); ProgressBar(owed.toDouble() / limit, if (owed.toDouble() / limit > 0.3) hex("#FF9500") else C.accent)
          if (owed.toDouble() / limit > 0.3) Text("Keeping it under 30% helps your credit score.", style = T.caption, color = C.secondary, modifier = Modifier.padding(top = 6.dp))
        }
        Divider(); PRow("Available", value = Money.format(maxOf(0, limit - owed)))
      }
      a.statementDay?.let { sd ->
        val cyc = Cards.cycle(sd)
        Divider(); PRow("Unbilled (this cycle)", value = Money.format(mine.filter { it.kind == TxnType.Expense && it.accountId == a.id && it.occurredAt in cyc }.sumOf { it.amount }))
        Divider(); PRow("Statement on", value = shortDate.format(cyc.end.toDate().minusDays(1)))
      }
      CardStatement.last(a, db.liveTxns)?.let { st ->
        Divider(); PRow("Last statement", value = "${Money.format(st.paid)} paid of ${Money.format(st.billed)}")
        Divider(); PRow("Still to pay", value = if (st.due > 0) Money.format(st.due) else "Paid in full", valueColor = if (st.due > 0) C.expense else C.income)
      }
      a.dueDay?.let { dd ->
        val due = Cards.nextDue(dd); val days = ChronoUnit.DAYS.between(LocalDate.now(), due)
        Divider(); PRow("Bill due", value = shortDate.format(due) + if (days <= 5) " · in $days days" else "", valueColor = if (days <= 3 && owed > 0) C.expense else null)
      }
      if (owed > 0) { Divider(); PRow("Pay Bill (${Money.format(owed)})", titleColor = C.accent, leading = { Icon2("indianrupeesign.circle") },
        onClick = { Ui.sheet = Sheet.Add(TxnType.Transfer) }) }
    }
    if (a.kind == AccountType.Investment) valuationSection(a, db.valuations)
    group("Transactions") {
      if (mine.isEmpty()) PRow("No transactions yet", titleColor = C.secondary)
      mine.take(100).forEachIndexed { i, t -> if (i > 0) Divider(64.dp); TxnRow(t, l) }
    }
  }
}

@Composable fun CategoriesScreen() {
  val db by Store.db.collectAsState()
  var income by remember { mutableStateOf(false) }
  val kind = if (income) "income" else "expense"
  PScreen("Categories", back = true, actions = {
    GlassIcon("arrow.up.arrow.down", "Reorder") { Ui.sheet = Sheet.Reorder("categories:$kind") }
    GlassIcon("plus", "Add category") { Ui.sheet = Sheet.CategoryForm(null, income) }
  }) {
    item { Segmented(listOf("Expense", "Income"), if (income) 1 else 0, Modifier.padding(16.dp)) { income = it == 1 } }
    db.categories.filter { it.kind == kind && it.parentId == null && it.archivedAt == null }.sortedBy { it.sortOrder }.forEach { p ->
      group {
        PRow(p.name, leading = { CategoryBadge(p.icon, p.color, 32.dp) }, chevron = true, onClick = { Ui.sheet = Sheet.CategoryForm(p.id, income) })
        db.categories.filter { it.parentId == p.id && it.archivedAt == null }.forEach { c ->
          Divider(64.dp); PRow(c.name, modifier = Modifier.padding(start = 20.dp), leading = { CategoryBadge(c.icon, c.color, 26.dp) }, chevron = true,
            onClick = { Ui.sheet = Sheet.CategoryForm(c.id, income) })
        }
      }
    }
    val hidden = db.categories.filter { it.kind == kind && it.archivedAt != null }
    if (hidden.isNotEmpty()) group("Hidden") { hidden.forEachIndexed { i, c -> if (i > 0) Divider(64.dp); PRow(c.name, leading = { CategoryBadge(c.icon, c.color, 30.dp) }, chevron = true, onClick = { Ui.sheet = Sheet.CategoryForm(c.id, income) }) } }
  }
}

@Composable fun BudgetsScreen() {
  val db by Store.db.collectAsState()
  val l = remember(db) { Lookups(db) }
  val p = Budgets.progress(db.budgets, TripMath.budgetTxns(db.transactions, db.trips), l.categories, Periods.month(LocalDate.now(), Prefs.monthStartDay), Periods.week(LocalDate.now(), Prefs.weekStartDay))
  PScreen("Budgets", back = true, actions = { GlassIcon("plus", "Add budget") { Ui.sheet = Sheet.BudgetForm(null) } }) {
    if (p.isEmpty()) item { EmptyHint("No budgets", "gauge.with.dots.needle.33percent", "Set a monthly limit for everything or for one category. You'll get a nudge at 80%.") }
    else group(footer = "Tap a budget to change or delete it.") { p.forEachIndexed { i, x -> if (i > 0) Divider(); BudgetRow(x, l) } }
  }
}

@Composable fun RecurringScreen() {
  val db by Store.db.collectAsState()
  val l = remember(db) { Lookups(db) }
  PScreen("Recurring", back = true, actions = { GlassIcon("plus", "Add recurring") { Ui.sheet = Sheet.RecurringForm(null) } }) {
    if (db.recurringRules.isEmpty()) item { EmptyHint("Nothing repeats yet", "repeat", "Rent, SIPs, subscriptions: add them once and they log themselves.") }
    else group {
      db.recurringRules.sortedBy { it.nextAt }.forEachIndexed { i, r ->
        if (i > 0) Divider(64.dp)
        val c = r.categoryId?.let { l.categories[it] }
        PRow(r.payee ?: c?.name ?: "Recurring", subtitle = if (r.pausedAt != null) "Paused" else "Every ${if (r.interval > 1) "${r.interval} " else ""}${r.freq.noun}${if (r.interval > 1) "s" else ""} · next ${shortDate.format(r.nextAt.toDate())}",
          leading = { CategoryBadge(c?.icon ?: "repeat", c?.color) }, onClick = { Ui.sheet = Sheet.RecurringForm(r.id) }) { AmountText(r.amount, TxnType.of(r.type)) }
      }
    }
  }
}

@Composable fun GoalsScreen() {
  val db by Store.db.collectAsState()
  PScreen("Goals", back = true, actions = { GlassIcon("plus", "Add goal") { Ui.sheet = Sheet.GoalForm(null) } }) {
    val goals = db.goals.filter { it.archivedAt == null }
    if (goals.isEmpty()) item { EmptyHint("No goals yet", "target", "A trip, a new phone, an emergency fund. Save towards it bit by bit.") }
    else group { goals.forEachIndexed { i, g -> if (i > 0) Divider(64.dp); GoalRow(g) } }
  }
}

