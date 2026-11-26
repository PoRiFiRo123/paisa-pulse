package com.paisapulse.app.ui.screens

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.provider.ContactsContract
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.FileProvider
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter
import com.paisapulse.app.data.*
import com.paisapulse.app.logic.*
import com.paisapulse.app.ui.*
import com.paisapulse.app.work.Services
import java.io.File

// Split v2, mirroring the iPhone SplitsV2.swift: contacts, who paid, equal / amounts / shares, groups,
// requests by SMS + QR + pay link, "Pay with…" a UPI app and "Did it go through?".

private val avatarColors = listOf("#5E5CE6", "#FF9500", "#34C759", "#FF2D55", "#007AFF", "#AF52DE", "#30B0C7", "#E5484D")
fun avatarColor(name: String): String = avatarColors[Math.abs(name.fold(0) { h, c -> h * 31 + c.code }) % avatarColors.size]

@Composable fun Avatar(name: String, size: Dp = 34.dp) {
  val c = hex(avatarColor(name))
  Box(Modifier.size(size).clip(CircleShape).background(Brush.verticalGradient(listOf(c.copy(alpha = 0.9f), c))), contentAlignment = Alignment.Center) {
    Text(name.take(1).uppercase(), style = T.headline.copy(fontSize = androidx.compose.ui.unit.TextUnit(size.value * 0.45f, androidx.compose.ui.unit.TextUnitType.Sp)), color = Color.White)
  }
}

fun qrBitmap(text: String, size: Int = 640): Bitmap {
  val m = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, size, size, mapOf(com.google.zxing.EncodeHintType.MARGIN to 1))
  val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.RGB_565)
  for (x in 0 until size) for (y in 0 until size) bmp.setPixel(x, y, if (m[x, y]) android.graphics.Color.BLACK else android.graphics.Color.WHITE)
  return bmp
}

/** Picks one contact (name + number) through the system picker; no Contacts permission needed. */
@Composable fun rememberContactPicker(onPick: (String, String?) -> Unit): () -> Unit {
  val ctx = LocalContext.current
  val launcher = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { r ->
    val uri = r.data?.data ?: return@rememberLauncherForActivityResult
    if (r.resultCode != Activity.RESULT_OK) return@rememberLauncherForActivityResult
    runCatching {
      ctx.contentResolver.query(uri, arrayOf(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME, ContactsContract.CommonDataKinds.Phone.NUMBER), null, null, null)?.use { c ->
        if (c.moveToFirst()) onPick(c.getString(0) ?: "Friend", c.getString(1))
      }
    }
  }
  return { runCatching { launcher.launch(Intent(Intent.ACTION_PICK, ContactsContract.CommonDataKinds.Phone.CONTENT_URI)) }.onFailure { Ui.show("No contacts app found") } }
}

fun addFriendFromContact(name: String, phone: String?): String {
  val existing = Store.value.friends.firstOrNull { it.name.equals(name, ignoreCase = true) }
  if (existing != null) {
    if (existing.phone == null && phone != null) Store.update { d -> d.copy(friends = d.friends.map { if (it.id == existing.id) it.copy(phone = phone) else it }) }
    return existing.id
  }
  val f = Friend(name = name, phone = phone)
  Store.update { it.copy(friends = it.friends + f) }
  return f.id
}

fun sendSms(ctx: Context, phones: List<String>, body: String) {
  val i = if (phones.isNotEmpty()) Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:" + phones.joinToString(";") { Uri.encode(it) })).putExtra("sms_body", body)
    else Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, body), "Send request")
  runCatching { ctx.startActivity(i) }.onFailure { ctx.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, body), "Send request")) }
}

fun shareBitmap(ctx: Context, bmp: Bitmap, title: String, name: String = "upi-qr.png") {
  val dir = File(ctx.cacheDir, "share").apply { mkdirs() }
  val f = File(dir, name).apply { outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) } }
  val uri = FileProvider.getUriForFile(ctx, "com.paisapulse.app.files", f)
  ctx.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("image/png").putExtra(Intent.EXTRA_STREAM, uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION), title))
}

// MARK: Split editor (full screen over Quick Add)

@Composable fun SplitEditorDialog(setup: SplitSetup, total: Long, onChange: (SplitSetup) -> Unit, onDismiss: () -> Unit) {
  val db by Store.db.collectAsState()
  var s by remember { mutableStateOf(setup) }
  fun set(n: SplitSetup) { s = n; onChange(n) }
  var addingName by remember { mutableStateOf(false) }
  var savingGroup by remember { mutableStateOf(false) }
  var payerMenu by remember { mutableStateOf(false) }
  val pickContact = rememberContactPicker { name, phone -> val id = addFriendFromContact(name, phone); if (id !in s.people) set(s.copy(people = s.people + id)) }
  val used = db.splitEntries.groupingBy { it.friendId }.eachCount()
  val ordered = db.friends.sortedWith(compareByDescending<Friend> { used[it.id] ?: 0 }.thenBy { it.name })
  val r = SplitMath.compute(total, s)
  fun name(id: String) = db.friends.firstOrNull { it.id == id }?.name ?: "Friend"

  Dialog(onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
    Box(Modifier.fillMaxSize().background(C.background)) {
      PScreen("Split", large = false, leading = { GlassIcon("chevron.left", "Done") { onDismiss() } }, actions = {
        if (!s.isEmpty) Text("Clear", style = T.body, color = C.expense, modifier = Modifier.glass(CircleShape).combinedClickableCompat({ set(SplitSetup()) }, {}).padding(horizontal = 16.dp, vertical = 11.dp))
      }, bottomInset = 40.dp) {
        if (db.splitGroups.isNotEmpty()) item {
          Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            db.splitGroups.forEach { g ->
              val on = s.groupId == g.id
              Text("👥 ${g.name}", style = T.subhead.copy(fontWeight = FontWeight.Medium), color = if (on) Color.White else C.label,
                modifier = Modifier.clip(CircleShape).background(if (on) C.accent else C.fill)
                  .combinedClickableCompat({ set(if (on) s.copy(groupId = null) else s.copy(groupId = g.id, people = g.memberIds.filter { id -> db.friends.any { it.id == id } })) }, {})
                  .padding(horizontal = 12.dp, vertical = 7.dp))
            }
          }
        }
        group("With") {
          ordered.forEachIndexed { i, f ->
            if (i > 0) Divider(64.dp)
            val on = f.id in s.people
            PRow(f.name, leading = {
              Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Sym.of(if (on) "checkmark.circle.fill" else "circle"), null, tint = if (on) C.accent else C.tertiary, modifier = Modifier.size(24.dp))
                Spacer(Modifier.width(10.dp)); Avatar(f.name, 30.dp)
              }
            }, value = if (on && total > 0) Money.format(r.shares[f.id] ?: 0) else null,
              onClick = { set(if (on) s.copy(people = s.people - f.id, payer = if (s.payer == f.id) null else s.payer) else s.copy(people = s.people + f.id)) })
          }
          if (ordered.isNotEmpty()) Divider()
          PRow("Add from Contacts", titleColor = C.accent, leading = { Icon2("person.badge.plus") }, onClick = pickContact)
          Divider(56.dp); PRow("Add by Name", titleColor = C.accent, leading = { Icon2("pencil") }, onClick = { addingName = true })
        }
        if (!s.isEmpty) {
          group {
            Box {
              PRow("Paid by", onClick = { payerMenu = true }) { Text(s.payer?.let(::name) ?: "You", style = T.body, color = C.accent) }
              DropdownMenu(payerMenu, { payerMenu = false }, modifier = Modifier.background(C.card)) {
                DropdownMenuItem({ Text("You", style = T.body) }, { payerMenu = false; set(s.copy(payer = null)) })
                s.people.forEach { id -> DropdownMenuItem({ Text(name(id), style = T.body) }, { payerMenu = false; set(s.copy(payer = id)) }) }
              }
            }
            Divider(); ToggleRow("Include me", s.includeMe) { set(s.copy(includeMe = it)) }
            Divider()
            Segmented(SplitMode.entries.map { it.label }, s.mode.ordinal, Modifier.padding(12.dp)) { set(s.copy(mode = SplitMode.entries[it])) }
          }
          if (s.mode != SplitMode.Equal) group(footer = when {
            s.mode == SplitMode.Amount && r.unassigned > 0 -> "${Money.format(r.unassigned)} left to assign"
            s.mode == SplitMode.Amount && r.unassigned < 0 -> "${Money.format(-r.unassigned)} more than the total"
            s.mode == SplitMode.Shares -> "Shares like 2 : 1 for someone who had twice as much."
            else -> null
          }) {
            val keys = (if (s.includeMe) listOf("me") else emptyList()) + s.people
            keys.forEachIndexed { i, k ->
              if (i > 0) Divider()
              var text by remember(k, s.mode) {
                mutableStateOf(s.values[k]?.let { v -> if (s.mode == SplitMode.Amount) (if (v % 100 == 0L) (v / 100).toString() else "%.2f".format(v / 100.0)) else v.toString() } ?: "")
              }
              PRow(if (k == "me") "You" else name(k)) {
                OutlinedTextField(text, { t -> text = t; set(s.copy(values = s.values + (k to (if (s.mode == SplitMode.Amount) Money.parse(t) ?: 0L else t.toLongOrNull() ?: 0L)))) },
                  singleLine = true, modifier = Modifier.width(120.dp), placeholder = { Text(if (s.mode == SplitMode.Amount) "₹0" else "1") },
                  keyboardOptions = KeyboardOptions(keyboardType = if (s.mode == SplitMode.Amount) KeyboardType.Decimal else KeyboardType.Number),
                  textStyle = T.body.copy(textAlign = TextAlign.End))
                if (s.mode == SplitMode.Shares && total > 0) Text(Money.format(r.shares[k] ?: 0), style = T.caption, color = C.secondary, modifier = Modifier.padding(start = 8.dp).width(64.dp))
              }
            }
          }
          group(footer = if (s.payer == null) "Only your share counts in your spending. After saving you can send everyone a request."
            else "Nothing leaves your account now. Settle up from Splits when you pay them back.") {
            PRow("Your share", value = Money.format(r.myShare))
            Divider()
            if (s.payer != null) PRow("You'll owe ${name(s.payer!!)}", value = Money.format(r.myShare))
            else PRow("They'll owe you", value = Money.format(r.entries.values.sum()))
            if (s.groupId == null) { Divider(); PRow("Save These People as a Group", titleColor = C.accent, leading = { Icon2("person.2.fill") }, onClick = { savingGroup = true }) }
          }
        }
      }
    }
  }
  if (addingName) NameDialog("Add person", "Name", onDismiss = { addingName = false }) { n ->
    val f = Friend(name = n); Store.update { it.copy(friends = it.friends + f) }; set(s.copy(people = s.people + f.id)); addingName = false
  }
  if (savingGroup) NameDialog("Name this group", "Flatmates, Goa trip…", onDismiss = { savingGroup = false }) { n ->
    val g = SplitGroup(name = n, memberIds = s.people); Store.update { it.copy(splitGroups = it.splitGroups + g) }; set(s.copy(groupId = g.id)); savingGroup = false
  }
}

@Composable fun NameDialog(title: String, hint: String, initial: String = "", keyboard: KeyboardType = KeyboardType.Text, onDismiss: () -> Unit, onSave: (String) -> Unit) {
  var t by remember { mutableStateOf(initial) }
  AlertDialog(onDismissRequest = onDismiss, containerColor = C.card, title = { Text(title, style = T.headline, color = C.label) },
    text = { OutlinedTextField(t, { t = it }, singleLine = true, placeholder = { Text(hint) }, keyboardOptions = KeyboardOptions(keyboardType = keyboard)) },
    confirmButton = { TextButton({ t.trim().takeIf { it.isNotEmpty() }?.let(onSave) }) { Text("Save", color = C.accent, style = T.headline) } },
    dismissButton = { TextButton(onDismiss) { Text("Cancel", color = C.accent, style = T.body) } })
}

// MARK: Request

@Composable fun RequestSheet(note: String?, amounts: Map<String, Long>) {
  val ctx = LocalContext.current
  val db by Store.db.collectAsState()
  val people = db.friends.filter { (amounts[it.id] ?: 0) > 0 }
  var upiDraft by remember { mutableStateOf("") }
  var qrFor by remember { mutableStateOf<Friend?>(null) }
  val me = Prefs.myName.ifBlank { "me" }
  PSheet({ Ui.sheet = null }) {
    SheetHeader("Ask to Pay", saveLabel = "Done", onCancel = { Ui.sheet = null }) { Ui.sheet = null }
    androidx.compose.foundation.lazy.LazyColumn(Modifier.fillMaxWidth().padding(bottom = 24.dp)) {
      if (Prefs.myUpiId.isBlank()) group(footer = "Your UPI ID goes into the request so friends can pay you from any UPI app. It stays on this phone.") {
        Row(Modifier.padding(horizontal = 16.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
          Box(Modifier.weight(1f)) { FieldRow(upiDraft, { upiDraft = it }, "Your UPI ID, e.g. you@okaxis") }
          Text("Save", style = T.headline, color = if ("@" in upiDraft) C.accent else C.tertiary,
            modifier = Modifier.combinedClickableCompat({ if ("@" in upiDraft) Prefs.set("myUpiId", upiDraft.trim()) }, {}).padding(8.dp))
        }
      }
      group(note?.let { "Split: $it" } ?: "Split", footer = "The message has a link to a simple pay page (details only in the link) with a QR code and a Pay button.") {
        people.forEachIndexed { i, f ->
          if (i > 0) Divider(64.dp)
          val amount = amounts[f.id] ?: 0
          PRow(f.name, subtitle = "owes ${Money.format(amount)}", leading = { Avatar(f.name) }) {
            if (Prefs.myUpiId.isNotBlank()) {
              GlassIcon("qrcode", "Show QR code") { qrFor = f }
              Spacer(Modifier.width(8.dp))
              Box(Modifier.size(44.dp).clip(CircleShape).background(C.accent).combinedClickableCompat({
                sendSms(ctx, listOfNotNull(f.phone), SplitMath.requestMessage(f.name, amount, note, Prefs.myUpiId, me))
              }, {}), contentAlignment = Alignment.Center) { Icon(Sym.of("message.fill"), "Send by SMS", tint = Color.White, modifier = Modifier.size(20.dp)) }
            }
          }
        }
      }
      if (people.size > 1 && Prefs.myUpiId.isNotBlank()) group {
        PRow("Message Everyone", titleColor = C.accent, leading = { Icon2("person.2.fill") }, onClick = {
          val lines = people.joinToString("\n") { "${it.name}: ${Money.format(amounts[it.id] ?: 0)}" }
          val each = amounts[people.first().id] ?: 0
          sendSms(ctx, people.mapNotNull { it.phone }, "Split${note?.let { " for $it" } ?: ""}:\n$lines\nTotal ${Money.format(people.sumOf { amounts[it.id] ?: 0 })}. Pay me on UPI: ${SplitMath.payPageUrl(Prefs.myUpiId, me, each, note)}")
        })
      }
    }
  }
  qrFor?.let { f -> QRDialog("${f.name} pays you", amounts[f.id] ?: 0, SplitMath.upiUri(Prefs.myUpiId, me, amounts[f.id] ?: 0, note)) { qrFor = null } }
}

@Composable fun QRDialog(title: String, amount: Long, upi: String, onDismiss: () -> Unit) {
  val ctx = LocalContext.current
  val bmp = remember(upi) { qrBitmap(upi) }
  AlertDialog(onDismissRequest = onDismiss, containerColor = C.card,
    title = { Text(title, style = T.headline, color = C.label, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center) },
    text = {
      Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(Money.format(amount), style = T.amount(36, FontWeight.Bold), color = C.label)
        Image(bmp.asImageBitmap(), "UPI QR code", Modifier.padding(top = 12.dp).size(230.dp).clip(RoundedCornerShape(16.dp)).background(Color.White).padding(8.dp))
        Text("Scan with any UPI app", style = T.footnote, color = C.secondary, modifier = Modifier.padding(top = 8.dp))
      }
    },
    confirmButton = { TextButton({ shareBitmap(ctx, bmp, "Share QR") }) { Text("Share QR", color = C.accent, style = T.headline) } },
    dismissButton = { TextButton(onDismiss) { Text("Done", color = C.accent, style = T.body) } })
}

// MARK: Splits home, person, group

@Composable fun SplitsScreen() {
  val db by Store.db.collectAsState()
  val b = Splits.balances(db.splitEntries)
  var adding by remember { mutableStateOf(false) }
  val pickContact = rememberContactPicker { name, phone -> addFriendFromContact(name, phone) }
  var upi by remember { mutableStateOf(Prefs.myUpiId) }
  var me by remember { mutableStateOf(Prefs.myName) }
  DisposableEffect(Unit) { onDispose { Prefs.set("myUpiId", upi.trim()); Prefs.set("myName", me.trim()) } }
  PScreen("Splits", back = true, actions = { GlassIcon("person.badge.plus", "Add person") { adding = true } }) {
    group(footer = "Split an expense from Quick Add › Split. Your share is what counts in your spending.") {
      SummaryCells("You're owed" to (b.values.filter { it > 0 }.sum() to C.income), "You owe" to (-b.values.filter { it < 0 }.sum() to C.expense))
    }
    group("Groups") {
      db.splitGroups.forEachIndexed { i, g ->
        if (i > 0) Divider(64.dp)
        PRow(g.name, subtitle = g.memberIds.mapNotNull { id -> db.friends.firstOrNull { it.id == id }?.name }.joinToString(", "),
          leading = { CategoryBadge("person.2.fill", "#5E5CE6", 34.dp) }, chevron = true, onClick = { Ui.push(Route.Group(g.id)) })
      }
      if (db.splitGroups.isNotEmpty()) Divider()
      PRow("New Group", titleColor = C.accent, leading = { Icon2("plus") }, onClick = { Ui.sheet = Sheet.GroupForm(null) })
    }
    group("People") {
      if (db.friends.isEmpty()) PRow("Add the people you split with", titleColor = C.secondary)
      db.friends.sortedBy { it.name }.forEachIndexed { i, f ->
        if (i > 0) Divider(64.dp)
        PRow(f.name, leading = { Avatar(f.name) }, chevron = true, onClick = { Ui.push(Route.Friend(f.id)) }) { BalanceLabel(b[f.id] ?: 0) }
      }
      Divider()
      PRow("Add from Contacts", titleColor = C.accent, leading = { Icon2("person.badge.plus") }, onClick = pickContact)
    }
    group("For requests", footer = "Requests include a link to a pay page and a QR code for this UPI ID. It stays on this phone.") {
      FieldRow(me, { me = it }, "Your name")
      Divider(); FieldRow(upi, { upi = it }, "Your UPI ID, e.g. you@okaxis")
    }
  }
  if (adding) NameDialog("Add person", "Name", onDismiss = { adding = false }) { n -> Store.update { it.copy(friends = it.friends + Friend(name = n)) }; adding = false }
}

@Composable fun BalanceLabel(bal: Long) {
  if (bal == 0L) Text("settled", style = T.subhead, color = C.secondary)
  else Column(horizontalAlignment = Alignment.End) {
    Text(Money.format(bal), style = T.amount(17), color = if (bal > 0) C.income else C.expense)
    Text(if (bal > 0) "owes you" else "you owe", style = T.caption2, color = C.secondary)
  }
}

@Composable fun FriendScreen(id: String, groupId: String? = null) {
  val ctx = LocalContext.current
  val db by Store.db.collectAsState()
  val f = db.friends.firstOrNull { it.id == id } ?: run { LaunchedEffect(Unit) { Ui.pop() }; return }
  val mine = db.splitEntries.filter { it.friendId == id && (groupId == null || it.groupId == groupId) }.sortedByDescending { it.occurredAt }
  val bal = mine.sumOf { it.amount }
  var upi by remember { mutableStateOf(f.upiId ?: "") }
  var phone by remember { mutableStateOf(f.phone ?: "") }
  var manual by remember { mutableIntStateOf(0) }
  var paying by remember { mutableStateOf<Long?>(null) }
  var askPaid by remember { mutableStateOf(false) }
  DisposableEffect(Unit) { onDispose { Store.update { d -> d.copy(friends = d.friends.map { if (it.id == id) it.copy(upiId = upi.trim().ifBlank { null }, phone = phone.trim().ifBlank { null }) else it }) } } }
  val owner = LocalLifecycleOwner.current
  DisposableEffect(owner) {
    val obs = LifecycleEventObserver { _, e -> if (e == Lifecycle.Event.ON_RESUME && paying != null) askPaid = true }
    owner.lifecycle.addObserver(obs); onDispose { owner.lifecycle.removeObserver(obs) }
  }
  PScreen(f.name, back = true) {
    group {
      Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Avatar(f.name, 56.dp)
        Text(if (bal == 0L) "All settled" else if (bal > 0) "${f.name} owes you" else "You owe ${f.name}", style = T.subhead, color = C.secondary, modifier = Modifier.padding(top = 6.dp))
        RollingText(Money.format(bal), T.amount(40, FontWeight.Bold), if (bal > 0) C.income else if (bal < 0) C.expense else C.label)
      }
      if (bal > 0) { Divider(); PRow("Ask ${f.name} to Pay", titleColor = C.accent, leading = { Icon2("paperplane.fill") }, onClick = { Ui.sheet = Sheet.Request(null, mapOf(id to bal)) }) }
      if (bal < 0 && upi.isNotBlank()) { Divider(); PRow("Pay ${Money.format(-bal)} with…", titleColor = C.accent, leading = { Icon2("indianrupeesign.circle") }, onClick = {
        val i = Intent(Intent.ACTION_VIEW, Uri.parse(SplitMath.upiUri(upi.trim(), f.name, -bal, "Settle up")))
        runCatching { ctx.startActivity(Intent.createChooser(i, "Pay with…")); paying = -bal }.onFailure { Ui.show("No UPI app found") }
      }) }
      if (bal != 0L) { Divider(); PRow("Mark as Settled", titleColor = C.accent, leading = { Icon2("checkmark.circle") }, onClick = {
        val e = SplitEntry(friendId = id, amount = -bal, note = "Settled up", groupId = groupId)
        Store.update { it.copy(splitEntries = it.splitEntries + e) }
        Ui.show("Settled") { Store.update { d -> d.copy(splitEntries = d.splitEntries.filterNot { it.id == e.id }) } }
      }) }
    }
    group(footer = "For money that isn't a split expense, like cash they handed you.") {
      PRow("They Owe Me…", titleColor = C.accent, leading = { Icon2("arrow.down.left") }, onClick = { manual = 1 })
      Divider(56.dp); PRow("I Owe Them…", titleColor = C.accent, leading = { Icon2("arrow.up.right") }, onClick = { manual = -1 })
    }
    group("Paisa Pulse", footer = if (f.userId != null) "Splits with ${f.name} show up on their phone, and theirs on yours." else "Linked friends see shared splits on their phone and confirm their share.") {
      FriendAccountGroupContent(f)
    }
    group(footer = "UPI ID lets you pay them from any UPI app; phone fills in the SMS when you send a request.") {
      FieldRow(upi, { upi = it }, "UPI ID, e.g. name@okaxis")
      Divider(); FieldRow(phone, { phone = it }, "Phone (for SMS)", number = true)
    }
    group("History") {
      if (mine.isEmpty()) PRow("Nothing yet", titleColor = C.secondary)
      mine.forEachIndexed { i, e ->
        if (i > 0) Divider()
        PRow(e.note ?: if (e.txnId == null) "Settle up" else "Split", subtitle = shortDate.format(e.occurredAt.toDate()) + " · hold to delete",
          onLongClick = { Store.update { d -> d.copy(splitEntries = d.splitEntries.filterNot { it.id == e.id }) } }) {
          Text(Money.format(e.amount), style = T.amount(17), color = if (e.amount > 0) C.income else C.expense)
        }
      }
    }
  }
  if (manual != 0) {
    var amount by remember { mutableStateOf("") }
    var what by remember { mutableStateOf("") }
    AlertDialog(onDismissRequest = { manual = 0 }, containerColor = C.card,
      title = { Text(if (manual > 0) "${f.name} owes you" else "You owe ${f.name}", style = T.headline, color = C.label) },
      text = { Column {
        OutlinedTextField(amount, { amount = it }, singleLine = true, placeholder = { Text("Amount") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal))
        OutlinedTextField(what, { what = it }, singleLine = true, placeholder = { Text("What for (optional)") }, modifier = Modifier.padding(top = 8.dp))
      } },
      confirmButton = { TextButton({
        Money.parse(amount)?.let { p ->
          val sign = manual
          Store.update { it.copy(splitEntries = it.splitEntries + SplitEntry(friendId = id, amount = sign * p, note = what.trim().ifBlank { if (sign > 0) "They owe me" else "I owe them" }, groupId = groupId)) }
        }
        manual = 0
      }) { Text("Add", color = C.accent, style = T.headline) } },
      dismissButton = { TextButton({ manual = 0 }) { Text("Cancel", color = C.accent, style = T.body) } })
  }
  if (askPaid) AlertDialog(onDismissRequest = { askPaid = false; paying = null }, containerColor = C.card,
    title = { Text("Did it go through?", style = T.headline, color = C.label) },
    text = { Text("If the UPI app says it worked, we'll record the payment and settle up.", style = T.body, color = C.secondary) },
    confirmButton = { TextButton({
      val amount = paying ?: 0
      val acc = db.accounts.firstOrNull { it.id == Prefs.lastAccountId && it.archivedAt == null }?.id ?: db.accounts.firstOrNull { it.archivedAt == null }?.id
      Store.update { d -> d.copy(
        transactions = if (acc != null) d.transactions + Txn(type = "expense", amount = amount, accountId = acc, payee = f.name, note = "Settled up", source = "settle") else d.transactions,
        splitEntries = d.splitEntries + SplitEntry(friendId = id, amount = amount, note = "Paid by UPI", groupId = groupId)) }
      Services.refreshWidget(); Ui.show("Settled with ${f.name}")
      askPaid = false; paying = null
    }) { Text("Yes, I Paid", color = C.accent, style = T.headline) } },
    dismissButton = { TextButton({ askPaid = false; paying = null }) { Text("No", color = C.accent, style = T.body) } })
}

@Composable fun GroupScreen(id: String) {
  val db by Store.db.collectAsState()
  val g = db.splitGroups.firstOrNull { it.id == id } ?: run { LaunchedEffect(Unit) { Ui.pop() }; return }
  val mine = db.splitEntries.filter { it.groupId == id }.sortedByDescending { it.occurredAt }
  val b = Splits.balances(mine)
  var menu by remember { mutableStateOf(false) }
  PScreen(g.name, back = true, actions = {
    Box {
      GlassIcon("ellipsis", "More") { menu = true }
      DropdownMenu(menu, { menu = false }, modifier = Modifier.background(C.card)) {
        DropdownMenuItem({ Text("Edit", style = T.body) }, { menu = false; Ui.sheet = Sheet.GroupForm(id) })
        DropdownMenuItem({ Text("Delete Group", style = T.body, color = C.expense) }, { menu = false; Store.update { d -> d.copy(splitGroups = d.splitGroups.filterNot { it.id == id }) }; Ui.pop() })
      }
    }
  }) {
    group { SummaryCells("Owed to you" to (b.values.filter { it > 0 }.sum() to C.income), "You owe" to (-b.values.filter { it < 0 }.sum() to C.expense)) }
    group("Members", footer = "Add a friend, someone new, or someone already on Paisa Pulse (find them by @username, email or phone).") {
      db.friends.filter { it.id in g.memberIds }.forEachIndexed { i, f ->
        if (i > 0) Divider(64.dp)
        PRow(f.name, leading = { Avatar(f.name) }, chevron = true, onClick = { Ui.push(Route.Friend(f.id, id)) }) {
          if (f.userId != null) Icon(Sym.of("person.crop.circle.badge.checkmark"), "On Paisa Pulse", tint = C.secondary, modifier = Modifier.padding(end = 8.dp).size(18.dp))
          BalanceLabel(b[f.id] ?: 0)
        }
      }
      Divider()
      PRow("Add People", titleColor = C.accent, leading = { Icon2("person.badge.plus") }, onClick = { Ui.sheet = Sheet.GroupForm(id) })
    }
    if (b.values.any { it != 0L }) group(footer = "Marks every balance in this group as paid.") {
      PRow("Settle Up Everyone", titleColor = C.accent, leading = { Icon2("checkmark.circle") }, onClick = {
        Store.update { d -> d.copy(splitEntries = d.splitEntries + b.filterValues { it != 0L }.map { (f, v) -> SplitEntry(friendId = f, amount = -v, note = "Settled up", groupId = id) }) }
      })
    }
    group("Activity") {
      if (mine.isEmpty()) PRow("Nothing yet", titleColor = C.secondary)
      mine.take(50).forEachIndexed { i, e ->
        if (i > 0) Divider()
        PRow(e.note ?: "Split", subtitle = "${db.friends.firstOrNull { it.id == e.friendId }?.name ?: "Friend"} · ${shortDate.format(e.occurredAt.toDate())}") {
          Text(Money.format(e.amount), style = T.amount(17), color = if (e.amount > 0) C.income else C.expense)
        }
      }
    }
  }
}

@Composable fun GroupFormSheet(id: String?) {
  val db = Store.value
  val existing = id?.let { gid -> db.splitGroups.firstOrNull { it.id == gid } }
  var name by remember { mutableStateOf(existing?.name ?: "") }
  var members by remember { mutableStateOf(existing?.memberIds ?: emptyList()) }
  var newFriends by remember { mutableStateOf(listOf<Friend>()) }
  PSheet({ Ui.sheet = null }) {
    SheetHeader(if (existing == null) "New Group" else "Edit Group", canSave = name.isNotBlank() && members.isNotEmpty(), onCancel = { Ui.sheet = null }) {
      Store.update { d ->
        val withFriends = d.copy(friends = d.friends + newFriends.filter { f -> f.id in members && d.friends.none { it.id == f.id } })
        if (existing != null) withFriends.copy(splitGroups = d.splitGroups.map { if (it.id == existing.id) it.copy(name = name.trim(), memberIds = members) else it })
        else withFriends.copy(splitGroups = d.splitGroups + SplitGroup(name = name.trim(), memberIds = members))
      }
      Ui.sheet = null
    }
    androidx.compose.foundation.lazy.LazyColumn(Modifier.fillMaxWidth().padding(bottom = 24.dp)) {
      group { FieldRow(name, { name = it }, "Name (Flatmates, Goa trip…)") }
      group("Members", footer = "Someone already on Paisa Pulse? Find them by @username, email or phone, and the group's shared expenses show up on their phone too.") {
        MemberPickerRows(members, { members = it }, newFriends, { newFriends = it })
      }
    }
  }
}
