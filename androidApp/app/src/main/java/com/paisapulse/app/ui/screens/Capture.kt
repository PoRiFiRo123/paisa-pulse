package com.paisapulse.app.ui.screens

import android.app.Activity
import android.content.Intent
import android.speech.RecognizerIntent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import com.paisapulse.app.data.*
import com.paisapulse.app.logic.*
import com.paisapulse.app.ui.*
import com.paisapulse.app.work.Services
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

/** "screenshot": payment screenshots read with ML Kit (on device). "voice": speak or type a sentence (Android only). */
@Composable fun CaptureScreen(mode: String) {
  val ctx = LocalContext.current
  val scope = rememberCoroutineScope()
  val db by Store.db.collectAsState()
  val l = remember(db) { Lookups(db) }
  var drafts by remember { mutableStateOf(listOf<CaptureDraft>()) }
  var skipped by remember { mutableStateOf(listOf<String>()) }
  var unread by remember { mutableIntStateOf(0) }
  var reading by remember { mutableStateOf(false) }
  var sentence by remember { mutableStateOf("") }
  val voice = mode == "voice"
  val alerts = mode == "alerts"
  fun context() = CaptureDrafts.context(Store.value, Prefs.lastAccountId.ifEmpty { null })
  fun looksLogged(d: CaptureDraft) = Store.value.liveTxns.any { it.amount == d.amount && Math.abs(it.occurredAt - d.occurredAt) <= 86_400_000L }

  fun readUris(uris: List<android.net.Uri>) {
    if (uris.isEmpty()) return
    reading = true
    scope.launch {
      val c = context(); var missed = 0
      val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
      val found = mutableListOf<CaptureDraft>()
      uris.forEachIndexed { i, uri ->
        val blocks = runCatching {
          val image = InputImage.fromFilePath(ctx, uri)
          suspendCancellableCoroutine { cont ->
            recognizer.process(image).addOnSuccessListener { r -> cont.resume(r.textBlocks.map { it.text }) }.addOnFailureListener { cont.resume(emptyList()) }
          }
        }.getOrDefault(emptyList())
        val d = ScreenshotParser.parse(blocks, c, "shot-${drafts.size + i}-${now()}")
        if (d == null) missed++ else found += if (d.warning == null && looksLogged(d)) d.copy(include = false, warning = "Looks like you've already added this one.") else d
      }
      recognizer.close()
      drafts = drafts + found; unread = missed; reading = false
    }
  }
  val photos = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(20)) { uris -> readUris(uris) }
  // Shared from a UPI app (GPay, PhonePe, Paytm…): read them straight away.
  LaunchedEffect(Ui.sharedImages) {
    if (!voice && Ui.sharedImages.isNotEmpty()) { val u = Ui.sharedImages; Ui.sharedImages = emptyList(); readUris(u) }
  }
  // Bank SMS / notifications kept by auto-capture.
  LaunchedEffect(alerts) {
    if (!alerts) return@LaunchedEffect
    val c = context(); val known = Store.value.transactions.mapNotNull { it.externalId }.toSet(); val seen = HashSet<String>()
    drafts = com.paisapulse.app.work.AlertQueue.all(ctx).mapNotNull { BankAlerts.parse(it, c) }.filter { it.key !in known && seen.add(it.key) }
      .map { if (looksLogged(it)) it.copy(include = false, warning = "Looks like you've already added this one.") else it }
    if (drafts.isEmpty()) com.paisapulse.app.work.AlertQueue.save(ctx, emptyList())
  }
  fun parseSentence(text: String) {
    if (text.isBlank()) return
    val (d, s) = VoiceParser.parse(text, context())
    drafts = drafts + d.map { it.copy(key = "voice-${drafts.size}-${it.key}-${now()}") }; skipped = s; sentence = ""
  }
  val speech = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { r ->
    if (r.resultCode == Activity.RESULT_OK) r.data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()?.let { parseSentence(it) }
  }
  fun listen() {
    val i = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
      .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
      .putExtra(RecognizerIntent.EXTRA_LANGUAGE, "en-IN")
      .putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
      .putExtra(RecognizerIntent.EXTRA_PROMPT, "Say it like: 250 lunch, 80 auto and 40 chai")
    runCatching { speech.launch(i) }.onFailure { Ui.show("Speech isn't available on this phone. Type it instead.") }
  }
  fun commit() {
    val add = drafts.filter { it.include && it.accountId != null }.map { d ->
      Txn(type = d.type, amount = d.amount, accountId = d.accountId!!, toAccountId = if (d.type == "transfer") d.toAccountId else null,
        categoryId = if (d.type == "transfer") null else d.categoryId, payee = d.payee, note = d.note, occurredAt = d.occurredAt,
        source = if (voice) "voice" else if (alerts) "sms" else "screenshot", externalId = if (alerts) d.key else null,
        paymentMethod = if (voice || d.type == "transfer") null else if (alerts) (PaymentMethod.fromText(d.source)?.id ?: "upi") else "upi")
    }
    val ids = add.map { it.id }.toSet()
    Store.update { it.copy(transactions = it.transactions + add) }
    if (alerts) com.paisapulse.app.work.AlertQueue.save(ctx, emptyList()) // everything shown has been reviewed
    Services.refreshWidget()
    Ui.pop()
    Ui.show("Added ${add.size}") { Store.update { d -> d.copy(transactions = d.transactions.map { if (it.id in ids) it.copy(deletedAt = now()) else it }) }; Services.refreshWidget() }
  }
  val count = drafts.count { it.include && it.accountId != null }

  PScreen(if (voice) "Say It" else if (alerts) "Bank Messages" else "From Screenshots", back = true, actions = {
    Text("Add $count", style = T.body.copy(fontWeight = FontWeight.SemiBold), color = if (count == 0) C.tertiary else C.accent,
      modifier = Modifier.glass(CircleShape).combinedClickableCompat({ if (count > 0) commit() }, {}).padding(horizontal = 16.dp, vertical = 11.dp))
  }) {
    if (voice) {
      group(footer = "Amounts, dates (yesterday, last monday), accounts (from axis, in cash) and payees (to Rahul, at DMart). Heard on this phone when it can.") {
        Column(Modifier.padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
          Box(Modifier.size(84.dp).clip(CircleShape).background(C.accent).combinedClickableCompat({ listen() }, {}), contentAlignment = Alignment.Center) {
            androidx.compose.material3.Icon(Sym.of("mic.fill"), "Speak", tint = Color.White, modifier = Modifier.size(38.dp))
          }
          Text("Tap and say what you spent", style = T.subhead, color = C.secondary, modifier = Modifier.padding(top = 10.dp))
          Row(Modifier.padding(top = 12.dp).fillMaxWidth().clip(RoundedCornerShape(22.dp)).background(C.fill).padding(horizontal = 14.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f)) { FieldRow(sentence, { sentence = it }, "Or type: 250 lunch, 80 auto…", modifier = Modifier.padding(0.dp)) }
            Text("Read", style = T.subhead.copy(fontWeight = FontWeight.SemiBold), color = if (sentence.isBlank()) C.tertiary else C.accent,
              modifier = Modifier.combinedClickableCompat({ parseSentence(sentence) }, {}).padding(8.dp))
          }
        }
      }
      if (skipped.isNotEmpty()) item { Text("Didn't catch an amount in: ${skipped.joinToString(", ")}", style = T.footnote, color = C.secondary, modifier = Modifier.padding(horizontal = 32.dp)) }
    } else if (alerts) {
      if (drafts.isEmpty()) item { EmptyHint("All caught up", "tray", "No bank messages waiting. Turn on auto-capture in Settings › Auto-capture.") }
      else item { Text("From your bank messages. Tick the ones to add.", style = T.footnote, color = C.secondary, modifier = Modifier.padding(horizontal = 32.dp)) }
    } else {
      group(footer = if (unread > 0) "$unread screenshot${if (unread == 1) "" else "s"} had no amount we could read." else "Payment screens from GPay, PhonePe, Paytm, BHIM, CRED, Amazon Pay, WhatsApp, Navi or your bank. Read on this phone. Tip: share a screenshot straight from any UPI app to Paisa Pulse.") {
        Button({ photos.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }, enabled = !reading,
          modifier = Modifier.fillMaxWidth().padding(16.dp).height(50.dp), shape = RoundedCornerShape(25.dp), colors = ButtonDefaults.buttonColors(containerColor = C.accent)) {
          Text(if (reading) "Reading…" else if (drafts.isEmpty()) "Choose Screenshots" else "Choose More", style = T.headline, color = Color.White)
        }
      }
      if (drafts.isEmpty() && !reading) item { EmptyHint("Snap it, log it", "camera.fill", "Take a screenshot after you pay, then pick it here. Amount, payee, date and account are filled in.") }
    }
    if (drafts.isNotEmpty()) group {
      drafts.forEachIndexed { i, d ->
        if (i > 0) Divider(52.dp)
        DraftCard(d, db, l) { n -> drafts = drafts.map { if (it.key == d.key) n else it } }
      }
    }
  }
}

@Composable private fun DraftCard(d: CaptureDraft, db: Db, l: Lookups, onChange: (CaptureDraft) -> Unit) {
  var typeMenu by remember { mutableStateOf(false) }
  var accMenu by remember { mutableStateOf(false) }
  var catMenu by remember { mutableStateOf(false) }
  var pickDate by remember { mutableStateOf(false) }
  val kind = TxnType.of(d.type)
  Row(Modifier.fillMaxWidth().alpha(if (d.include) 1f else 0.6f).padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.Top) {
    androidx.compose.material3.Icon(Sym.of(if (d.include) "checkmark.circle.fill" else "circle"), null, tint = if (d.include) C.accent else C.tertiary,
      modifier = Modifier.size(24.dp).combinedClickableCompat({ onChange(d.copy(include = !d.include)) }, {}))
    Spacer(Modifier.width(12.dp))
    Column(Modifier.weight(1f)) {
      Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.weight(1f)) {
          if (kind == TxnType.Transfer) Text("To ${d.toAccountId?.let { l.accounts[it]?.name } ?: "card"}", style = T.body, color = C.label)
          else FieldRow(d.payee ?: "", { onChange(d.copy(payee = it.ifEmpty { null })) }, "Payee", modifier = Modifier.padding(0.dp))
        }
        AmountText(d.amount, kind)
      }
      Text(java.time.Instant.ofEpochMilli(d.occurredAt).atZone(zone).format(java.time.format.DateTimeFormatter.ofPattern("d MMM, h:mm a", java.util.Locale.ENGLISH)),
        style = T.caption, color = C.accent, modifier = Modifier.padding(vertical = 2.dp).combinedClickableCompat({ pickDate = true }, {}))
      Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        Box {
          Text(kind.label, style = T.caption.copy(fontWeight = FontWeight.Medium), color = C.accent, modifier = Modifier.combinedClickableCompat({ typeMenu = true }, {}))
          DropdownMenu(typeMenu, { typeMenu = false }, modifier = Modifier.background(C.card)) {
            TxnType.entries.forEach { t -> DropdownMenuItem({ Text(t.label, style = T.body) }, { typeMenu = false; onChange(d.copy(type = t.key)) }) }
          }
        }
        Box {
          Text(d.accountId?.let { l.accounts[it]?.name } ?: "Account", style = T.caption.copy(fontWeight = FontWeight.Medium), color = C.accent,
            modifier = Modifier.combinedClickableCompat({ accMenu = true }, {}))
          DropdownMenu(accMenu, { accMenu = false }, modifier = Modifier.background(C.card)) {
            db.accounts.filter { it.archivedAt == null }.forEach { a -> DropdownMenuItem({ Text(a.name, style = T.body) }, { accMenu = false; onChange(d.copy(accountId = a.id)) }) }
          }
        }
        if (kind != TxnType.Transfer) Box {
          Text(d.categoryId?.let { l.categories[it]?.name } ?: "Category", style = T.caption.copy(fontWeight = FontWeight.Medium), color = C.accent,
            modifier = Modifier.combinedClickableCompat({ catMenu = true }, {}))
          DropdownMenu(catMenu, { catMenu = false }, modifier = Modifier.background(C.card)) {
            DropdownMenuItem({ Text("Uncategorised", style = T.body) }, { catMenu = false; onChange(d.copy(categoryId = null)) })
            db.categories.filter { it.archivedAt == null && it.kind == (if (kind == TxnType.Income) "income" else "expense") }.sortedBy { it.sortOrder }.forEach { c ->
              DropdownMenuItem({ Text(c.name, style = T.body) }, { catMenu = false; onChange(d.copy(categoryId = c.id)) }, leadingIcon = { CategoryBadge(c.icon, c.color, 24.dp) })
            }
          }
        }
      }
      d.warning?.let { Text("⚠ $it", style = T.caption, color = Color(0xFFFF9500), modifier = Modifier.padding(top = 2.dp)) }
    }
  }
  if (pickDate) DayPickerDialog(d.occurredAt.toDate(), onDismiss = { pickDate = false }) { day ->
    val z = java.time.Instant.ofEpochMilli(d.occurredAt).atZone(zone)
    onChange(d.copy(occurredAt = day.atTime(z.toLocalTime()).atZone(zone).toInstant().toEpochMilli())); pickDate = false
  }
}
