package com.paisapulse.app.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.paisapulse.app.data.*
import com.paisapulse.app.logic.*
import com.paisapulse.app.ui.*
import java.time.LocalDate
import java.time.format.TextStyle
import java.util.Locale
import kotlin.math.sqrt

@Composable fun InsightsScreen() {
  val db by Store.db.collectAsState()
  val l = remember(db) { Lookups(db) }
  var offset by remember { mutableIntStateOf(0) }
  var kind by remember { mutableStateOf(PeriodKind.Month) }
  var customStart by remember { mutableStateOf(LocalDate.now().minusDays(29)) }
  var customEnd by remember { mutableStateOf(LocalDate.now()) }
  var picking by remember { mutableStateOf<Int?>(null) }
  val custom = Range(minOf(customStart, customEnd).ms(), maxOf(customStart, customEnd).plusDays(1).ms())
  fun period(o: Int) = kind.range(o, Prefs.monthStartDay, Prefs.weekStartDay, custom)
  val range = period(offset)
  val s = Ledger.summary(db.transactions, range)
  val p = Ledger.summary(db.transactions, period(offset - 1))
  val months = (5 downTo 0).map { i -> period(offset - i).let { Triple(kind.short(it), Ledger.summary(db.transactions, it).spent, i == 0) } }
  val cats = Ledger.byCategory(db.transactions, range, l.categories)
  val days = maxOf(1L, java.time.temporal.ChronoUnit.DAYS.between(range.start.toDate(), minOf(range.end, now()).toDate()))
  PScreen("Insights", back = true, actions = {
    GlassIcon("chevron.left", "Previous ${kind.noun}") { offset-- }
    GlassIcon("chevron.right", "Next ${kind.noun}", tint = if (offset < 0) C.accent else C.tertiary) { if (offset < 0) offset++ }
  }) {
    item {
      Segmented(PeriodKind.entries.map { it.label }, kind.ordinal, Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) { kind = PeriodKind.entries[it]; offset = 0 }
    }
    if (kind == PeriodKind.Custom) group {
      PRow("From", value = shortDate.format(customStart), valueColor = C.accent, onClick = { picking = 0 })
      Divider(); PRow("To", value = shortDate.format(customEnd), valueColor = C.accent, onClick = { picking = 1 })
    }
    group {
      Column(Modifier.padding(20.dp)) {
        Text("Spent in ${kind.label(range, Prefs.monthStartDay)}", style = T.subhead, color = C.secondary)
        Text(Money.format(s.spent), style = T.amount(36, FontWeight.Bold), color = C.label)
        Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(18.dp)) {
          Stat("Per day", Money.format(s.spent / days), C.label)
          if (p.spent > 0) { val ch = (s.spent - p.spent).toDouble() / p.spent
            Stat("vs last ${kind.noun}", "${if (ch >= 0) "up" else "down"} ${(kotlin.math.abs(ch) * 100).toInt()}%", if (ch > 0) C.expense else C.income) }
          Stat("Kept", Money.format(maxOf(0, s.saved)), C.income)
        }
      }
    }
    group("Last 6 ${kind.noun}s") {
      val max = maxOf(1L, months.maxOf { it.second })
      val accent = C.accent; val label = C.secondary
      Column(Modifier.padding(16.dp)) {
        Row(Modifier.fillMaxWidth().height(160.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Bottom) {
          months.forEach { (_, v, cur) ->
            Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
              Text(Money.compact(v), style = T.caption2, color = label, maxLines = 1)
              Box(Modifier.fillMaxWidth().fillMaxHeight((v.toFloat() / max).coerceAtLeast(0.02f) * 0.85f).clip(RoundedCornerShape(6.dp))
                .background(if (cur) accent else accent.copy(alpha = 0.35f)))
            }
          }
        }
        Row(Modifier.fillMaxWidth().padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
          months.forEach { (name, _, _) -> Text(name, style = T.caption2, color = label, maxLines = 1,
            modifier = Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.Center) }
        }
      }
    }
    if (cats.isNotEmpty()) group("Where it went") {
      val total = cats.sumOf { it.second }.toFloat()
      val colors = cats.map { hex(l.categories[it.first]?.color ?: "#8E8E93") }
      Box(Modifier.fillMaxWidth().height(200.dp).padding(16.dp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(170.dp)) {
          var a = -90f
          cats.forEachIndexed { i, (_, v) -> val sw = 360f * v / total
            drawArc(colors[i], a + 0.8f, (sw - 1.6f).coerceAtLeast(0.5f), false, style = Stroke(32.dp.toPx())); a += sw }
        }
      }
      cats.forEachIndexed { i, (id, v) ->
        Divider(64.dp)
        val c = l.categories[id]
        PRow(c?.name ?: "Uncategorised", leading = { CategoryBadge(c?.icon ?: "questionmark", c?.color, 30.dp) }) {
          Column(horizontalAlignment = Alignment.End) {
            Text(Money.format(v), style = T.amount(17), color = C.expense)
            Text("${(v * 100 / maxOf(1, s.spent))}%", style = T.caption, color = C.secondary)
          }
        }
      }
    }
    val biggest = db.liveTxns.filter { it.kind == TxnType.Expense && it.occurredAt in range }.sortedByDescending { it.effectiveAmount }.take(5)
    if (biggest.isNotEmpty()) group("Biggest expenses") { biggest.forEachIndexed { i, t -> if (i > 0) Divider(64.dp); TxnRow(t, l, showTime = false) } }
  }
  picking?.let { which ->
    DayPickerDialog(if (which == 0) customStart else customEnd, onDismiss = { picking = null }) { d -> if (which == 0) customStart = d else customEnd = d; picking = null }
  }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable fun DayPickerDialog(initial: LocalDate, onDismiss: () -> Unit, onPick: (LocalDate) -> Unit) {
  val state = rememberDatePickerState(initialSelectedDateMillis = initial.atStartOfDay(java.time.ZoneOffset.UTC).toInstant().toEpochMilli())
  DatePickerDialog(onDismissRequest = onDismiss, confirmButton = {
    TextButton({ state.selectedDateMillis?.let { onPick(java.time.Instant.ofEpochMilli(it).atZone(java.time.ZoneOffset.UTC).toLocalDate()) } ?: onDismiss() }) {
      Text("Done", color = C.accent, style = T.headline)
    }
  }, dismissButton = { TextButton(onDismiss) { Text("Cancel", color = C.accent, style = T.body) } }) { DatePicker(state) }
}

@Composable fun CalendarScreen() {
  val db by Store.db.collectAsState()
  val l = remember(db) { Lookups(db) }
  var month by remember { mutableStateOf(LocalDate.now().withDayOfMonth(1)) }
  var selected by remember { mutableStateOf(LocalDate.now()) }
  val range = Range(month.ms(), month.plusMonths(1).ms())
  val daily = Ledger.dailySpend(db.transactions, range)
  val max = maxOf(1L, daily.values.maxOrNull() ?: 1L)
  val lead = (month.dayOfWeek.value % 7) // Sunday first
  val cells: List<LocalDate?> = List(lead) { null } + (0 until month.lengthOfMonth()).map { month.plusDays(it.toLong()) }
  val s = Ledger.summary(db.transactions, range)
  val dayTxns = db.liveTxns.filter { it.occurredAt.toDate() == selected }.sortedByDescending { it.occurredAt }
  PScreen(month.month.getDisplayName(TextStyle.FULL, Locale.ENGLISH) + " " + month.year, back = true, actions = {
    GlassIcon("chevron.up", "Previous month") { month = month.minusMonths(1); selected = month }
    GlassIcon("chevron.down", "Next month") { month = month.plusMonths(1); selected = month }
  }) {
    group(footer = "Redder days are bigger spending days.") {
      SummaryCells("Spent" to (s.spent to C.expense), "Income" to (s.income to C.income))
      Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row { listOf("S", "M", "T", "W", "T", "F", "S").forEach { Text(it, style = T.caption2.copy(fontWeight = FontWeight.SemiBold), color = C.secondary,
          modifier = Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.Center) } }
        cells.chunked(7).forEach { week ->
          Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            (week + List(7 - week.size) { null }).forEach { d ->
              if (d == null) Spacer(Modifier.weight(1f).height(44.dp)) else {
                val spent = daily[d] ?: 0
                val heat = if (spent > 0) 0.15f + 0.75f * sqrt(spent.toFloat() / max) else 0f
                Column(Modifier.weight(1f).height(44.dp).clip(RoundedCornerShape(8.dp)).background(C.expense.copy(alpha = heat))
                  .then(if (d == selected) Modifier.border(2.dp, C.accent, RoundedCornerShape(8.dp)) else Modifier).clickable { selected = d },
                  horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                  Text("${d.dayOfMonth}", style = T.subhead.copy(fontWeight = if (d == LocalDate.now()) FontWeight.Bold else FontWeight.Normal), color = C.label)
                  Text(if (spent > 0) Money.compact(spent).drop(1) else " ", style = T.caption2.copy(fontSize = 9.sp), color = C.secondary)
                }
              }
            }
          }
        }
      }
    }
    group(dayLabel(selected)) {
      if (dayTxns.isEmpty()) PRow("Nothing on this day", titleColor = C.secondary)
      dayTxns.forEach { t -> TxnRow(t, l); Divider(64.dp) }
      PRow("Add on ${shortDate.format(selected)}", titleColor = C.accent, leading = { Icon2("plus") },
        onClick = { Ui.sheet = Sheet.Add(date = selected.atTime(12, 0).atZone(zone).toInstant().toEpochMilli()) })
    }
  }
}

@Composable fun NetWorthScreen() {
  val db by Store.db.collectAsState()
  val pts = (11 downTo 0).map { i ->
    val end = LocalDate.now().minusMonths(i.toLong()).plusDays(1).ms()
    end to Ledger.netWorth(db.accounts, Ledger.balances(db.accounts, db.transactions.filter { it.occurredAt <= end }))
  }
  val accent = C.accent
  PScreen("Net Worth", back = true) {
    group(footer = "Rebuilt from your transactions and each account's starting balance.") {
      Canvas(Modifier.fillMaxWidth().height(240.dp).padding(20.dp)) {
        val min = pts.minOf { it.second }.toFloat(); val max = pts.maxOf { it.second }.toFloat(); val span = (max - min).coerceAtLeast(1f)
        val step = size.width / (pts.size - 1)
        val line = Path(); val area = Path()
        pts.forEachIndexed { i, (_, v) ->
          val x = i * step; val y = size.height - (v - min) / span * size.height
          if (i == 0) { line.moveTo(x, y); area.moveTo(x, size.height); area.lineTo(x, y) } else { line.lineTo(x, y); area.lineTo(x, y) }
        }
        area.lineTo(size.width, size.height); area.close()
        drawPath(area, Brush.verticalGradient(listOf(accent.copy(alpha = 0.35f), accent.copy(alpha = 0f))))
        drawPath(line, accent, style = Stroke(3.dp.toPx()))
      }
    }
    group {
      pts.reversed().take(6).forEachIndexed { i, (t, v) ->
        if (i > 0) Divider()
        PRow(t.toDate().minusDays(1).let { it.month.getDisplayName(TextStyle.FULL, Locale.ENGLISH) + " " + it.year }, value = Money.format(v), valueColor = if (v < 0) C.expense else C.label)
      }
    }
  }
}
