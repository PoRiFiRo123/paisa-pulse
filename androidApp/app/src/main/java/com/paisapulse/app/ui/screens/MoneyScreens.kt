package com.paisapulse.app.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.paisapulse.app.R
import com.paisapulse.app.data.*
import com.paisapulse.app.logic.*
import com.paisapulse.app.ui.*
import com.paisapulse.app.work.BackupOps
import kotlinx.coroutines.launch

// Currency picker, bank picker, multi-currency converter, main currency, accent colour, app icon,
// and the Insights sections. Same screens on iPhone (apple/App/More/MoneyViews.swift).

/** Every currency, searchable, popular first. */
@Composable fun CurrencyPickerDialog(title: String, exclude: Set<String> = emptySet(), onDismiss: () -> Unit, onPick: (String) -> Unit) {
  var q by remember { mutableStateOf("") }
  val query = q.trim().lowercase()
  val codes = World.currencies.map { it.first }.filter { it !in exclude }.filter { code ->
    query.isEmpty() || code.lowercase().contains(query) || World.currencyName(code).lowercase().contains(query) ||
      World.countries.any { it.currency == code && it.name.lowercase().contains(query) }
  }
  val popular = listOf("INR", "USD", "EUR", "GBP", "AED", "SGD", "THB").filter { it !in exclude }
  AlertDialog(onDismiss, containerColor = C.card, confirmButton = { TextButton(onDismiss) { Text("Cancel", color = C.accent) } },
    title = { Text(title, style = T.headline, color = C.label) },
    text = {
      Column {
        OutlinedTextField(q, { q = it }, singleLine = true, placeholder = { Text("Currency or country") }, modifier = Modifier.fillMaxWidth())
        LazyColumn(Modifier.heightIn(max = 440.dp).padding(top = 8.dp)) {
          if (query.isEmpty()) {
            item { Text("Popular", style = T.footnote, color = C.secondary, modifier = Modifier.padding(vertical = 6.dp)) }
            items(popular) { CurrencyRow(it) { onPick(it) } }
            item { Text("All currencies", style = T.footnote, color = C.secondary, modifier = Modifier.padding(vertical = 6.dp)) }
          }
          items(codes) { CurrencyRow(it) { onPick(it) } }
        }
      }
    })
}

@Composable private fun CurrencyRow(code: String, onClick: () -> Unit) {
  Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
    Text(World.symbol(code), style = T.headline, color = C.accent, modifier = Modifier.width(52.dp))
    Column(Modifier.weight(1f)) {
      Text(World.currencyName(code), style = T.body, color = C.label, maxLines = 1)
      Text((listOf(code) + World.countries.filter { it.currency == code }.take(3).map { it.name }).joinToString(" · "), style = T.caption, color = C.secondary, maxLines = 1)
    }
    if (code == Money.base) Text("Main", style = T.caption, color = C.secondary)
  }
}

/** Indian banks (or wallets) with their colours; popular first, search, or type your own. */
@Composable fun BankPickerDialog(wallets: Boolean, selected: String?, onDismiss: () -> Unit, onPick: (String, Banks.Bank?) -> Unit) {
  var q by remember { mutableStateOf("") }
  val query = q.trim().lowercase()
  val list = Banks.all.filter { if (wallets) it.kind == "wallet" else it.kind != "wallet" }
  val found = list.filter { query.isEmpty() || it.short.lowercase().contains(query) || it.name.lowercase().contains(query) }
  val popular = if (query.isEmpty() && !wallets) Banks.popular.mapNotNull { Banks.byId(it) } else emptyList()
  AlertDialog(onDismiss, containerColor = C.card, confirmButton = { TextButton(onDismiss) { Text("Cancel", color = C.accent) } },
    title = { Text(if (wallets) "Wallet" else "Bank", style = T.headline, color = C.label) },
    text = {
      Column {
        OutlinedTextField(q, { q = it }, singleLine = true, placeholder = { Text(if (wallets) "Search wallets" else "Search banks") }, modifier = Modifier.fillMaxWidth())
        LazyColumn(Modifier.heightIn(max = 440.dp).padding(top = 8.dp)) {
          if (popular.isNotEmpty()) {
            item { Text("Popular", style = T.footnote, color = C.secondary, modifier = Modifier.padding(vertical = 6.dp)) }
            items(popular) { b -> BankRow(b, Banks.match(selected)?.id == b.id) { onPick(b.short, b) } }
            item { Text("All banks", style = T.footnote, color = C.secondary, modifier = Modifier.padding(vertical = 6.dp)) }
          }
          items(found.filter { it !in popular }) { b -> BankRow(b, Banks.match(selected)?.id == b.id) { onPick(b.short, b) } }
          if (query.isNotEmpty() && list.none { it.short.lowercase() == query || it.name.lowercase() == query }) item {
            Text("Use \"${q.trim()}\"", style = T.body, color = C.accent, modifier = Modifier.fillMaxWidth().clickable { onPick(q.trim(), null) }.padding(vertical = 12.dp))
          }
        }
      }
    })
}

@Composable private fun BankRow(b: Banks.Bank, on: Boolean, onClick: () -> Unit) {
  Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
    Box(Modifier.size(34.dp).clip(RoundedCornerShape(9.dp)).background(hex(b.color)), contentAlignment = Alignment.Center) {
      Text(b.short.take(1), style = T.headline, color = Color.White)
    }
    Spacer(Modifier.width(12.dp))
    Column(Modifier.weight(1f)) {
      Text(b.short, style = T.body, color = C.label)
      if (b.name != b.short) Text(b.name, style = T.caption, color = C.secondary, maxLines = 1)
    }
    if (on) Icon(Sym.of("checkmark"), null, tint = C.accent)
  }
}

/** Compare one amount across many currencies. Tap a row to type in that currency. */
@Composable fun ConverterScreen() {
  val ctx = LocalContext.current
  val scope = rememberCoroutineScope()
  val base = Money.base
  var codes by remember { mutableStateOf(listOf(base) + Prefs.converterCurrencies.split(",").filter { it.isNotBlank() && it != base }) }
  var active by remember { mutableStateOf(base) }
  var amount by remember { mutableStateOf("100") }
  var rates by remember { mutableStateOf(Currency.cached(ctx)) }
  var loading by remember { mutableStateOf(false) }
  var adding by remember { mutableStateOf(false) }
  LaunchedEffect(Unit) { if (rates == null || System.currentTimeMillis() - (rates?.at ?: 0) > Currency.MAX_AGE) rates = Currency.rates(ctx) }
  fun persist(list: List<String>) { codes = list; Prefs.set("converterCurrencies", list.filter { it != base }.joinToString(",")) }
  val v = amount.replace(",", "").toDoubleOrNull() ?: 0.0
  PScreen("Converter", back = true) {
    group(footer = "Tap a currency to type in it. Hold a row to remove it, use the arrows to reorder.") {
      codes.forEachIndexed { i, code ->
        if (i > 0) Divider(68.dp)
        val r = rates?.let { Fx.rate(active, code, it.inrPer) }
        val isActive = code == active
        Row(Modifier.fillMaxWidth().background(if (isActive) C.accent.copy(alpha = 0.08f) else Color.Transparent)
          .clickable {
            if (!isActive) { r?.let { amount = "%.2f".format(v * it).removeSuffix(".00") }; active = code }
          }.padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
          Text(World.symbol(code), style = T.headline, color = if (isActive) C.accent else C.secondary, modifier = Modifier.width(44.dp))
          Column(Modifier.weight(1f)) {
            Text(code, style = T.subhead.copy(fontWeight = FontWeight.SemiBold), color = C.label)
            Text(World.currencyName(code), style = T.caption, color = C.secondary, maxLines = 1)
          }
          if (isActive) {
            FieldRow(amount, { amount = it }, "0", number = true, modifier = Modifier.width(150.dp), padding = PaddingValues(0.dp))
          } else Column(horizontalAlignment = Alignment.End) {
            Text(r?.let { Money.format(Math.round(v * it * 100), code) } ?: "—", style = T.amount(18, FontWeight.SemiBold), color = C.label)
            rates?.let { Fx.rate(code, active, it.inrPer) }?.let { one ->
              Text("1 $code = ${World.symbol(active)}${if (one < 1) "%.4f".format(one) else "%.2f".format(one)}", style = T.caption2, color = C.secondary)
            }
          }
          if (code != base) Column(Modifier.padding(start = 6.dp)) {
            if (i > 1) Icon(Sym.of("chevron.up"), "Move up", tint = C.tertiary, modifier = Modifier.size(18.dp).clickable { persist(codes.toMutableList().apply { add(i - 1, removeAt(i)) }) })
            if (i < codes.lastIndex) Icon(Sym.of("chevron.down"), "Move down", tint = C.tertiary, modifier = Modifier.size(18.dp).clickable { persist(codes.toMutableList().apply { add(i + 1, removeAt(i)) }) })
            Icon(Sym.of("xmark"), "Remove", tint = C.tertiary, modifier = Modifier.size(18.dp).clickable { persist(codes - code); if (active == code) active = base })
          }
        }
      }
      Divider()
      PRow("Add Currency", titleColor = C.accent, leading = { Icon(Sym.of("plus.circle.fill"), null, tint = C.accent) }, onClick = { adding = true })
    }
    group(footer = rates?.let { "Mid-market rates from open.er-api.com, updated ${shortDate.format(java.time.Instant.ofEpochMilli(it.at).atZone(java.time.ZoneId.systemDefault()).toLocalDate())}. Banks and forex cards add a markup." }
      ?: "Rates need an internet connection the first time. Only currency codes are requested.") {
      PRow(if (loading) "Refreshing…" else "Refresh Rates", titleColor = C.accent, onClick = { scope.launch { loading = true; rates = Currency.rates(ctx, true); loading = false } })
    }
  }
  if (adding) CurrencyPickerDialog("Add Currency", exclude = codes.toSet(), onDismiss = { adding = false }) { persist(codes + it); adding = false }
}

/** Settings › Main Currency: every amount is stored in it. Changing it converts at today's rate, or just relabels. */
@Composable fun MainCurrencyScreen() {
  val ctx = LocalContext.current
  val scope = rememberCoroutineScope()
  val base = Prefs.baseCurrency
  var picking by remember { mutableStateOf(false) }
  var pending by remember { mutableStateOf<String?>(null) }
  var rate by remember { mutableStateOf<Double?>(null) }
  PScreen("Main Currency", back = true) {
    group(footer = "Totals, budgets and net worth are shown in this currency. Spends in other currencies keep their original amount too. ₹ uses lakh and crore; other currencies use thousands.") {
      PRow(World.currencyName(base), subtitle = base, leading = { Text(World.symbol(base), style = T.amount(24, FontWeight.Bold), color = C.label, modifier = Modifier.width(52.dp)) },
        chevron = true, onClick = { picking = true })
    }
  }
  if (picking) CurrencyPickerDialog("Main Currency", exclude = setOf(base), onDismiss = { picking = false }) { code ->
    picking = false; pending = code; rate = null
    scope.launch { rate = Currency.rates(ctx)?.let { Fx.rate(base, code, it.inrPer) } }
  }
  pending?.let { code ->
    AlertDialog({ pending = null }, containerColor = C.card, title = { Text("Change to $code?", style = T.headline, color = C.label) },
      text = { Text(if (rate == null) "Rates aren't loaded (offline?), so amounts can only keep their numbers. A backup is saved first."
        else "Convert every amount at today's rate (1 $base = ${World.symbol(code)}${"%.4f".format(rate)}), or keep the numbers as they are if you entered them in $code already. A backup is saved first.", style = T.body, color = C.secondary) },
      confirmButton = {
        Column(horizontalAlignment = Alignment.End) {
          rate?.let { r -> TextButton({ change(ctx, code, r); pending = null }) { Text("Convert Everything", color = C.accent, style = T.headline) } }
          TextButton({ change(ctx, code, 1.0); pending = null }) { Text("Just Change the Symbol", color = C.accent) }
          TextButton({ pending = null }) { Text("Cancel", color = C.accent) }
        }
      })
  }
}

private fun change(ctx: android.content.Context, code: String, rate: Double) {
  runCatching { BackupOps.write(ctx) }
  Store.update { BaseCurrency.convert(it, rate, code) }
  Prefs.set("baseCurrency", code)
  com.paisapulse.app.work.Services.refreshWidget()
  Ui.show("Main currency is now $code")
}

/** Insights: how you paid. */
fun LazyListScope.paymentMethodSection(txns: List<Txn>) {
  val spent = txns.filter { it.type == "expense" }
  val groups = spent.groupBy { PaymentMethod.of(it.paymentMethod) }.map { (m, v) -> Triple(m, v.sumOf { it.effectiveAmount }, v.size) }.sortedByDescending { it.second }
  if (groups.none { it.first != null }) return
  val all = maxOf(1L, groups.sumOf { it.second })
  group("How you paid") {
    groups.forEachIndexed { i, (m, total, count) ->
      if (i > 0) Divider()
      Column(Modifier.padding(horizontal = 16.dp, vertical = 10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
          Icon(Sym.of(m?.icon ?: "questionmark.circle"), null, tint = C.accent, modifier = Modifier.size(18.dp))
          Spacer(Modifier.width(8.dp))
          Text(m?.label ?: "Not set", style = T.body, color = C.label, modifier = Modifier.weight(1f))
          Text(Money.format(total), style = T.amount(16), color = C.label)
        }
        Box(Modifier.padding(vertical = 6.dp).fillMaxWidth().height(6.dp).clip(CircleShape).background(C.fill)) {
          Box(Modifier.fillMaxWidth(total.toFloat() / all).fillMaxHeight().clip(CircleShape).background(if (m == null) C.secondary else C.accent))
        }
        Text("$count payments · ${Math.round(total * 100.0 / all)}%", style = T.caption, color = C.secondary)
      }
    }
  }
}

/** Insights: spending in other currencies, in both the foreign amount and the main currency. */
fun LazyListScope.spentAbroadSection(txns: List<Txn>) {
  val foreign = txns.filter { it.type == "expense" && it.currency != null && it.originalAmount != null }
  if (foreign.isEmpty()) return
  val groups = foreign.groupBy { it.currency!! }.map { (c, v) -> listOf(c, v.sumOf { it.originalAmount!! }, v.sumOf { it.effectiveAmount }, v.size) }
    .sortedByDescending { it[2] as Long }
  group("Spent abroad", footer = "In ${Money.base}, as charged (including card markup).") {
    groups.forEachIndexed { i, g ->
      val code = g[0] as String
      if (i > 0) Divider(68.dp)
      PRow(Money.format(g[1] as Long, code), subtitle = "${g[3]} spends · ${World.currencyName(code)}",
        leading = { Text(World.symbol(code), style = T.headline, color = C.accent, modifier = Modifier.width(40.dp)) }) {
        Text(Money.format(g[2] as Long), style = T.amount(16), color = C.expense)
      }
    }
  }
}

/** Accent colour: presets or any colour from the picker. */
@Composable fun AccentScreen() {
  var h by remember { mutableFloatStateOf(0f) }
  var s by remember { mutableFloatStateOf(0.6f) }
  var b by remember { mutableFloatStateOf(0.9f) }
  LaunchedEffect(Unit) {
    val hsv = FloatArray(3); android.graphics.Color.colorToHSV(hex(Prefs.customAccent).toArgb(), hsv); h = hsv[0]; s = hsv[1]; b = hsv[2]
  }
  fun applyCustom() {
    val c = Color(android.graphics.Color.HSVToColor(floatArrayOf(h, s, b)))
    Prefs.set("customAccent", "#%06X".format(c.toArgb() and 0xFFFFFF)); Prefs.set("accent", "custom")
  }
  PScreen("Accent Colour", back = true) {
    group("Accent colour") {
      val all = accents.map { Triple(it.first, it.second, hex(it.third.first)) } + Triple("custom", "Custom", hex(Prefs.customAccent))
      all.chunked(4).forEach { row ->
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp), horizontalArrangement = Arrangement.SpaceAround) {
          row.forEach { (key, name, color) ->
            val on = Prefs.accent == key
            Column(Modifier.width(64.dp).clickable { Prefs.set("accent", key) }, horizontalAlignment = Alignment.CenterHorizontally) {
              Box(Modifier.size(50.dp).border(if (on) 2.dp else 0.dp, if (on) color else Color.Transparent, CircleShape).padding(5.dp).clip(CircleShape).background(color))
              Text(name, style = T.caption2, color = C.secondary, maxLines = 1, modifier = Modifier.padding(top = 4.dp))
            }
          }
          repeat(4 - row.size) { Spacer(Modifier.width(64.dp)) }
        }
      }
    }
    group("Pick any colour", footer = "Buttons, links, the + button and highlights use this colour. Very light colours can be hard to read on white.") {
      Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        ColorWheel(h, s) { nh, ns -> h = nh; s = ns; applyCustom() }
        Text("Brightness", style = T.footnote, color = C.secondary)
        Slider(b, { b = it; applyCustom() }, valueRange = 0.25f..1f, colors = SliderDefaults.colors(thumbColor = C.accent, activeTrackColor = C.accent))
        Row(verticalAlignment = Alignment.CenterVertically) {
          Box(Modifier.size(44.dp).clip(CircleShape).background(C.accent), contentAlignment = Alignment.Center) { Icon(Sym.of("plus"), null, tint = Color.White) }
          Spacer(Modifier.width(12.dp))
          Text("Save", style = T.headline, color = Color.White, modifier = Modifier.clip(CircleShape).background(C.accent).padding(horizontal = 20.dp, vertical = 10.dp))
          Spacer(Modifier.width(12.dp))
          Text("Link", style = T.body, color = C.accent)
          Spacer(Modifier.weight(1f))
          Text(Prefs.customAccent, style = T.footnote, color = C.secondary)
        }
      }
    }
  }
}

/** Hue around the circle, saturation from the centre out. */
@Composable private fun ColorWheel(hue: Float, sat: Float, onChange: (Float, Float) -> Unit) {
  val hues = (0..360 step 30).map { Color(android.graphics.Color.HSVToColor(floatArrayOf(it.toFloat(), 1f, 1f))) }
  fun pick(o: Offset, size: Float) {
    val r = size / 2; val dx = o.x - r; val dy = o.y - r
    val d = kotlin.math.sqrt(dx * dx + dy * dy).coerceAtMost(r)
    val a = ((Math.toDegrees(kotlin.math.atan2(dy, dx).toDouble()) + 360) % 360).toFloat()
    onChange(a, d / r)
  }
  BoxWithConstraints(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
    val side = minOf(maxWidth, 260.dp)
    Canvas(Modifier.size(side)
      .pointerInput(Unit) { detectTapGestures { pick(it, size.width.toFloat()) } }
      .pointerInput(Unit) { detectDragGestures { change, _ -> pick(change.position, size.width.toFloat()) } }) {
      val r = size.minDimension / 2
      drawCircle(Brush.sweepGradient(hues, center), r)
      drawCircle(Brush.radialGradient(listOf(Color.White, Color.White.copy(alpha = 0f)), center, r), r)
      val rad = Math.toRadians(hue.toDouble())
      val p = Offset(center.x + (kotlin.math.cos(rad) * sat * r).toFloat(), center.y + (kotlin.math.sin(rad) * sat * r).toFloat())
      drawCircle(Color.White, 14.dp.toPx(), p)
      drawCircle(Color(android.graphics.Color.HSVToColor(floatArrayOf(hue, sat, 1f))), 11.dp.toPx(), p)
    }
  }
}

/** App icon picker with real previews of each icon. */
@Composable fun AppIconScreen() {
  val ctx = LocalContext.current
  var current by remember { mutableStateOf(AppIcons.current(ctx)) }
  PScreen("App Icon", back = true) {
    item {
      Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
        AppIcons.all.chunked(3).forEach { row ->
          Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceAround) {
            row.forEach { (key, name, _) ->
              val on = current == key
              Column(Modifier.width(96.dp).clickable { AppIcons.set(ctx, key); current = key }, horizontalAlignment = Alignment.CenterHorizontally) {
                Box(Modifier.size(86.dp).border(if (on) 3.dp else 0.dp, if (on) C.accent else Color.Transparent, RoundedCornerShape(24.dp)).padding(5.dp)) {
                  Image(painterResource(AppIcons.preview(key)), name, modifier = Modifier.fillMaxSize().shadow(6.dp, RoundedCornerShape(20.dp)).clip(RoundedCornerShape(20.dp)))
                }
                Text(name, style = T.subhead.copy(fontWeight = if (on) FontWeight.SemiBold else FontWeight.Normal), color = C.label, modifier = Modifier.padding(top = 8.dp))
              }
            }
            repeat(3 - row.size) { Spacer(Modifier.width(96.dp)) }
          }
        }
        Text("Home screen icons must be built into the app, so they come in these colours; the accent colour can be anything.",
          style = T.footnote, color = C.secondary, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
      }
    }
  }
}
