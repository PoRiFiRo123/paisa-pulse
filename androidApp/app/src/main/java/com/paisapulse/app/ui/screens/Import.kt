package com.paisapulse.app.ui.screens

import android.annotation.SuppressLint
import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Base64
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.compose.rememberLauncherForActivityResult
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
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.paisapulse.app.data.*
import com.paisapulse.app.logic.*
import com.paisapulse.app.ui.*
import com.paisapulse.app.work.Services
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*

/** Runs pdf.js (assets/pdf-extractor.html, the same file the iPhone app uses) in a hidden WebView. Read on the phone, no network. */
object PdfExtractor {
  class Failure(val code: String) : Exception(code)
  @SuppressLint("StaticFieldLeak") private var web: WebView? = null
  private var ready: CompletableDeferred<Unit>? = null
  private var pending: CompletableDeferred<String>? = null

  @SuppressLint("SetJavaScriptEnabled")
  private fun load(ctx: Context): CompletableDeferred<Unit> {
    ready?.let { return it }
    val d = CompletableDeferred<Unit>(); ready = d
    val w = WebView(ctx.applicationContext)
    w.settings.javaScriptEnabled = true
    w.settings.allowFileAccess = false
    w.addJavascriptInterface(object { @JavascriptInterface fun done(json: String) { pending?.complete(json) } }, "PaisaNative")
    w.webViewClient = object : WebViewClient() {
      override fun onPageFinished(view: WebView?, url: String?) { d.complete(Unit) }
      override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?) = request?.url?.toString()?.startsWith("https://paisapulse.local") != true
    }
    val html = ctx.assets.open("pdf-extractor.html").bufferedReader().readText()
    w.loadDataWithBaseURL("https://paisapulse.local/", html, "text/html", "utf-8", null)
    web = w
    return d
  }

  suspend fun extract(ctx: Context, bytes: ByteArray, password: String?): List<TextItem> {
    withContext(Dispatchers.Main) { load(ctx) }.await()
    val result = CompletableDeferred<String>(); pending = result
    val b64 = Base64.encodeToString(bytes, Base64.NO_WRAP)
    val pw = JsonPrimitive(password ?: "").toString()
    withContext(Dispatchers.Main) {
      web!!.evaluateJavascript("window.extractPdf('$b64', $pw).then(function (r) { PaisaNative.done(JSON.stringify(r)); })", null)
    }
    val obj = PaisaJson.parseToJsonElement(result.await()).jsonObject
    if (obj["ok"]?.jsonPrimitive?.booleanOrNull == true) {
      return obj["items"]!!.jsonArray.map { e ->
        val o = e.jsonObject
        fun d(k: String) = o[k]?.jsonPrimitive?.doubleOrNull ?: 0.0
        TextItem(o["str"]?.jsonPrimitive?.content ?: "", d("x"), d("y"), d("w"), d("h"), d("page").toInt())
      }
    }
    throw Failure(obj["error"]?.jsonPrimitive?.contentOrNull ?: "error")
  }
}

class ImportSession(
  val fileName: String, val sheet: CellSheet, val template: StatementTemplate?, val mapping: Mapping, val accountId: String,
  val rows: List<PlannedRow> = emptyList(), val mismatches: Int? = null,
) {
  fun copy(mapping: Mapping = this.mapping, accountId: String = this.accountId, rows: List<PlannedRow> = this.rows, mismatches: Int? = this.mismatches) =
    ImportSession(fileName, sheet, template, mapping, accountId, rows, mismatches)
}

private fun plan(s: ImportSession, db: Db): ImportSession {
  val rows = StatementParser.extractRows(s.sheet, s.mapping)
  return s.copy(rows = ImportPlan.plan(s.accountId, rows, db.accounts, db.categories, db.transactions), mismatches = StatementParser.balanceMismatches(rows))
}

private fun fileName(ctx: Context, uri: Uri): String =
  ctx.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c -> if (c.moveToFirst()) c.getString(0) else null } ?: "statement"

/** Settings › Import Statement. Mirrors the iPhone ImportView. */
@Composable fun ImportScreen(presetAccountId: String?) {
  val ctx = LocalContext.current
  val scope = rememberCoroutineScope()
  val db by Store.db.collectAsState()
  var session by remember { mutableStateOf<ImportSession?>(null) }
  var busy by remember { mutableStateOf(false) }
  var error by remember { mutableStateOf<String?>(null) }
  var pdf by remember { mutableStateOf<Pair<ByteArray, String>?>(null) }
  var wrongPassword by remember { mutableStateOf(false) }

  fun start(sheet: CellSheet, name: String) {
    val template = StatementParser.detectTemplate(sheet)
    val account = presetAccountId?.let { id -> db.accounts.firstOrNull { it.id == id } } ?: StatementParser.guessAccount(db.accounts, template)
    if (account == null) { error = "Add an account first."; return }
    val mapping = StatementParser.detectMapping(sheet, template, account.type == "card")
    if (mapping == null) { error = "Couldn't find the transactions table in this file. Try another format (PDF, CSV or Excel)."; return }
    session = plan(ImportSession(name, sheet, template, mapping, account.id), Store.value)
  }
  fun readPdf(bytes: ByteArray, name: String, password: String?) {
    busy = true
    scope.launch {
      try {
        val items = PdfExtractor.extract(ctx, bytes, password)
        wrongPassword = false; pdf = null
        start(PdfLayout.toSheet(items), name)
      } catch (f: PdfExtractor.Failure) {
        when (f.code) { "password" -> { wrongPassword = false; pdf = bytes to name }; "incorrect-password" -> { wrongPassword = true; pdf = bytes to name }
          else -> error = "Couldn't read this PDF. Try the CSV or Excel download." }
      } catch (e: Exception) { error = "Couldn't read this PDF. Try the CSV or Excel download." }
      busy = false
    }
  }
  val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
    uri ?: return@rememberLauncherForActivityResult
    scope.launch {
      val bytes = withContext(Dispatchers.IO) { runCatching { ctx.contentResolver.openInputStream(uri)!!.use { it.readBytes() } }.getOrNull() }
      if (bytes == null) { error = "Couldn't open the file."; return@launch }
      val name = fileName(ctx, uri)
      val text = { runCatching { String(bytes, Charsets.UTF_8) }.getOrDefault(String(bytes, Charsets.ISO_8859_1)) }
      when (StatementReaders.detect(bytes)) {
        FileKind.Pdf -> readPdf(bytes, name, null)
        FileKind.Xlsx -> start(withContext(Dispatchers.IO) { StatementReaders.xlsx(bytes) }, name)
        FileKind.Html -> start(StatementReaders.html(text()), name)
        FileKind.Csv -> start(StatementReaders.csv(text()), name)
        FileKind.XlsBinary -> error = "Old Excel (.xls) files aren't supported. Download the statement as PDF, CSV or XLSX instead."
        FileKind.Unknown -> error = "This doesn't look like a statement. Try the PDF, CSV or Excel download from your bank."
      }
    }
  }

  val s = session
  if (s == null) {
    PScreen("Import Statement", back = true) {
      group {
        Column(Modifier.padding(16.dp)) {
          androidx.compose.material3.Icon(Sym.of("doc.text.viewfinder"), null, tint = C.accent, modifier = Modifier.size(40.dp))
          Text("Bring in a bank or card statement", style = T.headline, color = C.label, modifier = Modifier.padding(top = 10.dp))
          Text("PDF, CSV or Excel from Axis, Bank of Baroda, HDFC, ICICI, SBI and most others. Read on this phone; nothing is uploaded.",
            style = T.subhead, color = C.secondary, modifier = Modifier.padding(top = 4.dp))
          Button({ picker.launch(arrayOf("*/*")) }, enabled = !busy, modifier = Modifier.fillMaxWidth().padding(top = 12.dp).height(50.dp),
            shape = RoundedCornerShape(25.dp), colors = ButtonDefaults.buttonColors(containerColor = C.accent)) {
            Text(if (busy) "Reading…" else "Choose File", style = T.headline, color = Color.White)
          }
        }
      }
      val batches = db.importBatches.sortedByDescending { it.createdAt }.take(20)
      if (batches.isNotEmpty()) group("Recent imports") {
        batches.forEachIndexed { i, b ->
          if (i > 0) Divider()
          PRow(b.fileName, subtitle = "${b.count} transactions · ${db.accounts.firstOrNull { it.id == b.accountId }?.name ?: "Account"} · ${shortDate.format(b.createdAt.toDate())}") {
            val undone = b.undoneAt != null
            Text(if (undone) "Restore" else "Undo", style = T.subhead.copy(fontWeight = FontWeight.SemiBold), color = if (undone) C.accent else C.expense,
              modifier = Modifier.clip(CircleShape).background(C.fill).combinedClickableCompat({ if (undone) restoreImport(b) else undoImport(b) }, {}).padding(horizontal = 12.dp, vertical = 6.dp))
          }
        }
      }
    }
  } else ImportReview(s, db, onChange = { session = it }, onBack = { session = null }, onCommit = {
    val (batch, txns) = ImportPlan.commit(s.accountId, s.fileName, s.template?.id, s.rows)
    Store.update { d -> d.copy(importBatches = d.importBatches + batch, transactions = d.transactions + txns) }
    Services.refreshWidget()
    session = null
    Ui.show("Imported ${batch.count}") { undoImport(batch) }
  })

  pdf?.let { (bytes, name) ->
    var pw by remember { mutableStateOf("") }
    AlertDialog(onDismissRequest = { pdf = null }, containerColor = C.card,
      title = { Text("Password-protected PDF", style = T.headline, color = C.label) },
      text = {
        Column {
          Text(if (wrongPassword) "That password didn't work. Banks often use your date of birth or customer ID." else "Banks usually lock statements with your date of birth or customer ID.",
            style = T.footnote, color = C.secondary)
          OutlinedTextField(pw, { pw = it }, singleLine = true, placeholder = { Text("Password") }, visualTransformation = PasswordVisualTransformation(), modifier = Modifier.padding(top = 8.dp))
        }
      },
      confirmButton = { TextButton({ val p = pw; pdf = null; readPdf(bytes, name, p) }) { Text("Open", color = C.accent, style = T.headline) } },
      dismissButton = { TextButton({ pdf = null }) { Text("Cancel", color = C.accent, style = T.body) } })
  }
  error?.let { e ->
    AlertDialog(onDismissRequest = { error = null }, containerColor = C.card, title = { Text("Can't import this file", style = T.headline, color = C.label) },
      text = { Text(e, style = T.body, color = C.secondary) }, confirmButton = { TextButton({ error = null }) { Text("OK", color = C.accent, style = T.headline) } })
  }
}

private fun undoImport(b: ImportBatch) {
  val t = now()
  Store.update { d -> d.copy(transactions = d.transactions.map { if (it.importBatchId == b.id && it.deletedAt == null) it.copy(deletedAt = t, updatedAt = t) else it },
    importBatches = d.importBatches.map { if (it.id == b.id) it.copy(undoneAt = t) else it }) }
  Services.refreshWidget()
}

private fun restoreImport(b: ImportBatch) {
  val undone = Store.value.importBatches.firstOrNull { it.id == b.id }?.undoneAt ?: return
  Store.update { d -> d.copy(transactions = d.transactions.map { if (it.importBatchId == b.id && it.deletedAt == undone) it.copy(deletedAt = null, updatedAt = now()) else it },
    importBatches = d.importBatches.map { if (it.id == b.id) it.copy(undoneAt = null) else it }) }
  Services.refreshWidget()
}

@Composable private fun ImportReview(s: ImportSession, db: Db, onChange: (ImportSession) -> Unit, onBack: () -> Unit, onCommit: () -> Unit) {
  val l = remember(db) { Lookups(db) }
  var columnsOpen by remember { mutableStateOf(false) }
  val chosen = s.rows.filter { it.include }
  fun replan(n: ImportSession) = onChange(plan(n, Store.value))
  fun setRow(key: String, f: (PlannedRow) -> PlannedRow) = onChange(s.copy(rows = s.rows.map { if (it.key == key) f(it) else it }))
  androidx.activity.compose.BackHandler { onBack() }
  PScreen(s.template?.name ?: "Review", large = false, leading = {
    Text("Back", style = T.body, color = C.accent, modifier = Modifier.glass(CircleShape).combinedClickableCompat(onBack, {}).padding(horizontal = 16.dp, vertical = 11.dp))
  }, actions = {
    Text("Import ${chosen.size}", style = T.body.copy(fontWeight = FontWeight.SemiBold), color = if (chosen.isEmpty()) C.tertiary else C.accent,
      modifier = Modifier.glass(CircleShape).combinedClickableCompat({ if (chosen.isNotEmpty()) onCommit() }, {}).padding(horizontal = 16.dp, vertical = 11.dp))
  }) {
    group(footer = s.mismatches?.takeIf { it > 0 }?.let { "$it rows don't match the running balance. Check the columns." }
      ?: "${s.rows.size} transactions found${if (s.mismatches == 0) ", balances check out" else ""}.") {
      PickerRow("Account", db.accounts.filter { it.archivedAt == null }.map { it.id to it.name }, s.accountId) { replan(s.copy(accountId = it)) }
      Divider()
      PRow("Columns", chevron = true, onClick = { columnsOpen = !columnsOpen })
      if (columnsOpen) {
        val header = s.sheet.getOrNull(s.mapping.headerRow).orEmpty()
        s.mapping.columns.forEachIndexed { i, role ->
          Divider()
          PickerRow(header.getOrNull(i)?.ifBlank { null } ?: "Column ${i + 1}", ColumnRole.entries.map { it to it.label }, role) { r ->
            replan(s.copy(mapping = s.mapping.copy(columns = s.mapping.columns.toMutableList().also { it[i] = r })))
          }
        }
        Divider()
        PickerRow("Dates", listOf(DateOrder.Dmy to "Day first (31/12)", DateOrder.Mdy to "Month first (12/31)"), s.mapping.dateOrder) { replan(s.copy(mapping = s.mapping.copy(dateOrder = it))) }
        if (ColumnRole.Amount in s.mapping.columns && ColumnRole.Debit !in s.mapping.columns) {
          Divider()
          PickerRow("A positive amount is", listOf(true to "Money in", false to "Money out"), s.mapping.positiveIsIn) { replan(s.copy(mapping = s.mapping.copy(positiveIsIn = it))) }
        }
      }
    }
    group {
      SummaryCells("Out" to (chosen.filter { it.row.out }.sumOf { it.row.amount } to C.expense), "In" to (chosen.filter { !it.row.out }.sumOf { it.row.amount } to C.income))
    }
    group("${chosen.size} of ${s.rows.size} selected", trailing = {
      val all = chosen.size != s.rows.size
      Text(if (all) "All" else "None", style = T.subhead, color = C.accent, modifier = Modifier.combinedClickableCompat({ onChange(s.copy(rows = s.rows.map { it.copy(include = all) })) }, {}))
    }) {
      s.rows.forEachIndexed { i, p ->
        if (i > 0) Divider(52.dp)
        ImportRowView(p, s.accountId, db, l, onToggle = { setRow(p.key) { it.copy(include = !it.include) } }, onChange = { n -> setRow(p.key) { n } })
      }
    }
  }
}

@Composable private fun ImportRowView(p: PlannedRow, accountId: String, db: Db, l: Lookups, onToggle: () -> Unit, onChange: (PlannedRow) -> Unit) {
  var catMenu by remember { mutableStateOf(false) }
  var accMenu by remember { mutableStateOf(false) }
  val others = db.accounts.filter { it.archivedAt == null && it.id != accountId }
  Row(Modifier.fillMaxWidth().alpha(if (p.include) 1f else 0.6f).padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.Top) {
    androidx.compose.material3.Icon(Sym.of(if (p.include) "checkmark.circle.fill" else "circle"), if (p.include) "Included" else "Skipped",
      tint = if (p.include) C.accent else C.tertiary, modifier = Modifier.size(24.dp).combinedClickableCompat(onToggle, {}))
    Spacer(Modifier.width(12.dp))
    Column(Modifier.weight(1f)) {
      Row(verticalAlignment = Alignment.CenterVertically) {
        Text(p.payee ?: "Unknown", style = T.body, color = C.label, maxLines = 1, modifier = Modifier.weight(1f))
        AmountText(p.row.amount, if (p.type == "transfer") TxnType.Transfer else if (p.row.out) TxnType.Expense else TxnType.Income)
      }
      Text(p.row.description, style = T.caption, color = C.secondary, maxLines = 2)
      Row(Modifier.padding(top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(shortDate.format(p.row.date.toDate()), style = T.caption, color = C.secondary)
        Spacer(Modifier.width(10.dp))
        if (p.type == "transfer") Box {
          Text("⇄ " + (p.otherAccountId?.let { l.accounts[it]?.name } ?: "Pick account"), style = T.caption.copy(fontWeight = FontWeight.Medium), color = C.accent,
            modifier = Modifier.combinedClickableCompat({ accMenu = true }, {}))
          DropdownMenu(accMenu, { accMenu = false }, modifier = Modifier.background(C.card)) {
            others.forEach { a -> DropdownMenuItem({ Text(a.name, style = T.body) }, { accMenu = false; onChange(p.copy(otherAccountId = a.id)) }) }
            HorizontalDivider(color = C.separator)
            DropdownMenuItem({ Text("Not a transfer", style = T.body) }, { accMenu = false; onChange(p.copy(type = if (p.row.out) "expense" else "income", otherAccountId = null)) })
          }
        } else Box {
          val c = p.categoryId?.let { l.categories[it] }
          Row(Modifier.combinedClickableCompat({ catMenu = true }, {}), verticalAlignment = Alignment.CenterVertically) {
            if (c != null) CategoryBadge(c.icon, c.color, 16.dp)
            Text(" " + (c?.name ?: "Uncategorised"), style = T.caption.copy(fontWeight = FontWeight.Medium), color = C.accent)
          }
          DropdownMenu(catMenu, { catMenu = false }, modifier = Modifier.background(C.card)) {
            DropdownMenuItem({ Text("Uncategorised", style = T.body) }, { catMenu = false; onChange(p.copy(categoryId = null)) })
            db.categories.filter { it.archivedAt == null && it.kind == (if (p.row.out) "expense" else "income") }.sortedBy { it.sortOrder }.forEach { cat ->
              DropdownMenuItem({ Text(cat.name, style = T.body) }, { catMenu = false; onChange(p.copy(categoryId = cat.id)) }, leadingIcon = { CategoryBadge(cat.icon, cat.color, 24.dp) })
            }
            HorizontalDivider(color = C.separator)
            others.forEach { a -> DropdownMenuItem({ Text("Transfer with ${a.name}", style = T.body) }, { catMenu = false; onChange(p.copy(type = "transfer", otherAccountId = a.id)) }) }
          }
        }
      }
      p.hint?.let { Text((if (p.status == "new") "ⓘ " else "⚠ ") + it, style = T.caption, color = if (p.status == "new") C.secondary else androidx.compose.ui.graphics.Color(0xFFFF9500), modifier = Modifier.padding(top = 2.dp)) }
    }
  }
}
