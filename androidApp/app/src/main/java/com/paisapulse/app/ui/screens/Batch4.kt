package com.paisapulse.app.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.paisapulse.app.data.*
import com.paisapulse.app.logic.*
import com.paisapulse.app.ui.*
import kotlinx.coroutines.launch
import java.time.format.TextStyle
import java.util.Locale

// Templates, tags, monthly recap, month-end forecast, Home layout and investment values.
// Same screens on iPhone (apple/App/More/Batch4Views.swift).

@Composable fun ForecastCard(f: Forecast.Result) {
  val hidden = Prefs.hideAmounts
  Column(Modifier.fillMaxWidth().padding(16.dp)) {
    Row(verticalAlignment = Alignment.Bottom) {
      Column(Modifier.weight(1f)) {
        Text("Likely by month-end", style = T.subhead, color = C.secondary)
        Text(Money.format(f.projected, hidden), style = T.amount(28, FontWeight.Bold), color = if (f.projected < 0) C.expense else C.label)
      }
      Column(horizontalAlignment = Alignment.End) {
        Text("Now", style = T.caption, color = C.secondary)
        Text(Money.format(f.now, hidden), style = T.amount(15), color = C.label)
      }
    }
    Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
      if (f.incoming > 0) Stat2("Coming in", Money.format(f.incoming, hidden), C.income)
      if (f.outgoing > 0) Stat2("Bills", Money.format(f.outgoing, hidden), C.expense)
      Stat2("Everyday · ${f.daysLeft}d", Money.format(f.dailySpend * f.daysLeft, hidden), C.secondary)
    }
  }
}

@Composable private fun Stat2(label: String, value: String, color: Color) {
  Column {
    Text(label, style = T.caption2, color = C.secondary)
    Text(value, style = T.amount(13), color = color)
  }
}

// MARK: Templates

@Composable fun TemplatesScreen() {
  val db by Store.db.collectAsState()
  val l = remember(db) { Lookups(db) }
  val items = remember {
    mutableStateListOf(*db.templates.sortedBy { it.sortOrder }.map { t ->
      val c = t.categoryId?.let { l.categories[it] }
      ReorderItem(t.id, t.name, c?.icon ?: "bolt.fill", c?.color ?: "#5E5CE6")
    }.toTypedArray())
  }
  // Save the dragged order when leaving the screen.
  DisposableEffect(Unit) {
    onDispose {
      val order = items.mapIndexed { i, it -> it.id to i }.toMap()
      Store.update { d -> d.copy(templates = d.templates.map { t -> order[t.id]?.let { t.copy(sortOrder = it) } ?: t }) }
    }
  }
  PScreen("Templates", back = true) {
    if (items.isEmpty()) item {
      EmptyHint("No templates yet", "bolt", "Open any transaction and tap Save as Template. Templates add in one tap from Home and Quick Add.")
    } else item {
      Text("Hold and drag the handle to move. Tap the bin to delete.", style = T.footnote, color = C.secondary, modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
      ReorderColumn(items) { item ->
        val t = db.templates.firstOrNull { it.id == item.id }
        if (t != null) AmountText(t.amount, TxnType.of(t.type), T.amount(15))
        Icon(Sym.of("trash"), "Delete ${item.name}", tint = C.expense, modifier = Modifier.padding(horizontal = 10.dp).size(20.dp).clickable {
          items.remove(item)
          Store.update { d -> d.copy(templates = d.templates.filterNot { it.id == item.id }) }
        })
      }
    }
  }
}

// MARK: Tags

@Composable fun TagsScreen() {
  val db by Store.db.collectAsState()
  val groups = remember(db) {
    db.liveTxns.flatMap { t -> t.tags.orEmpty().map { it to t } }.groupBy({ it.first }, { it.second })
  }
  PScreen("Tags", back = true) {
    if (groups.isEmpty()) item { EmptyHint("No tags yet", "number", "Add tags like \"goa trip\" or \"work\" in Quick Add to total things that span categories.") }
    else group {
      groups.keys.sorted().forEachIndexed { i, tag ->
        val list = groups[tag].orEmpty()
        if (i > 0) Divider()
        PRow("#$tag", titleColor = C.accent, chevron = true, onClick = { Ui.push(Route.TagDetail(tag)) }) {
          Column(horizontalAlignment = Alignment.End) {
            Text(Money.format(list.filter { it.kind == TxnType.Expense }.sumOf { it.effectiveAmount }, Prefs.hideAmounts), style = T.amount(15), color = C.label)
            Text("${list.size} transactions", style = T.caption2, color = C.secondary)
          }
        }
      }
    }
  }
}

@Composable fun TagDetailScreen(tag: String) {
  val db by Store.db.collectAsState()
  val l = remember(db) { Lookups(db) }
  val list = db.liveTxns.filter { tag in it.tags.orEmpty() }.sortedByDescending { it.occurredAt }
  val expenses = list.filter { it.kind == TxnType.Expense }
  val byCat = expenses.groupBy { Ledger.topLevel(it.categoryId, l.categories) }.mapValues { (_, v) -> v.sumOf { it.effectiveAmount } }.entries.sortedByDescending { it.value }
  PScreen("#$tag", back = true) {
    group {
      Column(Modifier.padding(20.dp)) {
        Text("Spent on #$tag", style = T.subhead, color = C.secondary)
        Text(Money.format(expenses.sumOf { it.effectiveAmount }), style = T.amount(36, FontWeight.Bold), color = C.label)
        if (list.isNotEmpty()) Text("${shortDate.format(list.last().occurredAt.toDate())} – ${shortDate.format(list.first().occurredAt.toDate())}", style = T.footnote, color = C.secondary)
      }
    }
    if (byCat.size > 1) group("By category") {
      byCat.forEachIndexed { i, (id, amount) ->
        if (i > 0) Divider(56.dp)
        val c = l.categories[id]
        PRow(c?.name ?: "Uncategorised", value = Money.format(amount), leading = { CategoryBadge(c?.icon ?: "questionmark", c?.color ?: "#8E8E93", 26.dp) })
      }
    }
    group("Transactions") { list.forEachIndexed { i, t -> if (i > 0) Divider(64.dp); TxnRow(t, l) } }
  }
}

// MARK: Recap

@Composable fun RecapScreen(start: Int) {
  val db by Store.db.collectAsState()
  val l = remember(db) { Lookups(db) }
  val ctx = LocalContext.current
  val scope = rememberCoroutineScope()
  val layer = rememberGraphicsLayer()
  var offset by remember { mutableIntStateOf(start) }
  val month = Periods.month(offset, Prefs.monthStartDay)
  val r = Recap.make(db.liveTxns, l.categories, month, Periods.month(offset - 1, Prefs.monthStartDay))
  val d = month.start.toDate()
  val title = d.month.getDisplayName(TextStyle.FULL, Locale.ENGLISH) + " " + d.year
  val biggest = r.biggestId?.let { id -> db.transactions.firstOrNull { it.id == id } }
  val bg = C.background
  PScreen("Recap", back = true, large = false, actions = {
    GlassIcon("chevron.left", "Previous month") { offset-- }
    GlassIcon("chevron.right", "Next month", tint = if (offset < 0) C.accent else C.tertiary) { if (offset < 0) offset++ }
  }) {
    item {
      Box(Modifier.drawWithContent { layer.record { this@drawWithContent.drawContent() }; drawLayer(layer) }.background(bg).padding(16.dp)) {
        RecapCard(r, title, l, biggest)
      }
    }
    item {
      Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Button({ scope.launch { shareBitmap(ctx, layer.toImageBitmap().asAndroidBitmap(), "Share your month", "recap.png") } },
          colors = ButtonDefaults.buttonColors(containerColor = C.accent), modifier = Modifier.fillMaxWidth().height(50.dp)) {
          Icon(Sym.of("square.and.arrow.up"), null, modifier = Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)); Text("Share", style = T.headline)
        }
        Text("The picture shows totals only, no account names.", style = T.caption, color = C.secondary, modifier = Modifier.padding(top = 6.dp, bottom = 24.dp))
      }
    }
  }
}

@Composable fun RecapCard(r: Recap.Result, title: String, l: Lookups, biggest: Txn?) {
  val top = r.topCategoryId?.let { l.categories[it] }
  Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(24.dp))
      .background(Brush.linearGradient(listOf(hex("#5E5CE6"), hex("#AF52DE")))).padding(20.dp)) {
      Text(title, style = T.headline, color = Color.White.copy(alpha = 0.85f))
      Text(Money.format(r.spent), style = T.amount(44, FontWeight.Bold), color = Color.White, maxLines = 1)
      r.change?.let { ch ->
        Text(if (ch >= 0) "${Math.round(ch * 100)}% more than last month" else "${Math.round(-ch * 100)}% less than last month",
          style = T.subhead.copy(fontWeight = FontWeight.Medium), color = Color.White.copy(alpha = 0.9f))
      }
    }
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
      RecapTile("Top category", top?.name ?: "—", Money.format(r.topCategoryAmount), top?.icon ?: "chart.pie.fill", top?.color ?: "#FF9500", Modifier.weight(1f))
      RecapTile(if (r.saved >= 0) "Saved" else "Overspent", Money.format(kotlin.math.abs(r.saved)), "of ${Money.format(r.income)} income", "banknote.fill",
        if (r.saved >= 0) "#34C759" else "#E5484D", Modifier.weight(1f))
    }
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
      RecapTile("No-spend days", "${r.noSpendDays} of ${r.days}", "Best streak ${r.longestNoSpendStreak} days", "leaf.fill", "#30B0C7", Modifier.weight(1f))
      RecapTile("Favourite place", r.topPayee ?: "—", if (r.topPayeeCount > 1) "${r.topPayeeCount} times" else "", "storefront.fill", "#FF2D55", Modifier.weight(1f))
    }
    if (biggest != null) Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(C.card).padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
      Column(Modifier.weight(1f)) {
        Text("Biggest expense", style = T.caption, color = C.secondary)
        Text(l.title(biggest), style = T.subhead.copy(fontWeight = FontWeight.SemiBold), color = C.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
      }
      Text(Money.format(biggest.effectiveAmount), style = T.amount(17), color = C.expense)
    }
    Text("${r.count} transactions · Paisa Pulse", style = T.caption, color = C.secondary, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
  }
}

@Composable private fun RecapTile(label: String, value: String, detail: String, icon: String, color: String, modifier: Modifier) {
  Column(modifier.heightIn(min = 112.dp).clip(RoundedCornerShape(18.dp)).background(C.card).padding(14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
    CategoryBadge(icon, color, 28.dp)
    Text(label, style = T.caption, color = C.secondary)
    Text(value, style = T.subhead.copy(fontWeight = FontWeight.SemiBold), color = C.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
    if (detail.isNotEmpty()) Text(detail, style = T.caption2, color = C.secondary, maxLines = 1)
  }
}

// MARK: Home layout

@Composable fun HomeLayoutSheet() {
  fun itemsFor(order: List<String>) = order.map { k -> HomeSections.all.first { it.first == k }.let { ReorderItem(it.first, it.second, it.third, "#5E5CE6") } }
  val items = remember { mutableStateListOf(*itemsFor(HomeSections.order(Prefs.homeOrder)).toTypedArray()) }
  var hidden by remember { mutableStateOf(HomeSections.hidden(Prefs.homeHidden)) }
  PSheet({ Ui.sheet = null }) {
    SheetHeader("Home Screen", saveLabel = "Done", onCancel = { Ui.sheet = null }) {
      Prefs.set("homeOrder", items.joinToString(",") { it.id })
      Prefs.set("homeHidden", hidden.sorted().joinToString(","))
      Ui.sheet = null
    }
    Text("Drag to reorder, switch off what you don't need.", style = T.footnote, color = C.secondary, modifier = Modifier.padding(horizontal = 20.dp))
    Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(vertical = 12.dp)) {
      ReorderColumn(items) { item ->
        Switch(item.id !in hidden, { on -> hidden = if (on) hidden - item.id else hidden + item.id },
          colors = SwitchDefaults.colors(checkedTrackColor = hex("#34C759"), checkedThumbColor = Color.White,
            uncheckedTrackColor = C.fill, uncheckedThumbColor = Color.White, uncheckedBorderColor = Color.Transparent, checkedBorderColor = Color.Transparent),
          modifier = Modifier.padding(end = 8.dp))
      }
      Text("Reset to Default", style = T.body, color = C.accent, textAlign = TextAlign.Center,
        modifier = Modifier.fillMaxWidth().clickable { items.clear(); items.addAll(itemsFor(HomeSections.all.map { it.first })); hidden = emptySet() }.padding(18.dp))
    }
  }
}

// MARK: Investment values

/** Investments: record what the account is worth today (Groww, mutual funds, PF). */
fun androidx.compose.foundation.lazy.LazyListScope.valuationSection(account: Account, all: List<Valuation>) {
  val list = all.filter { it.accountId == account.id }.sortedByDescending { it.at }
  group("Value", footer = "Money you move in later is added on top of the last value. Update it whenever you check your app. Long-press a value to delete it.") {
    var updating by remember { mutableStateOf(false) }
    PRow("Update Value", titleColor = C.accent, leading = { Icon2("arrow.triangle.2.circlepath") }, onClick = { updating = true })
    if (list.size > 1) {
      Divider()
      val accent = C.accent
      val pts = list.reversed()
      Canvas(Modifier.fillMaxWidth().height(160.dp).padding(20.dp)) {
        val min = pts.minOf { it.value }.toFloat(); val max = pts.maxOf { it.value }.toFloat(); val span = (max - min).coerceAtLeast(1f)
        val t0 = pts.first().at.toFloat(); val tSpan = (pts.last().at - pts.first().at).toFloat().coerceAtLeast(1f)
        val line = Path(); val area = Path()
        pts.forEachIndexed { i, v ->
          val x = (v.at - t0) / tSpan * size.width; val y = size.height - (v.value - min) / span * size.height
          if (i == 0) { line.moveTo(x, y); area.moveTo(x, size.height); area.lineTo(x, y) } else { line.lineTo(x, y); area.lineTo(x, y) }
          drawCircle(accent, 3.dp.toPx(), androidx.compose.ui.geometry.Offset(x, y))
        }
        area.lineTo(size.width, size.height); area.close()
        drawPath(area, Brush.verticalGradient(listOf(accent.copy(alpha = 0.3f), accent.copy(alpha = 0f))))
        drawPath(line, accent, style = Stroke(2.5.dp.toPx()))
      }
    }
    list.take(6).forEach { v ->
      Divider()
      PRow(shortDate.format(v.at.toDate()) + " " + v.at.toDate().year, value = Money.format(v.value), onLongClick = {
        Store.update { d -> d.copy(valuations = d.valuations.filterNot { it.id == v.id }) }
        Ui.show("Value deleted") { Store.update { d -> d.copy(valuations = d.valuations + v) } }
      })
    }
    if (updating) NameDialog("What's it worth today?", "Current value", keyboard = KeyboardType.Decimal, onDismiss = { updating = false }) { text ->
      Money.parse(text)?.let { p ->
        Store.update { d -> d.copy(valuations = d.valuations + Valuation(accountId = account.id, value = p)) }
        com.paisapulse.app.work.Services.refreshWidget()
      }
      updating = false
    }
  }
}
