package com.paisapulse.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.paisapulse.app.data.*
import com.paisapulse.app.ui.*

data class ReorderItem(val id: String, val name: String, val icon: String, val color: String)
data class ReorderGroup(val title: String, val items: List<ReorderItem>)

/** Accounts (by type) or categories (by kind) in the order you drag them to. Mirrors iOS ReorderView. */
@Composable fun ReorderSheet(what: String) {
  val db = Store.value
  val groups = remember(what) {
    if (what == "accounts") {
      val live = db.accounts.filter { it.archivedAt == null }
      AccountType.entries.sortedBy { it.order }.mapNotNull { t ->
        live.filter { it.kind == t }.sortedBy { it.sortOrder }.map { ReorderItem(it.id, it.name, it.icon, it.color) }
          .takeIf { it.isNotEmpty() }?.let { ReorderGroup(t.plural, it) }
      }
    } else {
      val kind = what.removePrefix("categories:")
      val live = db.categories.filter { it.kind == kind && it.archivedAt == null }
      val parents = live.filter { it.parentId == null }.sortedBy { it.sortOrder }
      fun item(c: Category) = ReorderItem(c.id, c.name, c.icon, c.color)
      listOf(ReorderGroup("Categories", parents.map(::item))) + parents.mapNotNull { p ->
        live.filter { it.parentId == p.id }.sortedBy { it.sortOrder }.takeIf { it.size > 1 }?.let { ReorderGroup("In ${p.name}", it.map(::item)) }
      }
    }
  }
  val lists = remember(what) { groups.map { g -> mutableStateListOf(*g.items.toTypedArray()) } }
  val title = when (what) { "accounts" -> "Reorder Accounts"; "categories:income" -> "Income Categories"; else -> "Expense Categories" }
  PSheet({ Ui.sheet = null }) {
    SheetHeader(title, saveLabel = "Done", onCancel = { Ui.sheet = null }) {
      val order = lists.flatMap { l -> l.mapIndexed { i, it -> it.id to i } }.toMap()
      Store.update { d ->
        if (what == "accounts") d.copy(accounts = d.accounts.map { a -> order[a.id]?.let { a.copy(sortOrder = it, updatedAt = now()) } ?: a })
        else d.copy(categories = d.categories.map { c -> order[c.id]?.let { c.copy(sortOrder = it, updatedAt = now()) } ?: c })
      }
      Ui.sheet = null
    }
    Text("Hold and drag the handle to move.", style = T.footnote, color = C.secondary, modifier = Modifier.padding(horizontal = 20.dp))
    Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
      groups.forEachIndexed { g, group ->
        if (groups.size > 1) Text(group.title, style = T.footnote, color = C.secondary, modifier = Modifier.padding(start = 32.dp, top = 16.dp, bottom = 6.dp))
        ReorderColumn(lists[g])
      }
    }
  }
}

private val RowHeight = 56.dp

@Composable private fun ReorderColumn(items: androidx.compose.runtime.snapshots.SnapshotStateList<ReorderItem>) {
  val rowPx = with(LocalDensity.current) { RowHeight.toPx() }
  val haptic = LocalHapticFeedback.current
  var dragging by remember { mutableStateOf<String?>(null) }
  var offset by remember { mutableFloatStateOf(0f) }
  Column(Modifier.padding(horizontal = 16.dp).fillMaxWidth().clip(RoundedCornerShape(24.dp)).background(C.card)) {
    items.forEachIndexed { index, item ->
      key(item.id) {
        val isDragged = dragging == item.id
        fun move(to: Int) { if (to in items.indices && to != index) { items.add(to, items.removeAt(index)); haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove) } }
        Row(Modifier.fillMaxWidth().height(RowHeight)
          .graphicsLayer { translationY = if (isDragged) offset else 0f; scaleX = if (isDragged) 1.02f else 1f; scaleY = if (isDragged) 1.02f else 1f }
          .then(if (isDragged) Modifier.shadow(8.dp, RoundedCornerShape(12.dp)) else Modifier)
          .background(C.card)
          .semantics {
            customActions = listOf(
              CustomAccessibilityAction("Move up") { move(index - 1); true },
              CustomAccessibilityAction("Move down") { move(index + 1); true },
            )
          }
          .padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
          CategoryBadge(item.icon, item.color, 30.dp)
          Spacer(Modifier.width(12.dp))
          Text(item.name, style = T.body, color = C.label, modifier = Modifier.weight(1f))
          Icon(Sym.of("line.3.horizontal"), "Drag to reorder", tint = C.tertiary, modifier = Modifier.size(28.dp)
            .pointerInput(item.id) {
              detectDragGesturesAfterLongPress(
                onDragStart = { dragging = item.id; offset = 0f; haptic.performHapticFeedback(HapticFeedbackType.LongPress) },
                onDragEnd = { dragging = null; offset = 0f },
                onDragCancel = { dragging = null; offset = 0f },
              ) { change, drag ->
                change.consume()
                offset += drag.y
                val i = items.indexOfFirst { it.id == item.id }
                if (offset > rowPx / 2 && i < items.lastIndex) { items.add(i + 1, items.removeAt(i)); offset -= rowPx; haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove) }
                else if (offset < -rowPx / 2 && i > 0) { items.add(i - 1, items.removeAt(i)); offset += rowPx; haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove) }
              }
            })
        }
        if (index < items.lastIndex) Divider(58.dp)
      }
    }
  }
}
