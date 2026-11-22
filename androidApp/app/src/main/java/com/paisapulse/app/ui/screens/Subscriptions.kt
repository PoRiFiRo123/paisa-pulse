package com.paisapulse.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.paisapulse.app.data.*
import com.paisapulse.app.logic.*
import com.paisapulse.app.ui.*

/** Mirrors the iPhone SubscriptionsView. */
@Composable fun SubscriptionsScreen() {
  val db by Store.db.collectAsState()
  val l = remember(db) { Lookups(db) }
  var dismissed by remember { mutableStateOf(setOf<String>()) }
  val now = now()
  val subs = db.recurringRules.filter { it.type == "expense" }
    .sortedWith(compareBy<RecurringRule>({ if (Subscriptions.isActive(it, now)) 0 else 1 }, { it.nextAt }))
  val active = subs.filter { Subscriptions.isActive(it, now) }
  val monthly = active.sumOf { Subscriptions.monthly(it) }
  val found = remember(db) { Subscriptions.detect(db.transactions, db.recurringRules, now) }.filter { it.id !in dismissed }
  val paid = db.liveTxns.filter { it.recurringId != null }.groupBy { it.recurringId!! }

  PScreen("Subscriptions", back = true) {
    group {
      Column(Modifier.padding(16.dp)) {
        Text("Every month", style = T.subhead, color = C.secondary)
        Text(Money.format(monthly, Prefs.hideAmounts), style = T.amount(40, FontWeight.Bold), color = C.expense)
        Text("${Money.format(monthly * 12, Prefs.hideAmounts)} a year · ${active.size} active", style = T.subhead, color = C.secondary)
      }
    }
    if (found.isNotEmpty()) group("Found in your history", footer = "Steady payments on a steady cadence. Tracking adds the next payment for you and links the past ones.") {
      found.forEachIndexed { i, d ->
        if (i > 0) Divider(64.dp)
        PRow(d.payee, subtitle = "${Money.format(d.amount, Prefs.hideAmounts)} every ${d.frequency.noun} · ${d.txnIds.size} payments",
          leading = { SubBadge(d.payee, d.categoryId, l) }, onLongClick = { dismissed = dismissed + d.id }) {
          Text("Track", style = T.subhead.copy(fontWeight = FontWeight.SemiBold), color = androidx.compose.ui.graphics.Color.White,
            modifier = Modifier.clip(CircleShape).background(C.accent).combinedClickableCompat({ track(d) }, {}).padding(horizontal = 14.dp, vertical = 6.dp))
        }
      }
    }
    if (subs.isEmpty()) item { EmptyHint("No subscriptions yet", "creditcard.and.123", "Netflix, Spotify, the gym: track them here, or add a monthly expense under Recurring.") }
    else group("Tracked") {
      subs.forEachIndexed { i, r ->
        if (i > 0) Divider(64.dp)
        val on = Subscriptions.isActive(r, now)
        val pays = paid[r.id].orEmpty()
        Column(Modifier.alpha(if (on) 1f else 0.55f)) {
          PRow(r.payee ?: r.categoryId?.let { l.categories[it]?.name } ?: "Subscription",
            subtitle = (if (on) "Renews ${shortDate.format(r.nextAt.toDate())}" else if (r.pausedAt != null) "Paused" else "Ended") +
              if (pays.isNotEmpty()) " · paid ${Money.format(pays.sumOf { it.amount }, Prefs.hideAmounts)} over ${pays.size}" else "",
            leading = { SubBadge(r.payee, r.categoryId, l) }, onClick = { Ui.sheet = Sheet.RecurringForm(r.id) }) {
            Column(horizontalAlignment = Alignment.End) {
              AmountText(r.amount, TxnType.Expense)
              Text("/${if (r.interval > 1) "${r.interval} " else ""}${r.freq.noun}${if (r.interval > 1) "s" else ""}", style = T.caption2, color = C.secondary)
            }
          }
        }
      }
    }
  }
}

@Composable private fun SubBadge(payee: String?, categoryId: String?, l: Lookups) {
  val b = Brands.match(payee)
  if (b != null) MerchantBadge(b) else { val c = categoryId?.let { l.categories[it] }; CategoryBadge(c?.icon ?: "repeat", c?.color ?: "#32ADE6") }
}

private fun track(d: Subscriptions.Detected) {
  val rule = Subscriptions.rule(d)
  val ids = d.txnIds.toSet()
  Store.update { db -> db.copy(recurringRules = db.recurringRules + rule,
    transactions = db.transactions.map { if (it.id in ids) it.copy(recurringId = rule.id) else it }) }
  Ui.show("Tracking ${d.payee}") {
    Store.update { db -> db.copy(recurringRules = db.recurringRules.filterNot { it.id == rule.id },
      transactions = db.transactions.map { if (it.id in ids) it.copy(recurringId = null) else it }) }
  }
}
