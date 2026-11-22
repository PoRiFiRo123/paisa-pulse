package com.paisapulse.app.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.paisapulse.app.data.Prefs
import com.paisapulse.app.data.TxnType
import com.paisapulse.app.logic.Money
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.HazeStyle
import dev.chrisbanes.haze.HazeTint
import dev.chrisbanes.haze.hazeEffect

val LocalHaze = staticCompositionLocalOf { HazeState() }

/** Liquid Glass stand-in: a blurred, tinted surface over the content behind (Android 12+ blur; tint below). */
@Composable
fun Modifier.glass(shape: androidx.compose.ui.graphics.Shape = CircleShape): Modifier {
  val p = C
  return this.shadow(10.dp, shape, ambientColor = Color.Black.copy(alpha = 0.12f), spotColor = Color.Black.copy(alpha = 0.12f))
    .clip(shape)
    .hazeEffect(LocalHaze.current, HazeStyle(backgroundColor = p.background, tint = HazeTint(p.glass), blurRadius = 24.dp, noiseFactor = 0f))
    .border(0.5.dp, p.glassBorder, shape)
}

fun TxnType.color(p: Palette) = when (this) { TxnType.Expense -> p.expense; TxnType.Income -> p.income; TxnType.Transfer -> p.secondary }

@Composable fun CategoryBadge(icon: String?, color: String?, size: Dp = 36.dp) {
  val c = hex(color ?: "#8E8E93")
  Box(Modifier.size(size).clip(RoundedCornerShape(size * 0.28f))
    .background(Brush.verticalGradient(listOf(c.copy(alpha = 0.92f), c))), contentAlignment = Alignment.Center) {
    Icon(Sym.of(icon), null, tint = Color.White, modifier = Modifier.size(size * 0.54f))
  }
}

/** Amount without a minus sign: soft red expense, green income, grey transfer. */
@Composable fun AmountText(amount: Long, type: TxnType, style: androidx.compose.ui.text.TextStyle = T.amount(17)) {
  Text(Money.format(amount, Prefs.hideAmounts), style = style, color = type.color(C), maxLines = 1)
}

/** Screen with an iOS large title that collapses into the glass top bar on scroll. */
@Composable
fun PScreen(
  title: String,
  large: Boolean = true,
  back: Boolean = false,
  actions: @Composable RowScope.() -> Unit = {},
  leading: (@Composable () -> Unit)? = null,
  bottomInset: Dp = 110.dp,
  content: LazyListScope.() -> Unit,
) {
  val list = rememberLazyListState()
  val collapsed by remember { derivedStateOf { !large || list.firstVisibleItemIndex > 0 || list.firstVisibleItemScrollOffset > 60 } }
  Box(Modifier.fillMaxSize().background(C.background)) {
    LazyColumn(state = list, modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(top = 100.dp, bottom = bottomInset)) {
      if (large) item { Text(title, style = T.largeTitle, color = C.label, modifier = Modifier.padding(start = 20.dp, end = 20.dp, bottom = 8.dp)) }
      content()
    }
    Row(Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 16.dp, vertical = 6.dp).height(48.dp),
      verticalAlignment = Alignment.CenterVertically) {
      if (back) GlassIcon("chevron.left", "Back") { Ui.pop() } else leading?.invoke()
      Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
        androidx.compose.animation.AnimatedVisibility(collapsed, enter = fadeIn(), exit = fadeOut()) {
          Text(title, style = T.headline, color = C.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
      }
      Row(horizontalArrangement = Arrangement.spacedBy(8.dp), content = actions)
    }
  }
}

@Composable fun GlassIcon(sym: String, label: String, tint: Color = C.accent, onClick: () -> Unit) {
  Box(Modifier.size(44.dp).glass().clickable(onClickLabel = label, onClick = onClick), contentAlignment = Alignment.Center) {
    Icon(Sym.of(sym), label, tint = tint, modifier = Modifier.size(22.dp))
  }
}

/** iOS inset-grouped section. */
fun LazyListScope.group(header: String? = null, footer: String? = null, trailing: (@Composable () -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
  item {
    Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
      if (header != null || trailing != null) Row(Modifier.padding(start = 16.dp, end = 4.dp, bottom = 8.dp, top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(header ?: "", style = T.title3.copy(fontSize = androidx.compose.ui.unit.TextUnit(19f, androidx.compose.ui.unit.TextUnitType.Sp)), color = C.secondary, modifier = Modifier.weight(1f))
        trailing?.invoke()
      }
      Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(24.dp)).background(C.card), content = content)
      if (footer != null) Text(footer, style = T.footnote, color = C.secondary, modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 8.dp))
    }
  }
}

@Composable fun Divider(inset: Dp = 16.dp) { HorizontalDivider(Modifier.padding(start = inset), 0.5.dp, C.separator) }

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun PRow(
  title: String,
  modifier: Modifier = Modifier,
  subtitle: String? = null,
  value: String? = null,
  valueColor: Color? = null,
  leading: (@Composable () -> Unit)? = null,
  chevron: Boolean = false,
  titleColor: Color? = null,
  onLongClick: (() -> Unit)? = null,
  onClick: (() -> Unit)? = null,
  trailing: (@Composable () -> Unit)? = null,
) {
  val m = if (onClick != null || onLongClick != null) modifier.combinedClickable(onClick = { onClick?.invoke() }, onLongClick = onLongClick) else modifier
  Row(m.fillMaxWidth().heightIn(min = 52.dp).padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
    if (leading != null) { leading(); Spacer(Modifier.width(12.dp)) }
    Column(Modifier.weight(1f)) {
      Text(title, style = T.body, color = titleColor ?: C.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
      if (subtitle != null) Text(subtitle, style = T.footnote, color = C.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
    if (value != null) Text(value, style = T.body, color = valueColor ?: C.secondary, maxLines = 1, modifier = Modifier.padding(start = 8.dp))
    trailing?.invoke()
    if (chevron) Icon(Sym.of("chevron.right"), null, tint = C.tertiary, modifier = Modifier.padding(start = 8.dp).size(14.dp))
  }
}

/** iOS-style switch row. */
@Composable fun ToggleRow(title: String, checked: Boolean, leading: (@Composable () -> Unit)? = null, onChange: (Boolean) -> Unit) {
  PRow(title, leading = leading, onClick = { onChange(!checked) }) {
    Switch(checked, onChange, colors = SwitchDefaults.colors(checkedTrackColor = hex("#34C759"), checkedThumbColor = Color.White,
      uncheckedTrackColor = C.fill, uncheckedThumbColor = Color.White, uncheckedBorderColor = Color.Transparent, checkedBorderColor = Color.Transparent))
  }
}

/** iOS menu picker: shows the value with ⌃⌄; tap opens a menu. */
@Composable fun <V> PickerRow(title: String, options: List<Pair<V, String>>, selected: V, leading: (@Composable () -> Unit)? = null, onSelect: (V) -> Unit) {
  var open by remember { mutableStateOf(false) }
  Box {
    PRow(title, leading = leading, onClick = { open = true }) {
      Text(options.firstOrNull { it.first == selected }?.second ?: "", style = T.body, color = C.accent, maxLines = 1)
      Icon(Sym.of("chevron.up.chevron.down"), null, tint = C.accent, modifier = Modifier.padding(start = 2.dp).size(16.dp))
    }
    DropdownMenu(open, { open = false }, modifier = Modifier.background(C.card), offset = androidx.compose.ui.unit.DpOffset(200.dp, 0.dp)) {
      options.forEach { (v, label) ->
        DropdownMenuItem(text = { Text(label, style = T.body, color = C.label) }, onClick = { onSelect(v); open = false },
          trailingIcon = { if (v == selected) Icon(Sym.of("checkmark"), null, tint = C.accent) })
      }
    }
  }
}

/** iOS segmented control. */
@Composable fun Segmented(options: List<String>, selected: Int, modifier: Modifier = Modifier, onSelect: (Int) -> Unit) {
  val haptics = LocalHapticFeedback.current
  Row(modifier.fillMaxWidth().height(36.dp).clip(RoundedCornerShape(18.dp)).background(C.fill).padding(2.dp)) {
    options.forEachIndexed { i, label ->
      val bg by animateColorAsState(if (i == selected) (if (C.dark) hex("#636366") else Color.White) else Color.Transparent, label = "seg")
      Box(Modifier.weight(1f).fillMaxHeight().shadow(if (i == selected) 2.dp else 0.dp, RoundedCornerShape(16.dp)).clip(RoundedCornerShape(16.dp)).background(bg)
        .clickable { haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove); onSelect(i) }, contentAlignment = Alignment.Center) {
        Text(label, style = T.subhead.copy(fontWeight = if (i == selected) FontWeight.SemiBold else FontWeight.Medium), color = C.label)
      }
    }
  }
}

/** Floating Liquid Glass tab bar with a separate Search button (iOS 26 layout). */
@Composable fun TabBar() {
  val tabs = listOf(Tab.Home to ("house.fill" to "Home"), Tab.Activity to ("list.bullet.rectangle.fill" to "Activity"),
    Tab.Accounts to ("creditcard.fill" to "Accounts"), Tab.Settings to ("gearshape.fill" to "Settings"))
  Row(Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 20.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
    Row(Modifier.weight(1f).height(64.dp).glass(RoundedCornerShape(32.dp)).padding(4.dp)) {
      tabs.forEach { (t, v) ->
        val sel = Ui.tab == t
        val bg by animateColorAsState(if (sel) C.fill else Color.Transparent, label = "tab")
        Column(Modifier.weight(1f).fillMaxHeight().clip(RoundedCornerShape(28.dp)).background(bg)
          .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { Ui.select(t) },
          horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
          Icon(Sym.of(v.first), v.second, tint = if (sel) C.accent else C.label, modifier = Modifier.size(24.dp))
          Text(v.second, style = T.caption2.copy(fontWeight = FontWeight.Medium), color = if (sel) C.accent else C.label)
        }
      }
    }
    Spacer(Modifier.width(10.dp))
    Box(Modifier.size(64.dp).glass().clickable { Ui.select(Tab.Search) }, contentAlignment = Alignment.Center) {
      Icon(Sym.of("magnifyingglass"), "Search", tint = if (Ui.tab == Tab.Search) C.accent else C.label, modifier = Modifier.size(26.dp))
    }
  }
}

@Composable fun ToastHost(modifier: Modifier = Modifier) {
  val t = Ui.toast
  AnimatedVisibility(t != null, modifier, enter = slideInVertically { it } + fadeIn(), exit = slideOutVertically { it } + fadeOut()) {
    val toast = t ?: return@AnimatedVisibility
    Row(Modifier.padding(bottom = 96.dp).glass(RoundedCornerShape(26.dp)).padding(horizontal = 18.dp, vertical = 12.dp),
      verticalAlignment = Alignment.CenterVertically) {
      Text(toast.text, style = T.subhead.copy(fontWeight = FontWeight.Medium), color = C.label)
      if (toast.undo != null) {
        Spacer(Modifier.width(14.dp))
        Text("Undo", style = T.subhead.copy(fontWeight = FontWeight.SemiBold), color = C.accent,
          modifier = Modifier.clickable { toast.undo.invoke(); Ui.toast = null })
      }
    }
  }
}

/** iOS sheet: rounded, draggable, with Cancel / title / Save in a header. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable fun PSheet(onDismiss: () -> Unit, skipPartial: Boolean = true, content: @Composable ColumnScope.() -> Unit) {
  ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = skipPartial),
    containerColor = C.background, shape = RoundedCornerShape(topStart = 32.dp, topEnd = 32.dp),
    dragHandle = { Box(Modifier.padding(top = 8.dp).size(36.dp, 5.dp).clip(CircleShape).background(C.tertiary)) }, content = content)
}

@Composable fun SheetHeader(title: String, canSave: Boolean = true, saveLabel: String = "Save", onCancel: () -> Unit, onSave: (() -> Unit)?) {
  Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
    GlassIcon("xmark", "Cancel", tint = C.label, onClick = onCancel)
    Text(title, style = T.headline, color = C.label, modifier = Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
    if (onSave != null) {
      Box(Modifier.size(44.dp).clip(CircleShape).background(if (canSave) C.accent else C.fill).clickable(enabled = canSave, onClick = onSave),
        contentAlignment = Alignment.Center) { Icon(Sym.of("checkmark"), saveLabel, tint = if (canSave) Color.White else C.secondary) }
    } else Spacer(Modifier.size(44.dp))
  }
}

/** Text field styled like an iOS form row. */
@Composable fun FieldRow(value: String, onChange: (String) -> Unit, placeholder: String, number: Boolean = false, modifier: Modifier = Modifier) {
  androidx.compose.foundation.text.BasicTextField(value, onChange, singleLine = true,
    textStyle = T.body.copy(color = C.label), cursorBrush = androidx.compose.ui.graphics.SolidColor(C.accent),
    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = if (number) androidx.compose.ui.text.input.KeyboardType.Decimal else androidx.compose.ui.text.input.KeyboardType.Text,
      capitalization = androidx.compose.ui.text.input.KeyboardCapitalization.Words),
    modifier = modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 15.dp),
    decorationBox = { inner -> Box { if (value.isEmpty()) Text(placeholder, style = T.body, color = C.tertiary); inner() } })
}

@Composable fun EmptyHint(title: String, sym: String, message: String) {
  Column(Modifier.fillMaxWidth().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally) {
    Icon(Sym.of(sym), null, tint = C.secondary, modifier = Modifier.size(44.dp))
    Spacer(Modifier.height(10.dp))
    Text(title, style = T.title3, color = C.label)
    Text(message, style = T.subhead, color = C.secondary, textAlign = androidx.compose.ui.text.style.TextAlign.Center, modifier = Modifier.padding(top = 4.dp))
  }
}

@Composable fun ColorRow(selected: String, onSelect: (String) -> Unit) {
  Row(Modifier.fillMaxWidth().horizontalScroll(androidx.compose.foundation.rememberScrollState()).padding(12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
    swatches.forEach { h ->
      Box(Modifier.size(30.dp).clip(CircleShape).background(hex(h)).clickable { onSelect(h) }, contentAlignment = Alignment.Center) {
        if (h == selected) Icon(Sym.of("checkmark"), null, tint = Color.White, modifier = Modifier.size(16.dp))
      }
    }
  }
}

@Composable fun ProgressBar(ratio: Double, color: Color, modifier: Modifier = Modifier) {
  val w by animateDpAsState(0.dp, label = "p")
  Box(modifier.fillMaxWidth().height(6.dp).clip(CircleShape).background(C.fill)) {
    Box(Modifier.fillMaxWidth(ratio.coerceIn(0.0, 1.0).toFloat()).fillMaxHeight().clip(CircleShape).background(color).padding(start = w))
  }
}
