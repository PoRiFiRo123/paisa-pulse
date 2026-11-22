package com.paisapulse.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.paisapulse.app.data.*
import com.paisapulse.app.logic.*
import com.paisapulse.app.ui.*
import com.paisapulse.app.work.Services

object Search {
  fun matches(t: Txn, q: String, l: Lookups): Boolean {
    val s = q.trim().lowercase(); if (s.isEmpty()) return true
    if (Money.parse(s)?.let { it == t.amount } == true) return true
    if (s.startsWith("#")) return t.tags.orEmpty().any { it.startsWith(s.drop(1)) }
    return (listOf(t.payee, t.note, t.categoryId?.let { l.categories[it]?.name }, l.accounts[t.accountId]?.name) + t.tags.orEmpty()).any { it?.lowercase()?.contains(s) == true }
  }
}

@Composable fun SearchField(q: String, onChange: (String) -> Unit, hint: String) {
  Row(Modifier.padding(horizontal = 16.dp, vertical = 4.dp).fillMaxWidth().height(44.dp).clip(CircleShape).background(C.fill).padding(horizontal = 14.dp),
    verticalAlignment = Alignment.CenterVertically) {
    Icon(Sym.of("magnifyingglass"), null, tint = C.secondary, modifier = Modifier.size(20.dp))
    Spacer(Modifier.width(8.dp))
    FieldRow(q, onChange, hint, modifier = Modifier.padding(0.dp))
  }
}

/** Saved-filter JSON, same shape as iOS FilterPayload and the RN app. */
@kotlinx.serialization.Serializable data class FilterPayload(val filters: Filters = Filters(), val search: String = "") {
  @kotlinx.serialization.Serializable data class Filters(
    val monthOffset: Int? = null, val accountIds: List<String> = emptyList(), val categoryIds: List<String> = emptyList(), val types: List<String> = emptyList(),
  )
  fun json() = PaisaJson.encodeToString(serializer(), this)
  companion object {
    fun of(offset: Int, accountId: String?, categoryId: String?, type: TxnType?, search: String) = FilterPayload(
      Filters(if (offset == 0) null else offset, listOfNotNull(accountId), listOfNotNull(categoryId), listOfNotNull(type?.key)), search)
    fun parse(json: String) = runCatching { PaisaJson.decodeFromString(serializer(), json) }.getOrNull()
  }
}

@Composable fun ActivityScreen() {
  val db by Store.db.collectAsState()
  val l = remember(db) { Lookups(db) }
  var offset by remember { mutableIntStateOf(0) }
  var q by remember { mutableStateOf("") }
  var type by remember { mutableStateOf<TxnType?>(null) }
  var accountId by remember { mutableStateOf<String?>(null) }
  var categoryId by remember { mutableStateOf<String?>(null) }
  var filters by remember { mutableStateOf(false) }
  var selecting by remember { mutableStateOf(false) }
  var selection by remember { mutableStateOf(setOf<String>()) }
  var naming by remember { mutableStateOf<SavedFilter?>(null) }
  var savingNew by remember { mutableStateOf(false) }
  var chipMenu by remember { mutableStateOf<String?>(null) }
  DisposableEffect(selecting) { Ui.hideTabBar = selecting; onDispose { Ui.hideTabBar = false } }
  androidx.activity.compose.BackHandler(selecting) { selecting = false; selection = emptySet() }
  val range = Periods.month(offset, Prefs.monthStartDay)
  val rows = db.liveTxns.filter { t ->
    t.occurredAt in range && (type == null || t.kind == type) && (accountId == null || t.accountId == accountId || t.toAccountId == accountId) &&
      (categoryId == null || t.categoryId == categoryId || Ledger.topLevel(t.categoryId, l.categories) == categoryId) && Search.matches(t, q, l)
  }.sortedByDescending { it.occurredAt }
  val days = rows.groupBy { it.occurredAt.toDate() }.toSortedMap(compareByDescending { it })
  val s = Ledger.summary(rows, range)
  val current = FilterPayload.of(offset, accountId, categoryId, type, q)
  val isDefault = type == null && accountId == null && categoryId == null
  val saved = db.savedFilters.sortedBy { it.sortOrder }
  fun apply(p: FilterPayload) {
    offset = p.filters.monthOffset ?: 0; accountId = p.filters.accountIds.firstOrNull(); categoryId = p.filters.categoryIds.firstOrNull()
    type = p.filters.types.firstOrNull()?.let { TxnType.of(it) }; q = p.search
  }
  fun bulk(items: List<Txn>, message: String, change: (Txn) -> Txn) {
    val ids = items.map { it.id }.toSet()
    val before = db.transactions.filter { it.id in ids }.associateBy { it.id }
    Store.update { d -> d.copy(transactions = d.transactions.map { if (it.id in ids) change(it).copy(updatedAt = now()) else it }) }
    Services.refreshWidget()
    selecting = false; selection = emptySet()
    Ui.show(message) { Store.update { d -> d.copy(transactions = d.transactions.map { before[it.id] ?: it }) }; Services.refreshWidget() }
  }

  Box(Modifier.fillMaxSize()) {
    PScreen(if (selecting) (if (selection.isEmpty()) "Select" else "${selection.size} selected") else "Activity", large = !selecting, leading = {
      if (selecting) {
        Text(if (selection.size == rows.size) "Deselect All" else "Select All", style = T.body, color = C.accent,
          modifier = Modifier.glass(CircleShape).combinedClickableCompat({ selection = if (selection.size == rows.size) emptySet() else rows.map { it.id }.toSet() }, {})
            .padding(horizontal = 16.dp, vertical = 11.dp))
      } else Row(Modifier.height(44.dp).glass(CircleShape).padding(horizontal = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton({ offset-- }) { Icon(Sym.of("chevron.left"), "Previous month", tint = C.accent, modifier = Modifier.size(16.dp)) }
        Text(Periods.label(range, Prefs.monthStartDay), style = T.subhead.copy(fontWeight = FontWeight.SemiBold), color = C.label)
        IconButton({ if (offset < 0) offset++ }, enabled = offset < 0) { Icon(Sym.of("chevron.right"), "Next month", tint = if (offset < 0) C.accent else C.tertiary, modifier = Modifier.size(16.dp)) }
      }
    }, actions = {
      if (selecting) {
        Text("Done", style = T.body.copy(fontWeight = FontWeight.SemiBold), color = C.accent,
          modifier = Modifier.glass(CircleShape).combinedClickableCompat({ selecting = false; selection = emptySet() }, {}).padding(horizontal = 16.dp, vertical = 11.dp))
      } else {
        Box {
          GlassIcon("line.3.horizontal.decrease", "Filters", tint = if (!isDefault) C.expense else C.accent) { filters = true }
          DropdownMenu(filters, { filters = false }, modifier = Modifier.background(C.card)) {
            DropdownMenuItem({ Text("Select", style = T.body) }, { filters = false; selecting = true }, leadingIcon = { Icon(Sym.of("checkmark.circle"), null) })
            if (!isDefault || q.isNotBlank()) DropdownMenuItem({ Text("Save Current Filter…", style = T.body) }, { filters = false; savingNew = true }, leadingIcon = { Icon(Sym.of("bookmark"), null) })
            HorizontalDivider(color = C.separator)
            Text("Type", style = T.footnote, color = C.secondary, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
            (listOf<TxnType?>(null) + TxnType.entries).forEach { v ->
              DropdownMenuItem({ Text(v?.label ?: "All types", style = T.body) }, { type = v }, trailingIcon = { if (type == v) Icon(Sym.of("checkmark"), null, tint = C.accent) })
            }
            HorizontalDivider(color = C.separator)
            Text("Account", style = T.footnote, color = C.secondary, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
            (listOf<Account?>(null) + db.accounts.filter { it.archivedAt == null }).forEach { a ->
              DropdownMenuItem({ Text(a?.name ?: "All accounts", style = T.body) }, { accountId = a?.id }, trailingIcon = { if (accountId == a?.id) Icon(Sym.of("checkmark"), null, tint = C.accent) })
            }
            HorizontalDivider(color = C.separator)
            Text("Category", style = T.footnote, color = C.secondary, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
            (listOf<Category?>(null) + db.categories.filter { it.parentId == null && it.archivedAt == null }).forEach { c ->
              DropdownMenuItem({ Text(c?.name ?: "All categories", style = T.body) }, { categoryId = c?.id }, trailingIcon = { if (categoryId == c?.id) Icon(Sym.of("checkmark"), null, tint = C.accent) })
            }
            if (!isDefault) DropdownMenuItem({ Text("Clear Filters", style = T.body, color = C.expense) }, { type = null; accountId = null; categoryId = null; filters = false })
          }
        }
        AddButton()
      }
    }) {
      if (!selecting) item { SearchField(q, { q = it }, "Payee, note, category, amount") }
      if (saved.isNotEmpty() && !selecting) item {
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
          saved.forEach { f ->
            val on = FilterPayload.parse(f.filters) == current
            Box {
              Row(Modifier.clip(CircleShape).background(if (on) C.accent else C.fill)
                .combinedClickableCompat({ if (on) { type = null; accountId = null; categoryId = null; q = "" } else FilterPayload.parse(f.filters)?.let { apply(it) } }, { chipMenu = f.id })
                .padding(horizontal = 12.dp, vertical = 7.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Sym.of(if (on) "bookmark.fill" else "bookmark"), null, tint = if (on) Color.White else C.label, modifier = Modifier.size(15.dp))
                Spacer(Modifier.width(5.dp))
                Text(f.name, style = T.subhead.copy(fontWeight = FontWeight.Medium), color = if (on) Color.White else C.label)
              }
              DropdownMenu(chipMenu == f.id, { chipMenu = null }, modifier = Modifier.background(C.card)) {
                DropdownMenuItem({ Text("Update to Current Filters", style = T.body) }, { chipMenu = null
                  Store.update { d -> d.copy(savedFilters = d.savedFilters.map { if (it.id == f.id) it.copy(filters = current.json(), updatedAt = now()) else it }) }
                  Ui.show("Updated ${f.name}") }, leadingIcon = { Icon(Sym.of("arrow.triangle.2.circlepath"), null) })
                DropdownMenuItem({ Text("Rename", style = T.body) }, { chipMenu = null; naming = f }, leadingIcon = { Icon(Sym.of("pencil"), null) })
                DropdownMenuItem({ Text("Delete", style = T.body, color = C.expense) }, { chipMenu = null
                  Store.update { d -> d.copy(savedFilters = d.savedFilters.filterNot { it.id == f.id }) } }, leadingIcon = { Icon(Sym.of("trash"), null, tint = C.expense) })
              }
            }
          }
        }
      }
      group { SummaryCells("Spent" to (s.spent to C.expense), "Income" to (s.income to C.income)) }
      if (rows.isEmpty()) item { EmptyHint(if (q.isEmpty()) "Nothing here" else "No results", if (q.isEmpty()) "tray" else "magnifyingglass",
        if (q.isEmpty()) "No transactions in ${Periods.label(range, Prefs.monthStartDay)} with these filters." else "Try a payee, note, category or amount.") }
      days.forEach { (day, items) ->
        val total = items.filter { it.kind == TxnType.Expense }.sumOf { it.effectiveAmount }
        group(dayLabel(day), trailing = { if (total > 0) Text(Money.format(total, Prefs.hideAmounts), style = T.amount(17), color = C.expense) }) {
          items.forEachIndexed { i, t ->
            if (i > 0) Divider(64.dp)
            if (selecting) TxnRow(t, l, selected = t.id in selection, onToggle = { selection = if (t.id in selection) selection - t.id else selection + t.id })
            else TxnRow(t, l)
          }
        }
      }
    }
    if (selecting) {
      val chosen = db.liveTxns.filter { it.id in selection }
      var catMenu by remember { mutableStateOf(false) }
      var accMenu by remember { mutableStateOf(false) }
      Row(Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(horizontal = 20.dp, vertical = 8.dp).fillMaxWidth().height(60.dp)
        .glass(RoundedCornerShape(30.dp)).padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.weight(1f)) {
          BulkButton("square.grid.2x2.fill", "Category", chosen.isNotEmpty()) { catMenu = true }
          DropdownMenu(catMenu, { catMenu = false }, modifier = Modifier.background(C.card)) {
            DropdownMenuItem({ Text("Uncategorised", style = T.body) }, { catMenu = false; bulk(chosen, "Category changed") { it.copy(categoryId = null) } })
            db.categories.filter { it.parentId == null && it.archivedAt == null }.sortedBy { it.sortOrder }.forEach { c ->
              DropdownMenuItem({ Text(c.name, style = T.body) }, { catMenu = false; bulk(chosen.filter { it.kind != TxnType.Transfer }, "Moved to ${c.name}") { it.copy(categoryId = c.id) } },
                leadingIcon = { CategoryBadge(c.icon, c.color, 24.dp) })
            }
          }
        }
        Box(Modifier.weight(1f)) {
          BulkButton("building.columns.fill", "Account", chosen.isNotEmpty()) { accMenu = true }
          DropdownMenu(accMenu, { accMenu = false }, modifier = Modifier.background(C.card)) {
            db.accounts.filter { it.archivedAt == null }.sortedBy { it.sortOrder }.forEach { a ->
              DropdownMenuItem({ Text(a.name, style = T.body) }, { accMenu = false; bulk(chosen, "Moved to ${a.name}") { it.copy(accountId = a.id) } },
                leadingIcon = { CategoryBadge(a.icon, a.color, 24.dp) })
            }
          }
        }
        Box(Modifier.weight(1f)) {
          BulkButton("trash", "Delete", chosen.isNotEmpty(), C.expense) { bulk(chosen, "Deleted ${chosen.size}") { it.copy(deletedAt = now()) } }
        }
      }
    }
  }
  if (savingNew || naming != null) {
    var name by remember(naming, savingNew) { mutableStateOf(naming?.name ?: "") }
    AlertDialog(onDismissRequest = { savingNew = false; naming = null }, containerColor = C.card,
      title = { Text(if (naming != null) "Rename Filter" else "Save Filter", style = T.headline, color = C.label) },
      text = {
        Column {
          if (naming == null) Text("It shows as a chip above your transactions.", style = T.footnote, color = C.secondary)
          OutlinedTextField(name, { name = it }, singleLine = true, placeholder = { Text("Name") }, modifier = Modifier.padding(top = 8.dp))
        }
      },
      confirmButton = { TextButton({
        val n = name.trim()
        if (n.isNotEmpty()) {
          val target = naming
          if (target != null) Store.update { d -> d.copy(savedFilters = d.savedFilters.map { if (it.id == target.id) it.copy(name = n, updatedAt = now()) else it }) }
          else Store.update { d -> d.copy(savedFilters = d.savedFilters + SavedFilter(name = n, filters = current.json(), sortOrder = (d.savedFilters.maxOfOrNull { it.sortOrder } ?: -1) + 1)) }
        }
        savingNew = false; naming = null
      }) { Text("Save", color = C.accent, style = T.headline) } },
      dismissButton = { TextButton({ savingNew = false; naming = null }) { Text("Cancel", color = C.accent, style = T.body) } })
  }
}

@Composable private fun BulkButton(sym: String, label: String, enabled: Boolean, tint: Color = C.accent, onClick: () -> Unit) {
  Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(24.dp)).combinedClickableCompat({ if (enabled) onClick() }, {}).padding(vertical = 6.dp),
    horizontalAlignment = Alignment.CenterHorizontally) {
    Icon(Sym.of(sym), label, tint = if (enabled) tint else C.tertiary, modifier = Modifier.size(22.dp))
    Text(label, style = T.caption2.copy(fontWeight = FontWeight.Medium), color = if (enabled) tint else C.tertiary)
  }
}

@Composable fun SearchScreen() {
  val db by Store.db.collectAsState()
  val l = remember(db) { Lookups(db) }
  var q by remember { mutableStateOf("") }
  val results = if (q.isBlank()) emptyList() else db.liveTxns.filter { Search.matches(it, q, l) }.sortedByDescending { it.occurredAt }.take(200)
  PScreen("Search") {
    item { SearchField(q, { q = it }, "Search everything") }
    when {
      q.isBlank() -> item { EmptyHint("Search everything", "magnifyingglass", "Swiggy, rent, 499, a note… across every month.") }
      results.isEmpty() -> item { EmptyHint("No results for \"$q\"", "magnifyingglass", "Check the spelling or try a new search.") }
      else -> group("${results.size} results · ${Money.format(results.filter { it.kind == TxnType.Expense }.sumOf { it.effectiveAmount })} spent") {
        results.forEachIndexed { i, t -> if (i > 0) Divider(64.dp); TxnRow(t, l, showTime = false) }
      }
    }
  }
}

@Composable fun TxnDetailScreen(id: String) {
  val db by Store.db.collectAsState()
  val t = db.transactions.firstOrNull { it.id == id } ?: run { LaunchedEffect(Unit) { Ui.pop() }; return }
  val l = remember(db) { Lookups(db) }
  val (icon, color) = l.badge(t)
  val splits = db.splitEntries.filter { it.txnId == t.id }
  val ctx = androidx.compose.ui.platform.LocalContext.current
  var savingTemplate by remember { mutableStateOf(false) }
  var viewing by remember { mutableStateOf(false) }
  val receipt = remember(t.receipt) { Receipts.bitmap(ctx, t.receipt) }
  val pickPhoto = androidx.activity.compose.rememberLauncherForActivityResult(androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia()) { uri ->
    uri ?: return@rememberLauncherForActivityResult
    Receipts.save(ctx, uri, t.id)?.let { name ->
      Receipts.delete(ctx, t.receipt)
      Store.update { d -> d.copy(transactions = d.transactions.map { if (it.id == id) it.copy(receipt = name, updatedAt = now()) else it }) }
    }
  }
  PScreen("", large = false, back = true, actions = {
    Text("Edit", style = T.body, color = C.accent, modifier = Modifier.glass(CircleShape).padding(horizontal = 16.dp, vertical = 11.dp)
      .then(Modifier.combinedClickableCompat({ Ui.sheet = Sheet.Add(t.kind, editId = t.id) }, {})))
  }) {
    item {
      Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        CategoryBadge(icon, color, 64.dp)
        Text(l.title(t), style = T.title3, color = C.label, modifier = Modifier.padding(top = 10.dp))
        AmountText(t.amount, t.kind, T.amount(44, FontWeight.Bold))
        Text(java.time.Instant.ofEpochMilli(t.occurredAt).atZone(zone).format(java.time.format.DateTimeFormatter.ofPattern("EEEE, d MMMM yyyy 'at' h:mm a", java.util.Locale.ENGLISH)),
          style = T.subhead, color = C.secondary)
      }
    }
    group {
      PRow("Type", value = t.kind.label)
      if (t.kind == TxnType.Transfer) {
        Divider(); PRow("From", value = l.accounts[t.accountId]?.displayName ?: "—")
        Divider(); PRow("To", value = t.toAccountId?.let { l.accounts[it]?.displayName } ?: "—")
      } else {
        Divider(); PRow("Category", value = t.categoryId?.let { l.categories[it]?.name } ?: "Uncategorised")
        Divider(); PRow("Account", value = l.accounts[t.accountId]?.displayName ?: "—")
      }
      t.note?.takeIf { it.isNotBlank() }?.let { Divider(); PRow("Note", value = it) }
      if (!t.tags.isNullOrEmpty()) { Divider(); PRow("Tags", value = t.tags.joinToString(" ") { "#$it" }, valueColor = C.accent) }
      if (t.source != null && t.source != "manual") { Divider(); PRow("Added by", value = t.source.replaceFirstChar { it.uppercase() }) }
    }
    t.splitShare?.let { share ->
      group("Split") {
        PRow("Your share", value = Money.format(share))
        splits.forEach { e ->
          Divider(); PRow(db.friends.firstOrNull { it.id == e.friendId }?.name ?: "Friend",
            value = if (e.amount >= 0) "owes ${Money.format(e.amount)}" else "paid, you owe ${Money.format(e.amount)}",
            valueColor = if (e.amount >= 0) C.income else C.expense)
        }
      }
    }
    group("Receipt") {
      if (receipt != null) {
        androidx.compose.foundation.Image(receipt.asImageBitmap(), "Receipt", contentScale = androidx.compose.ui.layout.ContentScale.Crop,
          modifier = Modifier.fillMaxWidth().height(180.dp).padding(12.dp).clip(RoundedCornerShape(12.dp)).combinedClickableCompat({ viewing = true }, {}))
        Divider()
        PRow("Remove Receipt", titleColor = C.expense, onClick = {
          Receipts.delete(ctx, t.receipt)
          Store.update { d -> d.copy(transactions = d.transactions.map { if (it.id == id) it.copy(receipt = null) else it }) }
        })
      } else PRow("Add a Photo of the Receipt", titleColor = C.accent, leading = { Icon2("doc.text.image") }, onClick = {
        pickPhoto.launch(androidx.activity.result.PickVisualMediaRequest(androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia.ImageOnly))
      })
    }
    group {
      PRow("Edit", titleColor = C.accent, leading = { Icon2("pencil") }, onClick = { Ui.sheet = Sheet.Add(t.kind, editId = t.id) })
      Divider(56.dp); PRow("Save as Template", titleColor = C.accent, leading = { Icon2("bolt.fill") }, onClick = { savingTemplate = true })
      Divider(56.dp); PRow("Duplicate", titleColor = C.accent, leading = { Icon2("plus.square.on.square") }, onClick = { TxnOps.duplicate(t) })
      if (t.recurringId == null) { Divider(56.dp); PRow("Repeat…", titleColor = C.accent, leading = { Icon2("repeat") }, onClick = { Ui.sheet = Sheet.RecurringForm(null, t.id) }) }
      Divider(56.dp); PRow("Delete", titleColor = C.expense, leading = { Icon(Sym.of("trash"), null, tint = C.expense) }, onClick = { TxnOps.delete(t); Ui.pop() })
    }
  }
  if (savingTemplate) NameDialog("Save as template", "Name, e.g. Metro", initial = t.payee ?: "", onDismiss = { savingTemplate = false }) { n ->
    Store.update { d -> d.copy(templates = d.templates + TxnTemplate(name = n, type = t.type, amount = t.amount, accountId = t.accountId, toAccountId = t.toAccountId,
      categoryId = t.categoryId, payee = t.payee, sortOrder = (d.templates.maxOfOrNull { it.sortOrder } ?: -1) + 1)) }
    savingTemplate = false; Ui.show("Template saved")
  }
  if (viewing && receipt != null) androidx.compose.ui.window.Dialog({ viewing = false }, properties = androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false)) {
    Box(Modifier.fillMaxSize().background(Color.Black).combinedClickableCompat({ viewing = false }, {}), contentAlignment = Alignment.Center) {
      androidx.compose.foundation.Image(receipt.asImageBitmap(), "Receipt", modifier = Modifier.fillMaxWidth())
    }
  }
}

/** Receipt photos in files/receipts on this phone (not in backups). */
object Receipts {
  private fun dir(ctx: android.content.Context) = java.io.File(ctx.filesDir, "receipts").apply { mkdirs() }
  fun save(ctx: android.content.Context, uri: android.net.Uri, id: String): String? = runCatching {
    val src = ctx.contentResolver.openInputStream(uri)!!.use { android.graphics.BitmapFactory.decodeStream(it) }
    val scale = minOf(1f, 1600f / maxOf(src.width, src.height))
    val bmp = if (scale < 1f) android.graphics.Bitmap.createScaledBitmap(src, (src.width * scale).toInt(), (src.height * scale).toInt(), true) else src
    val name = "$id-${System.currentTimeMillis() / 1000}.jpg"
    java.io.File(dir(ctx), name).outputStream().use { bmp.compress(android.graphics.Bitmap.CompressFormat.JPEG, 75, it) }
    name
  }.getOrNull()
  fun delete(ctx: android.content.Context, name: String?) { name?.let { java.io.File(dir(ctx), it).delete() } }
  fun bitmap(ctx: android.content.Context, name: String?): android.graphics.Bitmap? =
    name?.let { java.io.File(dir(ctx), it) }?.takeIf { it.exists() }?.let { android.graphics.BitmapFactory.decodeFile(it.path) }
}
