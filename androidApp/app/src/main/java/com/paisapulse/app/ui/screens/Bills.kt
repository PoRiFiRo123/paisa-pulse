package com.paisapulse.app.ui.screens

import android.Manifest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.paisapulse.app.data.*
import com.paisapulse.app.logic.*
import com.paisapulse.app.ui.*
import com.paisapulse.app.work.Services

/** Card bills and recurring bills due in the next month, soonest first. Same screen as iOS BillsView. */
@Composable fun BillsScreen() {
  val db by Store.db.collectAsState()
  val bills = remember(db) { Bills.upcoming(db.accounts, db.transactions, db.recurringRules, Ledger.balances(db.accounts, db.transactions, db.valuations)) }
  val askNotify = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {}

  fun recordPayment(b: Bill) {
    val banks = db.accounts.filter { it.kind == AccountType.Bank && it.archivedAt == null }
    val from = banks.firstOrNull { it.id == Prefs.lastAccountId } ?: banks.firstOrNull()
    if (from == null) { Ui.showError("Add a bank account first to pay the card from."); return }
    val t = Txn(type = "transfer", amount = b.amount, accountId = from.id, toAccountId = b.accountId, note = "Card bill payment")
    Store.update { it.copy(transactions = it.transactions + t) }
    Services.refreshWidget()
    Ui.show("Paid ${Money.format(b.amount)} from ${from.name}") {
      Store.update { d -> d.copy(transactions = d.transactions.map { if (it.id == t.id) it.copy(deletedAt = now()) else it }) }; Services.refreshWidget()
    }
  }

  PScreen("Bills", back = true) {
    if (bills.isEmpty()) item {
      EmptyHint("No bills coming up", "checkmark.seal", "Card bills show here when a card has a due day (Accounts › card › Edit). Recurring expenses like rent show too.")
    } else group("Next 31 days", footer = "${Money.format(bills.sumOf { it.amount })} in total. Recurring bills are added on their day by themselves.") {
      bills.forEachIndexed { i, b ->
        if (i > 0) Divider(64.dp)
        val days = Bills.daysLeft(b)
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
          CategoryBadge(b.icon, b.color)
          Spacer(Modifier.width(12.dp))
          Column(Modifier.weight(1f)) {
            Text(b.title, style = T.body, color = C.label, maxLines = 1)
            Text("${Bills.dueText(b)} · ${b.due.toDate().dayOfMonth} ${b.due.toDate().month.name.lowercase().replaceFirstChar { it.uppercase() }.take(3)}",
              style = T.caption, color = if (days <= 1) C.expense else C.secondary)
          }
          Column(horizontalAlignment = Alignment.End) {
            Text(Money.format(b.amount), style = T.body.copy(fontWeight = FontWeight.SemiBold), color = C.label)
            if (b.isCard) Text("Record Payment", style = T.caption.copy(fontWeight = FontWeight.SemiBold), color = C.accent,
              modifier = Modifier.pressScale().combinedClickableCompat({ recordPayment(b) }, {}).padding(top = 4.dp))
          }
        }
      }
    }
    group(footer = "Card bills 3 days before the due day, other bills 2 days before.") {
      ToggleRow("Remind me", Prefs.notifyBills, leading = { Badge("bell.badge", "#FF9500") }) { on ->
        Prefs.set("notifyBills", on)
        if (on && android.os.Build.VERSION.SDK_INT >= 33) askNotify.launch(Manifest.permission.POST_NOTIFICATIONS)
        Services.refreshNotifications()
      }
    }
  }
}
