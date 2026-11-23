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
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.graphicsLayer
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
import kotlinx.coroutines.launch

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
  var split by remember {
    mutableStateOf(editing?.let { e ->
      val old = db.splitEntries.filter { it.txnId == e.id }
      if (old.isEmpty()) SplitSetup() else {
        val base = SplitSetup(people = old.map { it.friendId }, groupId = old.first().groupId)
        val share = e.splitShare
        if (share != null && share != SplitMath.compute(e.amount, base).myShare)
          base.copy(mode = SplitMode.Amount, includeMe = share > 0, values = old.associate { it.friendId to it.amount } + ("me" to share))
        else base
      }
    } ?: SplitSetup())
  }
  var pickCategory by remember { mutableStateOf(false) }
  var pickSplit by remember { mutableStateOf(false) }
  var pickDate by remember { mutableStateOf(false) }
  var error by remember { mutableStateOf<String?>(null) }
  var cardId by remember { mutableStateOf(editing?.cardId) }
  var tagText by remember { mutableStateOf(Tags.text(editing?.tags)) }
  var payeePicked by remember { mutableStateOf(editing != null) }
  val base = Money.base
  var currency by remember { mutableStateOf(editing?.currency ?: base) }
  var rate by remember { mutableStateOf(editing?.let { e -> e.originalAmount?.takeIf { e.currency != null && e.currency != base }?.let { e.amount.toDouble() / it } }) }
  var curMenu by remember { mutableStateOf(false) }
  var allCurrencies by remember { mutableStateOf(false) }
  var method by remember { mutableStateOf(editing?.paymentMethod) }
  var methodTouched by remember { mutableStateOf(editing?.paymentMethod != null) }
  val trips = db.trips.filter { it.archivedAt == null }.sortedByDescending { it.startAt ?: it.createdAt }
  var tripId by remember { mutableStateOf(editing?.tripId ?: req.tripId ?: if (editing == null && req.type != TxnType.Transfer) TripMath.ongoing(trips)?.id else null) }
  var tripItemId by remember { mutableStateOf(editing?.tripItemId) }
  var walletId by remember { mutableStateOf(editing?.walletId) }
  var rateDialog by remember { mutableStateOf(false) }
  var rateText by remember { mutableStateOf("") }
  val ctx = androidx.compose.ui.platform.LocalContext.current
  val scope = rememberCoroutineScope()
  LaunchedEffect(Unit) { editing?.originalAmount?.takeIf { editing.currency != null && editing.currency != base }?.let { o -> expr = if (o % 100 == 0L) (o / 100).toString() else "%.2f".format(o / 100.0) } }
  val entered = KeypadMath.evaluate(expr)?.let { Money.paise(it) }
  val card = cardId?.let { id -> db.cards.firstOrNull { it.id == id } }
  // Converted to the main currency, then the card's forex markup on top.
  val converted = if (currency == base) entered else rate?.let { r -> entered?.let { Fx.convert(it, r) } }
  val amount = if (currency == base) converted else converted?.let { ForexMarkup.apply(it, card?.forexMarkupBps) }
  fun pickCurrency(code: String) {
    currency = code; rate = null
    if (code == base) return
    // A trip wallet in this currency: use what you paid for it, so the trip's numbers match your forex card.
    db.tripWallets.firstOrNull { it.tripId == tripId && it.currency == code }?.let { rate = it.rate; return }
    scope.launch { val r = Currency.rates(ctx)?.inrPer?.let { Fx.rate(code, base, it) }; if (r != null) rate = r else { rateText = ""; rateDialog = true } }
  }
  // Payment method follows the account and card until you pick one.
  LaunchedEffect(accountId, cardId) {
    if (!methodTouched) method = PaymentMethod.guess(accounts.firstOrNull { it.id == accountId }?.type, card?.kind)?.id
  }
  // On a trip abroad right now: start in the destination's currency.
  LaunchedEffect(Unit) {
    if (editing == null) trips.firstOrNull { it.id == tripId }?.takeIf { it.international }?.places?.mapNotNull { it.currency }?.firstOrNull { it != base }
      ?.let { if (currency == base) pickCurrency(it) }
  }
  val kindCats = db.categories.filter { it.archivedAt == null && it.parentId == null && it.kind == (if (type == TxnType.Income) "income" else "expense") }.sortedBy { it.sortOrder }

  fun save() {
    val amt = amount ?: return run { error = "Enter an amount." }
    val acc = accountId ?: return run { error = "Add an account first (Accounts tab)." }
    if (type == TxnType.Transfer && (toAccountId == null || toAccountId == acc)) { error = "Pick a different account to move money to."; return }
    val name = payee.trim().ifEmpty { null }
    val result = SplitMath.compute(amt, split)
    val splitting = type == TxnType.Expense && !split.isEmpty
    if (splitting && !result.valid) { error = "The split amounts don't add up to the total."; return }
    // A friend paid: nothing left your account yet, so it's only "you owe them" (settle up later).
    if (splitting && split.payer != null && editing == null) {
      val entries = result.entries.map { (f, v) -> SplitEntry(friendId = f, amount = v, note = name, groupId = split.groupId, occurredAt = at) }
      Store.update { it.copy(splitEntries = it.splitEntries + entries) }
      Ui.sheet = null
      Ui.show("You owe ${db.friends.firstOrNull { it.id == split.payer }?.name ?: "them"} ${Money.format(result.myShare)}")
      return
    }
    val owed = if (splitting && split.payer == null) result.entries else emptyMap()
    val txn = (editing ?: Txn(amount = amt, accountId = acc)).copy(type = type.key, amount = amt, accountId = acc,
      toAccountId = if (type == TxnType.Transfer) toAccountId else null, categoryId = if (type == TxnType.Transfer) null else categoryId,
      payee = name, occurredAt = at, updatedAt = now(), splitShare = if (splitting && split.payer == null) result.myShare else null, tags = Tags.parse(tagText).ifEmpty { null }, cardId = if (type == TxnType.Income) null else cardId,
      currency = currency.takeIf { it != base }, originalAmount = if (currency == base) null else entered, paymentMethod = method,
      tripId = if (type == TxnType.Transfer) null else tripId, tripItemId = if (type == TxnType.Transfer) null else tripItemId,
      walletId = if (type == TxnType.Expense) walletId else null)
    Store.update { d ->
      val txns = if (editing != null) d.transactions.map { if (it.id == txn.id) txn else it } else d.transactions + txn
      val entries = d.splitEntries.filterNot { it.txnId == txn.id } + owed.map { (f, v) -> SplitEntry(friendId = f, txnId = txn.id, amount = v, note = name, groupId = split.groupId, occurredAt = at) }
      d.copy(transactions = txns, splitEntries = entries)
    }
    Prefs.set("lastAccountId", acc)
    Services.refreshWidget(); Services.checkBudgets()
    Ui.sheet = null
    if (editing != null) Ui.show("Saved") else Ui.show("Added ${Money.format(amt)}") {
      Store.update { d -> d.copy(transactions = d.transactions.map { if (it.id == txn.id) it.copy(deletedAt = now()) else it }) }
    }
    if (editing == null && owed.isNotEmpty()) Ui.sheet = Sheet.Request(name ?: categoryId?.let { id -> db.categories.firstOrNull { it.id == id }?.name }, owed)
  }

  PSheet({ Ui.sheet = null }) {
    Column(Modifier.fillMaxHeight(0.94f)) {
      SheetHeader(if (editing == null) "New ${type.label}" else "Edit ${type.label}", canSave = (amount ?: 0) > 0, onCancel = { Ui.sheet = null }, onSave = ::save)
      Segmented(TxnType.entries.map { it.label }, TxnType.entries.indexOf(type), Modifier.padding(horizontal = 16.dp)) { type = TxnType.entries[it]
        if (categoryId != null && db.categories.firstOrNull { c -> c.id == categoryId }?.kind != (if (type == TxnType.Income) "income" else "expense")) categoryId = null }
      // Amount
      Column(Modifier.fillMaxWidth().padding(vertical = 14.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Row(verticalAlignment = Alignment.Bottom) {
          Box {
            Text(World.symbol(currency), style = T.amount(if (currency == base) 30 else 22), color = C.secondary,
              modifier = Modifier.padding(bottom = 8.dp, end = 4.dp).clickable { curMenu = true })
            DropdownMenu(curMenu, { curMenu = false }, modifier = Modifier.background(C.card).heightIn(max = 420.dp)) {
              DropdownMenuItem({ Text("$base · ${World.currencyName(base)}", style = T.body) }, { curMenu = false; pickCurrency(base) }, leadingIcon = { Icon(Sym.of("house"), null) })
              val tripCodes = trips.firstOrNull { it.id == tripId }?.places?.mapNotNull { it.currency }?.filter { it != base }?.distinct().orEmpty()
              if (tripCodes.isNotEmpty()) {
                HorizontalDivider(color = C.separator)
                tripCodes.forEach { c -> DropdownMenuItem({ Text("$c · ${World.currencyName(c)}", style = T.body) }, { curMenu = false; pickCurrency(c) }, leadingIcon = { Icon(Sym.of("airplane"), null) }) }
              }
              HorizontalDivider(color = C.separator)
              Currency.common.filter { it.code != base && it.code !in tripCodes }.forEach { c -> DropdownMenuItem({ Text("${c.code} · ${c.name}", style = T.body) }, { curMenu = false; pickCurrency(c.code) }) }
              DropdownMenuItem({ Text("All Currencies…", style = T.body, color = C.accent) }, { curMenu = false; allCurrencies = true }, leadingIcon = { Icon(Sym.of("globe"), null, tint = C.accent) })
            }
          }
          AnimatedContent(expr, label = "amt") { e -> Text(e, style = T.amount(56, FontWeight.Bold), color = type.color(C), maxLines = 1) }
        }
        if (currency != base) {
          Text(amount?.let { "≈ ${Money.format(it)} · 1 $currency = ${Money.symbol}${"%.2f".format(rate ?: 0.0)}" } ?: "Tap to set the rate for $currency",
            style = T.subhead, color = C.accent, modifier = Modifier.clickable { rateText = rate?.let { "%.4f".format(it) } ?: ""; rateDialog = true })
          val bps = card?.forexMarkupBps
          if (converted != null && bps != null && bps > 0) Text("incl. ${Money.format(ForexMarkup.fee(converted, bps))} card markup (${ForexMarkup.label(bps)})", style = T.caption, color = C.secondary)
        }
        else if (KeypadMath.isExpression(expr) && amount != null) Text("= ${Money.format(amount)}", style = T.subhead, color = C.secondary)
      }
      val templates = if (editing == null) db.templates.sortedBy { it.sortOrder } else emptyList()
      LazyColumn(Modifier.weight(1f).graphicsLayer { compositingStrategy = androidx.compose.ui.graphics.CompositingStrategy.Offscreen }
        .drawWithContent {
          drawContent()
          // Fade the last rows into the keypad instead of cutting them off.
          drawRect(androidx.compose.ui.graphics.Brush.verticalGradient(listOf(Color.Black, Color.Transparent), startY = size.height - 18.dp.toPx(), endY = size.height),
            blendMode = androidx.compose.ui.graphics.BlendMode.DstIn)
        }) {
        if (templates.isNotEmpty()) item {
          Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            templates.forEach { t ->
              Text("⚡ ${t.name} · ${Money.compact(t.amount)}", style = T.subhead, color = C.accent,
                modifier = Modifier.clip(CircleShape).background(C.accent.copy(alpha = 0.12f)).clickable {
                  type = TxnType.of(t.type); expr = if (t.amount % 100 == 0L) (t.amount / 100).toString() else "%.2f".format(t.amount / 100.0)
                  payee = t.payee ?: t.name; payeePicked = true; categoryId = t.categoryId
                  t.accountId?.takeIf { id -> accounts.any { it.id == id } }?.let { accountId = it }; toAccountId = t.toAccountId
                }.padding(horizontal = 12.dp, vertical = 7.dp))
            }
          }
        }
        group {
          FieldRow(payee, { payee = it; payeePicked = false }, if (type == TxnType.Transfer) "Note (optional)" else "Payee, e.g. Swiggy")
          // Payee memory: what you've typed before, with its usual category and account.
          val suggestions = if (!payeePicked && type != TxnType.Transfer) PayeeMemory.suggestions(payee, db.transactions, type) else emptyList()
          suggestions.forEach { sg ->
            Divider()
            PRow(sg.payee, leading = { Icon(Sym.of("clock.arrow.circlepath"), null, tint = C.secondary, modifier = Modifier.size(20.dp)) },
              value = sg.categoryId?.let { id -> db.categories.firstOrNull { it.id == id }?.name }, onClick = {
                payee = sg.payee; payeePicked = true
                sg.categoryId?.takeIf { id -> db.categories.any { it.id == id } }?.let { categoryId = it }
                if (accounts.any { it.id == sg.accountId }) accountId = sg.accountId
              })
          }
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
          val accountCards = db.cards.filter { it.accountId == accountId && it.archivedAt == null }
          if (type != TxnType.Income && accountCards.isNotEmpty()) { Divider(); PickerRow("Paid with", listOf("" to "Account") + accountCards.map { it.id to it.title }, cardId ?: "") { cardId = it.ifEmpty { null } } }
          Divider()
          // Payment method chips.
          Row(Modifier.horizontalScroll(rememberScrollState()).padding(10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            PaymentMethod.entries.forEach { m ->
              val on = method == m.id
              Row(Modifier.clip(CircleShape).background(if (on) C.accent else C.fill).clickable { method = if (on) null else m.id; methodTouched = true }
                .padding(horizontal = 12.dp, vertical = 7.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Sym.of(m.icon), null, tint = if (on) Color.White else C.label, modifier = Modifier.size(15.dp))
                Spacer(Modifier.width(6.dp))
                Text(m.label, style = T.subhead, color = if (on) Color.White else C.label, maxLines = 1)
              }
            }
          }
          Divider()
          PRow("Date", onClick = { pickDate = true }) {
            Text(shortDate.format(at.toDate()) + " " + at.toDate().year + ", " + at.time(), style = T.body, color = C.label,
              modifier = Modifier.clip(RoundedCornerShape(8.dp)).background(C.fill).padding(horizontal = 10.dp, vertical = 5.dp))
          }
          Divider()
          Row(Modifier.padding(start = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Sym.of("number"), null, tint = C.secondary, modifier = Modifier.size(18.dp))
            FieldRow(tagText, { tagText = it }, "Tags (goa trip, work)", modifier = Modifier.weight(1f))
          }
          if (type != TxnType.Transfer && trips.isNotEmpty()) {
            Divider()
            PickerRow("Trip", listOf("" to "None") + trips.map { it.id to it.name }, tripId ?: "") { tripId = it.ifEmpty { null }; tripItemId = null; walletId = null }
            tripId?.let { tid ->
              val items = db.tripItems.filter { it.tripId == tid }.sortedBy { it.sortOrder }
              if (items.isNotEmpty()) { Divider(); PickerRow("For", listOf("" to "Not set") + items.map { it.id to it.label }, tripItemId ?: "") { tripItemId = it.ifEmpty { null } } }
              val wallets = db.tripWallets.filter { it.tripId == tid }
              if (type == TxnType.Expense && wallets.isNotEmpty()) {
                Divider(); PickerRow("Paid from", listOf("" to "Account") + wallets.map { it.id to "${it.label} · ${it.currency ?: base}" }, walletId ?: "") { walletId = it.ifEmpty { null } }
              }
            }
          }
          if (type == TxnType.Expense) {
            Divider()
            val r = SplitMath.compute(amount ?: 0, split)
            PRow("Split", value = when {
              split.isEmpty -> "No"
              split.payer == null -> "${split.people.size + if (split.includeMe) 1 else 0} people · yours ${Money.format(r.myShare)}"
              else -> "${db.friends.firstOrNull { it.id == split.payer }?.name ?: "They"} paid · you owe ${Money.format(r.myShare)}"
            }, chevron = true, onClick = { pickSplit = true })
          }
        }
      }
      // Same as iPhone: the keypad sits on its own raised panel and steps aside while the text keyboard is up.
      @OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
      val ime = WindowInsets.isImeVisible
      androidx.compose.animation.AnimatedVisibility(!ime, enter = androidx.compose.animation.slideInVertically { it } + androidx.compose.animation.fadeIn(),
        exit = androidx.compose.animation.slideOutVertically { it } + androidx.compose.animation.fadeOut()) {
        Box(Modifier.fillMaxWidth().shadow(10.dp, RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp), ambientColor = Color.Black.copy(alpha = 0.12f))
          .clip(RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp)).background(C.background).padding(top = 10.dp)) {
          Keypad(expr) { expr = it }
        }
      }
    }
  }

  if (pickCategory) CategoryPickerDialog(if (type == TxnType.Income) "income" else "expense", categoryId, { categoryId = it; pickCategory = false }) { pickCategory = false }
  if (pickSplit) SplitEditorDialog(split, amount ?: 0, onChange = { split = it }) { pickSplit = false }
  if (pickDate) {
    val st = rememberDatePickerState(initialSelectedDateMillis = at + java.util.TimeZone.getDefault().getOffset(at))
    DatePickerDialog({ pickDate = false }, confirmButton = { TextButton({
      st.selectedDateMillis?.let { utc ->
        val d = Instant.ofEpochMilli(utc).atZone(java.time.ZoneOffset.UTC).toLocalDate()
        val t = Instant.ofEpochMilli(at).atZone(zone).toLocalTime()
        at = d.atTime(t).atZone(zone).toInstant().toEpochMilli()
      }; pickDate = false }) { Text("OK") } }) { DatePicker(st) }
  }
  if (allCurrencies) CurrencyPickerDialog("Currency", onDismiss = { allCurrencies = false }) { pickCurrency(it); allCurrencies = false }
  if (rateDialog) AlertDialog({ rateDialog = false }, containerColor = C.card, title = { Text("${Money.symbol} per 1 $currency") },
    text = { Column { Text("Use the rate on your card statement or forex card for an exact match.", style = T.footnote, color = C.secondary)
      OutlinedTextField(rateText, { rateText = it }, singleLine = true, placeholder = { Text("e.g. 83.25") }) } },
    confirmButton = { TextButton({ rateText.toDoubleOrNull()?.takeIf { it > 0 }?.let { rate = it }; rateDialog = false }) { Text("Use") } },
    dismissButton = { TextButton({ rateDialog = false }) { Text("Cancel") } })
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
