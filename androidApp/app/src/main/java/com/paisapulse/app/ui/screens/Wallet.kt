package com.paisapulse.app.ui.screens

import android.graphics.Bitmap
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import com.paisapulse.app.data.*
import com.paisapulse.app.logic.*
import com.paisapulse.app.ui.*

val AccountType.order get() = when (this) { AccountType.Bank -> 0; AccountType.Card -> 1; AccountType.Wallet -> 2; AccountType.Cash -> 3; AccountType.Investment -> 4 }

/** Accounts as a wallet: cards overlap like Apple Wallet; tap one to open it (same as the iPhone app). */
@Composable fun AccountsScreen() {
  val db by Store.db.collectAsState()
  val b = Ledger.balances(db.accounts, db.transactions, db.valuations)
  val active = db.accounts.filter { it.archivedAt == null }.sortedWith(compareBy({ it.kind.order }, { it.sortOrder }))
  val net = Ledger.netWorth(db.accounts, b)
  var menu by remember { mutableStateOf(false) }
  PScreen("Accounts", actions = {
    Box {
      GlassIcon("plus", "Add account") { menu = true }
      DropdownMenu(menu, { menu = false }, modifier = Modifier.background(C.card)) {
        listOf("bank" to "Bank account", "card" to "Credit card", "cash" to "Cash", "wallet" to "Wallet (Paytm, Amazon Pay…)", "investment" to "Investments (Groww, mutual funds)").forEach { (k, l) ->
          DropdownMenuItem({ Text(l, style = T.body) }, { menu = false; Ui.sheet = Sheet.AccountNew(k) }, leadingIcon = { Icon(Sym.of(AccountType.of(k).icon), null) })
        }
        HorizontalDivider(color = C.separator)
        DropdownMenuItem({ Text("Reorder Accounts", style = T.body) }, { menu = false; Ui.sheet = Sheet.Reorder("accounts") }, leadingIcon = { Icon(Sym.of("arrow.up.arrow.down"), null) })
      }
    }
  }) {
    item {
      Column(Modifier.padding(horizontal = 20.dp, vertical = 4.dp)) {
        Text("Net worth", style = T.subhead, color = C.secondary)
        RollingText(Money.format(net, Prefs.hideAmounts), T.amount(36, FontWeight.Bold), if (net < 0) C.expense else C.label)
        Text("Net worth over time", style = T.subhead.copy(fontWeight = FontWeight.Medium), color = C.accent,
          modifier = Modifier.padding(top = 4.dp).combinedClickableCompat({ Ui.push(Route.NetWorth) }, {}))
      }
    }
    if (active.isEmpty()) item { EmptyHint("No accounts", "creditcard.fill", "Add your bank account, card or cash to start.") }
    item {
      Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy((-128).dp)) {
        active.forEachIndexed { i, a ->
          Box(Modifier.zIndex(i.toFloat()).pressScale().shadow(14.dp, RoundedCornerShape(24.dp), ambientColor = Color.Black.copy(alpha = 0.25f))
            .combinedClickableCompat({ Ui.push(Route.AccountDetail(a.id)) }, {})) {
            WalletCard(a, b[a.id] ?: 0, db.cards.filter { it.accountId == a.id && it.archivedAt == null })
          }
        }
      }
    }
    val archived = db.accounts.filter { it.archivedAt != null }
    if (archived.isNotEmpty()) group("Archived") { archived.forEachIndexed { i, a -> if (i > 0) Divider(64.dp); AccountRow(a, b[a.id] ?: 0) } }
  }
}

/** An account drawn as a card: gradient in its colour, balance, and a peek of its linked cards. */
@Composable fun WalletCard(a: Account, balance: Long, cards: List<PaymentCard>) {
  val base = hex(a.color)
  val primary = cards.firstOrNull { it.kind == "credit" } ?: cards.firstOrNull()
  Box(Modifier.fillMaxWidth().height(200.dp).clip(RoundedCornerShape(24.dp))
    .background(Brush.linearGradient(listOf(base, lerp(base, Color.Black, 0.35f))))
    .drawBehind {
      drawCircle(Color.White.copy(alpha = 0.10f), 130.dp.toPx(), Offset(size.width - 20.dp.toPx(), -20.dp.toPx()))
      drawCircle(Color.White.copy(alpha = 0.06f), 100.dp.toPx(), Offset(40.dp.toPx(), size.height + 10.dp.toPx()))
    }.padding(18.dp)) {
    Column(Modifier.fillMaxSize()) {
      Row(verticalAlignment = Alignment.Top) {
        Box(Modifier.size(34.dp).clip(RoundedCornerShape(10.dp)).background(Color.White.copy(alpha = 0.18f)), contentAlignment = Alignment.Center) {
          Icon(Sym.of(a.icon), null, tint = Color.White, modifier = Modifier.size(19.dp))
        }
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
          Text(a.name, style = T.headline, color = Color.White, maxLines = 1)
          Text(a.institution ?: a.kind.label, style = T.caption, color = Color.White.copy(alpha = 0.75f), maxLines = 1)
        }
        primary?.let { NetworkMark(it.network) }
      }
      Spacer(Modifier.weight(1f))
      Text(if (balance < 0) (if (a.kind == AccountType.Card) "Due" else "Overdrawn") else "Balance", style = T.caption, color = Color.White.copy(alpha = 0.75f))
      RollingText(Money.format(balance, Prefs.hideAmounts), T.amount(28, FontWeight.Bold), Color.White)
      Row(verticalAlignment = Alignment.CenterVertically) {
        (a.last4 ?: primary?.last4)?.let { Text("•••• $it", style = T.subhead.copy(fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Medium), color = Color.White.copy(alpha = 0.85f)) }
        Spacer(Modifier.weight(1f))
        if (a.kind != AccountType.Card && cards.isNotEmpty()) {
          Row(horizontalArrangement = Arrangement.spacedBy((-10).dp)) {
            cards.take(3).forEach { c -> Box(Modifier.size(30.dp, 20.dp).clip(RoundedCornerShape(4.dp)).background(lerp(hex(c.color ?: a.color), Color.White, 0.25f))
              .border(1.dp, Color.White.copy(alpha = 0.6f), RoundedCornerShape(4.dp))) }
          }
          Spacer(Modifier.width(6.dp))
          Text("${cards.size} card${if (cards.size == 1) "" else "s"}", style = T.caption.copy(fontWeight = FontWeight.SemiBold), color = Color.White.copy(alpha = 0.85f))
        }
        val limit = a.creditLimit
        if (a.kind == AccountType.Card && limit != null && limit > 0)
          Text("${(maxOf(0L, -balance) * 100 / limit)}% used", style = T.caption.copy(fontWeight = FontWeight.SemiBold), color = Color.White.copy(alpha = 0.85f))
      }
    }
  }
}

@Composable fun NetworkMark(network: String) {
  when (network) {
    "mastercard" -> Row(horizontalArrangement = Arrangement.spacedBy((-8).dp)) {
      Box(Modifier.size(22.dp).clip(CircleShape).background(hex("#EB001B"))); Box(Modifier.size(22.dp).clip(CircleShape).background(hex("#F79E1B").copy(alpha = 0.9f)))
    }
    "visa" -> Text("VISA", color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Black, fontStyle = FontStyle.Italic)
    "rupay" -> Text("RuPay", color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.Black, fontStyle = FontStyle.Italic)
    "amex" -> Text("AMEX", color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Black, modifier = Modifier.clip(RoundedCornerShape(4.dp)).background(Color.White.copy(alpha = 0.2f)).padding(horizontal = 5.dp))
    else -> Text(CardNumber.networkName(network).uppercase(), color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Bold)
  }
}

@Composable fun PaymentCardFace(c: PaymentCard, accountColor: String) {
  val base = hex(c.color ?: accountColor)
  Box(Modifier.fillMaxWidth().height(170.dp).clip(RoundedCornerShape(18.dp))
    .background(Brush.linearGradient(listOf(lerp(base, Color.White, 0.12f), lerp(base, Color.Black, 0.3f)))).padding(16.dp)) {
    Box(Modifier.offset(y = 36.dp).size(38.dp, 28.dp).clip(RoundedCornerShape(5.dp)).background(Brush.verticalGradient(listOf(hex("#E8C77A"), hex("#B8913F")))))
    Column(Modifier.fillMaxSize()) {
      Row(verticalAlignment = Alignment.CenterVertically) {
        Text(if (c.kind == "credit") "CREDIT" else "DEBIT", style = T.caption2.copy(fontWeight = FontWeight.Bold, letterSpacing = 1.5.sp), color = Color.White.copy(alpha = 0.8f))
        Spacer(Modifier.weight(1f)); NetworkMark(c.network)
      }
      Spacer(Modifier.weight(1f))
      Text("••••  ••••  ••••  ${c.last4}", style = T.body.copy(fontFamily = FontFamily.Monospace, fontWeight = FontWeight.SemiBold), color = Color.White)
      Row {
        Text(c.nameOnCard ?: c.label ?: "", style = T.caption.copy(fontWeight = FontWeight.Medium), color = Color.White.copy(alpha = 0.85f), maxLines = 1, modifier = Modifier.weight(1f))
        c.expiryText?.let { Text(it, style = T.caption, color = Color.White.copy(alpha = 0.85f)) }
      }
    }
  }
}

/** Linked cards as a fanned stack; tap to spread them, tap again to edit. Long-press removes. */
@OptIn(ExperimentalFoundationApi::class)
@Composable fun CardStack(cards: List<PaymentCard>, accountColor: String, onEdit: (PaymentCard) -> Unit) {
  var spread by remember { mutableStateOf(false) }
  val haptics = LocalHapticFeedback.current
  val gap by animateDpAsState(if (spread) 12.dp else (-150).dp, spring(dampingRatio = 0.8f, stiffness = Spring.StiffnessLow), label = "stack")
  var confirm by remember { mutableStateOf<PaymentCard?>(null) }
  Column(verticalArrangement = Arrangement.spacedBy(gap)) {
    cards.forEachIndexed { i, c ->
      val sc by animateFloatAsState(if (spread) 1f else 1f - (cards.size - 1 - i) * 0.04f, label = "sc")
      Box(Modifier.zIndex(i.toFloat()).scale(sc).shadow(8.dp, RoundedCornerShape(18.dp))
        .combinedClickable(onClick = { haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove); if (spread) onEdit(c) else spread = true },
          onLongClick = { confirm = c })) { PaymentCardFace(c, accountColor) }
    }
    if (spread && cards.size > 1) TextButton({ spread = false }) { Text("Stack cards", color = C.accent) }
  }
  confirm?.let { c ->
    AlertDialog({ confirm = null }, containerColor = C.card, title = { Text("Remove ${c.title}?") },
      confirmButton = { TextButton({ Store.update { d -> d.copy(cards = d.cards.map { if (it.id == c.id) it.copy(archivedAt = now()) else it }) }; confirm = null }) { Text("Remove", color = C.expense) } },
      dismissButton = { TextButton({ onEdit(c); confirm = null }) { Text("Edit") } })
  }
}

/** Add or edit a card: scan with the camera (on-device text recognition) or type it in. Last 4 + network + expiry only. */
@Composable fun CardFormSheet(accountId: String, id: String?) {
  val ctx = LocalContext.current
  val db = Store.value
  val account = db.accounts.firstOrNull { it.id == accountId } ?: return
  val card = id?.let { i -> db.cards.firstOrNull { it.id == i } }
  val kind = if (account.kind == AccountType.Card) "credit" else "debit"
  var network by remember { mutableStateOf(card?.network ?: "visa") }
  var last4 by remember { mutableStateOf(card?.last4 ?: "") }
  var month by remember { mutableIntStateOf(card?.expiryMonth ?: 0) }
  var year by remember { mutableIntStateOf(card?.expiryYear ?: 0) }
  var name by remember { mutableStateOf(card?.nameOnCard ?: "") }
  var label by remember { mutableStateOf(card?.label ?: "") }
  var color by remember { mutableStateOf(card?.color ?: "") }
  var scanning by remember { mutableStateOf(false) }
  var markupOn by remember { mutableStateOf(card?.forexMarkupBps != null) }
  var markupGst by remember { mutableStateOf(true) }
  var markupPercent by remember { mutableDoubleStateOf(card?.forexMarkupBps?.let { Math.round(it / 1.18 / 25.0) * 0.25 } ?: 3.5) }
  val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicturePreview()) { bmp: Bitmap? ->
    bmp ?: return@rememberLauncherForActivityResult
    scanning = true
    TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS).process(InputImage.fromBitmap(bmp, 0))
      .addOnSuccessListener { r ->
        val s = CardNumber.parse(r.textBlocks.flatMap { b -> b.lines.map { it.text } })
        if (s == null) Ui.show("Couldn't read a card number. Try again in good light, or type it.") else {
          network = s.network; last4 = s.last4; s.month?.let { month = it }; s.year?.let { year = it }; s.name?.let { name = it }
        }
        scanning = false
      }.addOnFailureListener { scanning = false; Ui.show("Couldn't read the photo") }
  }
  val valid = last4.length == 4 && last4.all { it.isDigit() }
  val preview = PaymentCard(accountId = accountId, kind = kind, network = network, last4 = last4.ifEmpty { "0000" }, expiryMonth = month.takeIf { it > 0 },
    expiryYear = year.takeIf { it > 0 }, nameOnCard = name.ifBlank { null }?.uppercase(), label = label.ifBlank { null }, color = color.ifBlank { null })
  PSheet({ Ui.sheet = null }) {
    SheetHeader(if (card == null) (if (kind == "credit") "Card Details" else "Add Debit Card") else "Edit Card", valid, onCancel = { Ui.sheet = null }, onSave = {
      val c = (card ?: PaymentCard(accountId = accountId, last4 = last4)).copy(kind = kind, network = network, last4 = last4, expiryMonth = month.takeIf { it > 0 },
        expiryYear = year.takeIf { it > 0 }, nameOnCard = name.ifBlank { null }?.uppercase(), label = label.ifBlank { null }, color = color.ifBlank { null },
        forexMarkupBps = if (markupOn) ForexMarkup.bps(markupPercent, markupGst) else null)
      Store.update { d -> d.copy(cards = if (card == null) d.cards + c else d.cards.map { if (it.id == c.id) c else it },
        accounts = if (account.kind == AccountType.Card && account.last4 == null) d.accounts.map { if (it.id == account.id) it.copy(last4 = last4) else it } else d.accounts) }
      Ui.sheet = null
    })
    LazyColumn(Modifier.fillMaxHeight(0.9f).imePadding(), contentPadding = PaddingValues(bottom = 40.dp)) {
      item { Box(Modifier.padding(16.dp)) { PaymentCardFace(preview, account.color) } }
      group(footer = "Take a photo of the card. The full number is read once on this phone to check it, then only the last 4 digits are kept.") {
        PRow(if (scanning) "Reading…" else "Scan with Camera", titleColor = C.accent, leading = { Icon2("camera.fill") }, onClick = { if (!scanning) camera.launch(null) })
      }
      group("Card") {
        PickerRow("Network", CardNumber.networks.map { it to CardNumber.networkName(it) }, network) { network = it }
        Divider(); FieldRow(last4, { v -> last4 = v.filter { it.isDigit() }.take(4) }, "Last 4 digits", number = true)
        Divider(); PickerRow("Expiry month", listOf(0 to "Not set") + (1..12).map { it to "%02d".format(it) }, month) { month = it }
        val y0 = java.time.LocalDate.now().year
        Divider(); PickerRow("Expiry year", listOf(0 to "Not set") + (y0..y0 + 12).map { it to "$it" }, year) { year = it }
        Divider(); FieldRow(name, { name = it }, "Name on card (optional)")
        Divider(); FieldRow(label, { label = it }, "Nickname (optional), e.g. MyZone Debit")
      }
      group("Spending abroad", footer = "Most Indian cards add 2–3.5% plus GST on foreign spends. It's added automatically when you pay in another currency with this card. Check your card's fee page and edit it any time.") {
        ToggleRow("Foreign currency markup", markupOn) { markupOn = it }
        if (markupOn) {
          Divider()
          PRow("Markup", trailing = {
            Row(verticalAlignment = Alignment.CenterVertically) {
              Text("−", style = T.title3, color = C.accent, modifier = Modifier.clickable { markupPercent = maxOf(0.0, markupPercent - 0.25) }.padding(horizontal = 12.dp))
              Text("%.2f%%".format(markupPercent), style = T.headline, color = C.label)
              Text("+", style = T.title3, color = C.accent, modifier = Modifier.clickable { markupPercent = minOf(10.0, markupPercent + 0.25) }.padding(horizontal = 12.dp))
            }
          })
          Divider(); ToggleRow("Plus 18% GST on the markup", markupGst) { markupGst = it }
          Divider(); PRow("You pay extra", value = ForexMarkup.label(ForexMarkup.bps(markupPercent, markupGst)))
        }
      }
      group("Colour") { ColorRow(color) { color = it }; if (color.isNotEmpty()) { Divider(); PRow("Use the account's colour", titleColor = C.accent, onClick = { color = "" }) } }
      if (card != null) group { PRow("Remove Card", titleColor = C.expense, onClick = {
        Store.update { d -> d.copy(cards = d.cards.map { if (it.id == card.id) it.copy(archivedAt = now()) else it }) }; Ui.sheet = null }) }
    }
  }
}
