package com.paisapulse.app.ui.screens

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.paisapulse.app.data.*
import com.paisapulse.app.logic.*
import com.paisapulse.app.ui.*
import java.time.LocalDate
import java.time.format.TextStyle
import java.util.Locale

@Composable fun HomeScreen() {
  val db by Store.db.collectAsState()
  val l = remember(db) { Lookups(db) }
  val txns = remember(db) { db.liveTxns.sortedByDescending { it.occurredAt } }
  val month = Periods.month(LocalDate.now(), Prefs.monthStartDay)
  val title = month.start.toDate().month.getDisplayName(TextStyle.FULL, Locale.ENGLISH)
  val off = HomeSections.hidden(Prefs.homeHidden)

  val view = androidx.compose.ui.platform.LocalView.current
  // One tap hides every amount in the app (and in the recent-apps preview).
  val pendingAlerts by com.paisapulse.app.work.AlertQueue.count.collectAsState()
  val homeCtx = androidx.compose.ui.platform.LocalContext.current
  LaunchedEffect(Unit) { com.paisapulse.app.work.AlertQueue.refresh(homeCtx) }
  PScreen(title, leading = { GlassIcon("calendar", "Calendar") { Ui.push(Route.Calendar) } }, actions = {
    GlassIcon(if (Prefs.hideAmounts) "eye.slash" else "eye", if (Prefs.hideAmounts) "Show Amounts" else "Hide Amounts") {
      Haptics.soft(view); Prefs.set("hideAmounts", !Prefs.hideAmounts)
    }
  }) {
    if (pendingAlerts > 0) group {
      PRow("$pendingAlerts bank message${if (pendingAlerts == 1) "" else "s"} to review", titleColor = C.accent,
        leading = { Badge("message.badge.filled.fill", "#34C759") }, chevron = true, onClick = { Ui.push(Route.Capture("alerts")) })
    }
    HomeSections.order(Prefs.homeOrder).filter { it !in off }.forEach { key ->
      when (key) {
        "trips" -> homeTripsSection(db)
        "hero" -> group { HeroCard(Ledger.summary(txns, month), db.budgets.firstOrNull { it.categoryId == null && it.period != "weekly" }?.amount) }
        "templates" -> {
          val templates = db.templates.sortedBy { it.sortOrder }
          if (templates.isNotEmpty()) group("Quick add", footer = "Tap to add it now. Save more from any transaction › Save as Template.",
            trailing = { Text("Edit", style = T.subhead, color = C.accent, modifier = Modifier.clickable { Ui.push(Route.Templates) }) }) {
            Row(Modifier.horizontalScroll(rememberScrollState()).padding(12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
              templates.forEach { t ->
                Column(Modifier.clip(RoundedCornerShape(14.dp)).background(C.accent.copy(alpha = 0.12f)).clickable { quickAdd(t) }.padding(horizontal = 12.dp, vertical = 8.dp)) {
                  Text("⚡ ${t.name}", style = T.subhead.copy(fontWeight = FontWeight.Medium), color = C.accent, maxLines = 1)
                  Text(Money.format(t.amount, Prefs.hideAmounts), style = T.caption, color = C.secondary)
                }
              }
            }
          }
        }
        "forecast" -> {
          val f = Forecast.monthEnd(db.accounts, txns, db.valuations, db.recurringRules, month)
          if (f.daysLeft > 0) group("Month-end forecast") { ForecastCard(f) }
        }
        "cards" -> {
          val due = db.accounts.filter { it.kind == AccountType.Card && it.archivedAt == null && it.dueDay != null }.mapNotNull { a ->
            val d = Cards.nextDue(a.dueDay!!)
            val days = java.time.temporal.ChronoUnit.DAYS.between(LocalDate.now(), d)
            val amount = CardStatement.last(a, txns)?.due ?: maxOf(0L, -(Ledger.balances(listOf(a), txns)[a.id] ?: 0))
            if (days <= 10 && amount > 0) Triple(a, d, amount) else null
          }
          if (due.isNotEmpty()) group("Card bills") {
            due.forEachIndexed { i, (a, d, amount) ->
              if (i > 0) Divider(64.dp)
              val days = java.time.temporal.ChronoUnit.DAYS.between(LocalDate.now(), d)
              PRow(a.name, subtitle = if (days == 0L) "Due today" else "Due in $days days",
                leading = { CategoryBadge(a.icon, a.color, 32.dp) }, onClick = { Ui.sheet = Sheet.Add(TxnType.Transfer) }) {
                Text(Money.format(amount, Prefs.hideAmounts), style = T.amount(17), color = C.label)
              }
            }
          }
        }
        "categories" -> {
          val top = Ledger.byCategory(txns, month, l.categories).take(6)
          if (top.isNotEmpty()) group("Where it went") {
            Row(Modifier.horizontalScroll(rememberScrollState()).padding(12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
              top.forEach { (id, amt) ->
                val c = l.categories[id]
                Row(Modifier.clip(CircleShape).background(C.fill).padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                  CategoryBadge(c?.icon ?: "questionmark", c?.color, 28.dp)
                  Spacer(Modifier.width(8.dp))
                  Column {
                    Text(c?.name ?: "Uncategorised", style = T.caption, color = C.secondary, maxLines = 1)
                    Text(Money.format(amt, Prefs.hideAmounts), style = T.amount(15), color = C.label)
                  }
                }
              }
            }
            Divider()
            PRow("Insights", leading = { Icon2("chart.bar.xaxis") }, chevron = true, onClick = { Ui.push(Route.Insights) })
          }
        }
        "budgets" -> {
          val progress = Budgets.progress(db.budgets, TripMath.budgetTxns(txns, db.trips), l.categories, month, Periods.week(LocalDate.now(), Prefs.weekStartDay))
          if (progress.isNotEmpty()) group("Budgets", trailing = { Text("Edit", style = T.subhead, color = C.accent, modifier = Modifier.clickable { Ui.push(Route.Budgets) }) }) {
            progress.forEachIndexed { i, p -> if (i > 0) Divider(); BudgetRow(p, l) }
          }
        }
        "goals" -> {
          val goals = db.goals.filter { it.archivedAt == null }
          if (goals.isNotEmpty()) group("Goals", trailing = { Text("All", style = T.subhead, color = C.accent, modifier = Modifier.clickable { Ui.push(Route.Goals) }) }) {
            goals.take(3).forEachIndexed { i, g -> if (i > 0) Divider(64.dp); GoalRow(g) }
          }
        }
        "upcoming" -> {
          val upcoming = db.recurringRules.filter { it.pausedAt == null && it.nextAt < now() + 7 * 86_400_000L }.sortedBy { it.nextAt }.take(3)
          if (upcoming.isNotEmpty()) group("Next 7 days") {
            upcoming.forEachIndexed { i, r ->
              if (i > 0) Divider(64.dp)
              val c = r.categoryId?.let { l.categories[it] }
              PRow(r.payee ?: c?.name ?: "Recurring", subtitle = shortDate.format(r.nextAt.toDate()), leading = { CategoryBadge(c?.icon ?: "repeat", c?.color, 30.dp) }) {
                AmountText(r.amount, TxnType.of(r.type))
              }
            }
          }
        }
        "recap" -> {
          val day = java.time.temporal.ChronoUnit.DAYS.between(month.start.toDate(), LocalDate.now())
          if (day < 7 && txns.any { it.occurredAt < month.start }) group {
            val last = Periods.month(-1, Prefs.monthStartDay).start.toDate().month.getDisplayName(TextStyle.FULL, Locale.ENGLISH)
            PRow("Your $last recap", subtitle = "Where it went, your best streak and more", leading = { CategoryBadge("sparkles", "#5E5CE6", 36.dp) },
              chevron = true, onClick = { Ui.push(Route.Recap(-1)) })
          }
        }
        "recent" -> group("Recent", trailing = { Text("See all", style = T.subhead, color = C.accent, modifier = Modifier.clickable { Ui.select(Tab.Activity) }) }) {
          if (txns.isEmpty()) EmptyHint("No transactions yet", "indianrupeesign.circle", "Tap + to add what you spent. It takes two taps.")
          txns.take(8).forEachIndexed { i, t -> if (i > 0) Divider(64.dp); TxnRow(t, l) }
        }
      }
    }
    item {
      Text("Edit Home Screen", style = T.subhead, color = C.accent, textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        modifier = Modifier.fillMaxWidth().clickable { Ui.sheet = Sheet.HomeLayout }.padding(16.dp))
    }
  }
}

/** A template adds straight away, with Undo. */
fun quickAdd(t: TxnTemplate) {
  val d = Store.value
  val acc = t.accountId?.takeIf { id -> d.accounts.any { it.id == id && it.archivedAt == null } }
    ?: d.accounts.firstOrNull { it.id == Prefs.lastAccountId }?.id ?: d.accounts.firstOrNull { it.archivedAt == null }?.id ?: return
  val txn = Txn(type = t.type, amount = t.amount, accountId = acc, toAccountId = if (t.type == "transfer") t.toAccountId else null,
    categoryId = if (t.type == "transfer") null else t.categoryId, payee = t.payee ?: t.name, source = "template")
  Store.update { it.copy(transactions = it.transactions + txn) }
  com.paisapulse.app.work.Services.refreshWidget()
  Ui.show("Added ${t.name} · ${Money.format(t.amount)}") { Store.update { db -> db.copy(transactions = db.transactions.map { if (it.id == txn.id) it.copy(deletedAt = now()) else it }) } }
}

@Composable fun Icon2(sym: String) = androidx.compose.material3.Icon(Sym.of(sym), null, tint = C.accent, modifier = Modifier.size(24.dp))

/** One card, one ring: spending against the budget (or income). */
@Composable fun HeroCard(s: Ledger.Summary, budget: Long?) {
  val base = budget ?: s.income
  val ratio = if (base > 0) (s.spent.toDouble() / base).coerceAtMost(1.5) else 0.0
  val sweep by animateFloatAsState(ratio.coerceAtMost(1.0).toFloat(), quick(), label = "ring")
  val ringColor = if (ratio > 1) C.expense else C.accent
  val track = C.fill
  Row(Modifier.fillMaxWidth().liquidBackground().padding(20.dp), verticalAlignment = Alignment.CenterVertically) {
    Column(Modifier.weight(1f)) {
      Text("Spent this month", style = T.subhead, color = C.secondary)
      RollingText(Money.format(s.spent, Prefs.hideAmounts), T.amount(38, FontWeight.Bold), C.label, Modifier.padding(vertical = 6.dp))
      Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        Stat("Income", Money.format(s.income, Prefs.hideAmounts), C.income)
        Stat(if (s.saved >= 0) "Saved" else "Overspent", Money.format(s.saved, Prefs.hideAmounts), if (s.saved >= 0) C.label else C.expense)
      }
    }
    if (base > 0) Box(Modifier.size(88.dp), contentAlignment = Alignment.Center) {
      Canvas(Modifier.fillMaxSize()) {
        val st = Stroke(10.dp.toPx(), cap = StrokeCap.Round)
        drawArc(track, 0f, 360f, false, style = st)
        drawArc(ringColor, -90f, 360f * sweep, false, style = st)
      }
      Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text("${Math.round(ratio * 100)}%", style = T.headline, color = C.label)
        Text(if (budget != null) "of budget" else "of income", style = T.caption2, color = C.secondary)
      }
    }
  }
}

@Composable fun Stat(label: String, value: String, color: Color) {
  Column {
    Text(label, style = T.caption, color = C.secondary)
    RollingText(value, T.amount(15), color)
  }
}

@Composable fun BudgetRow(p: Budgets.Progress, l: Lookups) {
  val c = p.budget.categoryId?.let { l.categories[it] }
  Column(Modifier.fillMaxWidth().clickable { Ui.sheet = Sheet.BudgetForm(p.budget.id) }.padding(16.dp)) {
    Row(verticalAlignment = Alignment.CenterVertically) {
      Text(c?.name ?: "Everything", style = T.subhead.copy(fontWeight = FontWeight.Medium), color = C.label)
      if (p.budget.period == "weekly") Text("  weekly", style = T.caption, color = C.secondary)
      Spacer(Modifier.weight(1f))
      Text(if (p.over) "${Money.format(p.left, Prefs.hideAmounts)} over" else "${Money.format(p.left, Prefs.hideAmounts)} left", style = T.subhead,
        color = if (p.over) C.expense else C.secondary)
    }
    Spacer(Modifier.height(8.dp))
    ProgressBar(p.ratio, if (p.over) C.expense else if (p.ratio > 0.8) hex("#FF9500") else hex(c?.color ?: "#5E5CE6"))
  }
}

@Composable fun GoalRow(g: Goal) {
  val ratio = if (g.target > 0) g.saved.toDouble() / g.target else 0.0
  Row(Modifier.fillMaxWidth().clickable { Ui.sheet = Sheet.GoalForm(g.id) }.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
    CategoryBadge(g.icon, g.color)
    Spacer(Modifier.width(12.dp))
    Column(Modifier.weight(1f)) {
      Row { Text(g.name, style = T.subhead.copy(fontWeight = FontWeight.Medium), color = C.label, modifier = Modifier.weight(1f))
        Text("${Money.format(g.saved)} of ${Money.format(g.target)}", style = T.footnote, color = C.secondary) }
      Spacer(Modifier.height(6.dp)); ProgressBar(ratio, hex(g.color))
      val d = g.deadline
      if (g.saved >= g.target) Text("Done! 🎉", style = T.caption, color = C.income, modifier = Modifier.padding(top = 4.dp))
      else if (d != null) {
        val months = maxOf(1L, java.time.temporal.ChronoUnit.MONTHS.between(LocalDate.now(), d.toDate()))
        Text("Save ${Money.format((g.target - g.saved) / months)} a month to make it by ${d.toDate().format(java.time.format.DateTimeFormatter.ofPattern("MMM yyyy", Locale.ENGLISH))}",
          style = T.caption, color = C.secondary, modifier = Modifier.padding(top = 4.dp))
      }
    }
  }
}
