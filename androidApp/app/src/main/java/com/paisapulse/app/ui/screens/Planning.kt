package com.paisapulse.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.paisapulse.app.data.*
import com.paisapulse.app.logic.*
import com.paisapulse.app.ui.*
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

// Planning: trips and any planned event. Same screens on iPhone (apple/App/More/PlanningViews.swift).

private val dayMonth = DateTimeFormatter.ofPattern("d MMM", Locale.ENGLISH)
private val dayMonthYear = DateTimeFormatter.ofPattern("d MMM yyyy", Locale.ENGLISH)
private fun Long.localDate(): LocalDate = Instant.ofEpochMilli(this).atZone(ZoneId.systemDefault()).toLocalDate()

fun tripDates(t: Trip): String? {
  val s = t.startAt?.localDate() ?: return null
  val e = (t.endAt ?: t.startAt).localDate()
  return if (s == e) dayMonthYear.format(s) else "${dayMonth.format(s)} – ${dayMonthYear.format(e)}"
}

fun tripStatusText(s: TripMath.Summary): String = when (s.status) {
  TripMath.Status.Upcoming -> s.daysToGo?.let { if (it == 0) "Starts today" else if (it == 1) "Tomorrow" else "In $it days" } ?: "Upcoming"
  TripMath.Status.Ongoing -> s.day?.let { d -> s.days?.let { "Day $d of $it" } ?: "Day $d" } ?: "Happening now"
  TripMath.Status.Completed -> if (s.trip.startAt == null) "Logged" else "Done"
}

private fun summaries(db: Db, trips: List<Trip>) = trips.map { t ->
  TripMath.summary(t, db.tripItems, db.tripWallets, db.liveTxns, db.txnSplitShares.associate { it.id to it.share })
}

/** Green under 80%, amber to 100%, red over. */
@Composable fun BudgetBar(progress: Double, height: androidx.compose.ui.unit.Dp = 8.dp) {
  val color = if (progress > 1) C.expense else if (progress >= 0.8) hex("#FF9500") else C.income
  Box(Modifier.fillMaxWidth().height(height).clip(CircleShape).background(C.fill)) {
    Box(Modifier.fillMaxWidth(progress.coerceIn(0.0, 1.0).toFloat().coerceAtLeast(0.02f)).fillMaxHeight().clip(CircleShape).background(color))
  }
}

@Composable fun TripCard(s: TripMath.Summary, onClick: () -> Unit) {
  val t = s.trip
  val k = TripKinds.of(t.kind)
  val hidden = Prefs.hideAmounts
  val statusColor = when (s.status) { TripMath.Status.Ongoing -> C.income; TripMath.Status.Upcoming -> C.accent; else -> C.secondary }
  Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).background(C.card).clickable(onClick = onClick).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
    Row(verticalAlignment = Alignment.Top) {
      Box(Modifier.size(40.dp).clip(RoundedCornerShape(12.dp)).background(hex(k.color)), contentAlignment = Alignment.Center) {
        Icon(Sym.of(k.icon), null, tint = Color.White, modifier = Modifier.size(20.dp))
      }
      Spacer(Modifier.width(12.dp))
      Column(Modifier.weight(1f)) {
        Text(t.name, style = T.headline, color = C.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(listOfNotNull(tripDates(t), t.places.takeIf { it.isNotEmpty() }?.joinToString(", ") { it.name }).joinToString(" · "),
          style = T.caption, color = C.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
      }
      Text(tripStatusText(s), style = T.caption.copy(fontWeight = FontWeight.SemiBold), color = statusColor,
        modifier = Modifier.clip(CircleShape).background(statusColor.copy(alpha = 0.12f)).padding(horizontal = 8.dp, vertical = 4.dp))
    }
    Row(verticalAlignment = Alignment.Bottom) {
      Text(Money.format(s.spent, hidden), style = T.amount(20, FontWeight.Bold), color = C.label)
      if (s.budget > 0) Text("  of ${Money.format(s.budget, hidden)}", style = T.subhead, color = C.secondary)
      Spacer(Modifier.weight(1f))
      if (t.international) Icon(Sym.of("globe"), null, tint = C.secondary, modifier = Modifier.size(18.dp))
    }
    if (s.budget > 0) BudgetBar(s.progress)
  }
}

@Composable fun PlanningScreen() {
  val db by Store.db.collectAsState()
  var filter by remember { mutableStateOf("all") }
  var region by remember { mutableStateOf("any") }
  val live = db.trips.filter { it.archivedAt == null }
  val all = summaries(db, live)
  val o = TripMath.overview(all)
  val rank = { s: TripMath.Status -> when (s) { TripMath.Status.Ongoing -> 0; TripMath.Status.Upcoming -> 1; else -> 2 } }
  val shown = all.filter { s ->
    (filter == "all" || (if (filter == "over") s.overBudget else s.status.name.lowercase() == filter)) &&
      (region == "any" || (region == "international") == s.trip.international)
  }.sortedWith(compareBy<TripMath.Summary> { rank(it.status) }.thenByDescending { it.trip.startAt ?: it.trip.createdAt })
  val hidden = Prefs.hideAmounts
  PScreen("Planning", back = true) {
    item {
      Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
          Kpi("Upcoming", "${o.upcoming}", "calendar.badge.clock", "#2563EB", Modifier.weight(1f))
          Kpi("Happening now", "${o.ongoing}", "location.fill", "#16A34A", Modifier.weight(1f))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
          Kpi("Planned budget", Money.compact(o.planned, hidden), "target", "#0891B2", Modifier.weight(1f))
          Kpi("Over budget", "${o.overBudget}", "exclamationmark.triangle.fill", if (o.overBudget > 0) "#E5484D" else "#8E8E93", Modifier.weight(1f))
        }
      }
    }
    item {
      Text("Plan something new", style = T.title3, color = C.label, modifier = Modifier.padding(start = 20.dp, top = 12.dp, bottom = 8.dp))
      Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        TripKinds.all.forEach { k ->
          Column(Modifier.size(width = 140.dp, height = 124.dp).clip(RoundedCornerShape(20.dp))
            .background(Brush.linearGradient(listOf(hex(k.color), hex(k.color).copy(alpha = 0.75f))))
            .clickable { Ui.sheet = Sheet.TripForm(k.id) }.padding(14.dp), verticalArrangement = Arrangement.SpaceBetween) {
            Icon(Sym.of(k.icon), null, tint = Color.White, modifier = Modifier.size(26.dp))
            Text(k.label, style = T.subhead.copy(fontWeight = FontWeight.SemiBold), color = Color.White, maxLines = 1)
          }
        }
      }
    }
    if (live.isEmpty()) item {
      Box(Modifier.padding(top = 24.dp)) { EmptyHint("Plan your first trip", "airplane", "Pick a type above. Set a budget for each part, track cash or forex you carry, and split with friends.") }
    } else {
      item {
        Row(Modifier.padding(start = 20.dp, end = 16.dp, top = 20.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
          Text("Your plans", style = T.title3, color = C.label, modifier = Modifier.weight(1f))
          var open by remember { mutableStateOf(false) }
          Box {
            Text(if (region == "any") "Anywhere" else region.replaceFirstChar { it.uppercase() }, style = T.subhead, color = C.accent, modifier = Modifier.clickable { open = true })
            DropdownMenu(open, { open = false }, modifier = Modifier.background(C.card)) {
              listOf("any" to "Anywhere", "domestic" to "Domestic", "international" to "International").forEach { (k, v) ->
                DropdownMenuItem({ Text(v) }, { region = k; open = false }, trailingIcon = { if (region == k) Icon(Sym.of("checkmark"), null, tint = C.accent) })
              }
            }
          }
        }
        Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
          listOf("all" to "All", "ongoing" to "Now", "upcoming" to "Upcoming", "completed" to "Done", "over" to "Over budget").forEach { (k, v) ->
            Text(v, style = T.subhead.copy(fontWeight = FontWeight.Medium), color = if (filter == k) Color.White else C.label,
              modifier = Modifier.clip(CircleShape).background(if (filter == k) C.accent else C.fill).clickable { filter = k }.padding(horizontal = 14.dp, vertical = 7.dp))
          }
        }
      }
      if (shown.isEmpty()) item { Text("Nothing here with these filters.", style = T.subhead, color = C.secondary, modifier = Modifier.fillMaxWidth().padding(24.dp)) }
      items(shown, key = { it.trip.id }) { s -> Box(Modifier.padding(horizontal = 16.dp, vertical = 6.dp)) { TripCard(s) { Ui.push(Route.TripDetail(s.trip.id)) } } }
    }
    val archived = db.trips.count { it.archivedAt != null }
    if (archived > 0) item {
      Text("Archived ($archived)", style = T.subhead, color = C.accent, modifier = Modifier.fillMaxWidth().clickable { Ui.push(Route.ArchivedTrips) }.padding(20.dp))
    }
  }
}

@Composable private fun Kpi(label: String, value: String, icon: String, color: String, modifier: Modifier) {
  Column(modifier.clip(RoundedCornerShape(18.dp)).background(C.card).padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
    Icon(Sym.of(icon), null, tint = hex(color), modifier = Modifier.size(20.dp))
    Text(value, style = T.amount(24, FontWeight.Bold), color = C.label, maxLines = 1)
    Text(label, style = T.caption, color = C.secondary)
  }
}

@Composable fun ArchivedTripsScreen() {
  val db by Store.db.collectAsState()
  PScreen("Archived", back = true) {
    group { db.trips.filter { it.archivedAt != null }.forEachIndexed { i, t -> if (i > 0) Divider(); PRow(t.name, chevron = true, onClick = { Ui.push(Route.TripDetail(t.id)) }) } }
  }
}

/** Home: the trip that's on now, or the next one coming up. */
fun LazyListScope.homeTripsSection(db: Db) {
  val live = summaries(db, db.trips.filter { it.archivedAt == null })
  val shown = (live.filter { it.status == TripMath.Status.Ongoing } + live.filter { it.status == TripMath.Status.Upcoming }.sortedBy { it.trip.startAt ?: Long.MAX_VALUE }).take(2)
  if (shown.isEmpty()) group("Planning") {
    PRow("Plan a trip or event", subtitle = "Budgets, forex and splits in one place", leading = { CategoryBadge("airplane", "#2563EB", 32.dp) }, chevron = true, onClick = { Ui.push(Route.Planning) })
  } else {
    item {
      Row(Modifier.padding(start = 32.dp, end = 20.dp, top = 16.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Text("Planning", style = T.title3, color = C.secondary, modifier = Modifier.weight(1f))
        Text("All", style = T.subhead, color = C.accent, modifier = Modifier.clickable { Ui.push(Route.Planning) })
      }
    }
    items(shown, key = { "home-trip-" + it.trip.id }) { s -> Box(Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) { TripCard(s) { Ui.push(Route.TripDetail(s.trip.id)) } } }
  }
}

// ---------------------------------------------------------------- Create / edit

private data class ItemRow(val id: String, val label: String, val budget: String)

@Composable fun TripFormSheet(kind: String, editId: String?) {
  val db = Store.value
  val trip = editId?.let { id -> db.trips.firstOrNull { it.id == id } }
  var kindId by remember { mutableStateOf(trip?.kind ?: kind) }
  var name by remember { mutableStateOf(trip?.name ?: "") }
  var international by remember { mutableStateOf(trip?.international ?: false) }
  var places by remember { mutableStateOf(trip?.places ?: emptyList()) }
  var newPlace by remember { mutableStateOf("") }
  var hasDates by remember { mutableStateOf(trip?.startAt != null || TripKinds.of(kindId).dated) }
  val today = LocalDate.now()
  var start by remember { mutableStateOf(trip?.startAt?.localDate() ?: today) }
  var end by remember { mutableStateOf((trip?.endAt ?: trip?.startAt)?.localDate() ?: today.plusDays(3)) }
  var travellers by remember { mutableIntStateOf(trip?.travellers ?: 1) }
  var people by remember { mutableStateOf(trip?.groupId?.let { g -> db.splitGroups.firstOrNull { it.id == g } }?.memberIds ?: emptyList()) }
  var newFriends by remember { mutableStateOf(listOf<Friend>()) }
  var newPerson by remember { mutableStateOf("") }
  var budgetOn by remember { mutableStateOf(trip?.budgetEnabled != false) }
  var countIn by remember { mutableStateOf(trip?.countInBudgets != false) }
  var items by remember {
    mutableStateOf(trip?.let { t -> db.tripItems.filter { it.tripId == t.id }.sortedBy { it.sortOrder }.map { ItemRow(it.id, it.label, it.budget?.let { b -> (b / 100).toString() } ?: "") } }
      ?: TripKinds.items(kind, false).map { ItemRow(newId(), it, "") })
  }
  var newItem by remember { mutableStateOf("") }
  var notes by remember { mutableStateOf(trip?.notes ?: "") }
  var pickCountry by remember { mutableStateOf(false) }
  var pickStart by remember { mutableStateOf(false) }
  var pickEnd by remember { mutableStateOf(false) }
  val k = TripKinds.of(kindId)
  fun resetItems(kid: String, intl: Boolean) { if (trip == null) items = TripKinds.items(kid, intl).map { ItemRow(newId(), it, "") } }
  val friends = db.friends.sortedBy { it.name } + newFriends

  fun save() {
    val dated = k.dated || hasDates
    val zone = ZoneId.systemDefault()
    val id = trip?.id ?: newId()
    var groupId = trip?.groupId
    Store.update { d ->
      var groups = d.splitGroups
      if (people.isNotEmpty()) {
        val g = groupId?.let { gid -> groups.firstOrNull { it.id == gid } }
        if (g != null) groups = groups.map { if (it.id == g.id) it.copy(name = name.trim(), memberIds = people) else it }
        else { val ng = SplitGroup(name = name.trim(), memberIds = people); groups = groups + ng; groupId = ng.id }
      } else groupId?.let { gid -> groups = groups.map { if (it.id == gid) it.copy(memberIds = emptyList()) else it } }
      val t = Trip(id = id, name = name.trim(), kind = kindId, international = k.places && international, places = if (k.places) places else emptyList(),
        startAt = if (dated) start.atStartOfDay(zone).toInstant().toEpochMilli() else null,
        endAt = if (dated) maxOf(start, end).atStartOfDay(zone).toInstant().toEpochMilli() else null,
        travellers = maxOf(travellers, people.size + 1), groupId = groupId, budgetEnabled = budgetOn, countInBudgets = countIn,
        notes = notes.trim().ifEmpty { null }, archivedAt = trip?.archivedAt, createdAt = trip?.createdAt ?: now(), updatedAt = now())
      val newItems = items.filter { it.label.isNotBlank() }.mapIndexed { i, r -> TripItem(id = r.id, tripId = id, label = r.label.trim(), budget = Money.parse(r.budget), sortOrder = i) }
      d.copy(trips = d.trips.filterNot { it.id == id } + t, tripItems = d.tripItems.filterNot { it.tripId == id } + newItems,
        friends = d.friends + newFriends.filter { f -> f.id in people && d.friends.none { it.id == f.id } }, splitGroups = groups)
    }
    Ui.sheet = null
    if (trip == null) Ui.push(Route.TripDetail(id))
  }

  PSheet({ Ui.sheet = null }) {
    SheetHeader(if (trip == null) "New ${k.label}" else "Edit", canSave = name.isNotBlank(), onCancel = { Ui.sheet = null }, onSave = ::save)
    LazyColumn(Modifier.fillMaxHeight(0.92f)) {
      group {
        Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
          Box(Modifier.size(44.dp).clip(RoundedCornerShape(12.dp)).background(hex(k.color)), contentAlignment = Alignment.Center) { Icon(Sym.of(k.icon), null, tint = Color.White) }
          FieldRow(name, { name = it }, if (k.places) "Name, e.g. Goa with college gang" else "Name, e.g. Ananya's wedding", modifier = Modifier.weight(1f))
        }
        Divider()
        PickerRow("Type", TripKinds.all.map { it.id to it.label }, kindId) { kindId = it; resetItems(it, international); if (!TripKinds.of(it).dated) hasDates = trip?.startAt != null }
      }
      if (k.places) group("Destinations", footer = if (international) "Each country sets its currency, so spends there can be entered in it." else null) {
        Segmented(listOf("In India", "Abroad"), if (international) 1 else 0, Modifier.padding(12.dp)) { international = it == 1; places = emptyList(); resetItems(kindId, international) }
        places.forEachIndexed { i, p ->
          Divider()
          PRow(p.name, leading = { Icon(Sym.of(if (international) "globe" else "mappin.and.ellipse"), null, tint = C.secondary) },
            value = p.currency?.let { "${World.symbol(it)} $it" }, onLongClick = { places = places.filterIndexed { j, _ -> j != i } })
        }
        Divider()
        if (international) PRow("Add a Country", titleColor = C.accent, leading = { Icon(Sym.of("plus.circle.fill"), null, tint = C.accent) }, onClick = { pickCountry = true })
        else Row(verticalAlignment = Alignment.CenterVertically) {
          FieldRow(newPlace, { newPlace = it }, "Add a place (Goa, Coorg…)", modifier = Modifier.weight(1f))
          Text("Add", style = T.body, color = C.accent, modifier = Modifier.clickable { if (newPlace.isNotBlank()) { places = places + TripPlace(newPlace.trim()); newPlace = "" } }.padding(16.dp))
        }
      }
      group("When") {
        if (!k.dated) { ToggleRow("Has dates", hasDates) { hasDates = it }; Divider() }
        if (k.dated || hasDates) {
          PRow("From", value = dayMonthYear.format(start), valueColor = C.label, onClick = { pickStart = true }); Divider()
          PRow("To", value = dayMonthYear.format(end), valueColor = C.label, onClick = { pickEnd = true }); Divider()
        }
        PRow("People", trailing = {
          Row(verticalAlignment = Alignment.CenterVertically) {
            Text("−", style = T.title3, color = C.accent, modifier = Modifier.clickable { travellers = maxOf(1, travellers - 1) }.padding(horizontal = 12.dp))
            Text("$travellers", style = T.headline, color = C.label)
            Text("+", style = T.title3, color = C.accent, modifier = Modifier.clickable { travellers = minOf(50, travellers + 1) }.padding(horizontal = 12.dp))
          }
        })
      }
      group("Who's going", footer = "They become a split group, so you can split expenses and settle up at the end.") {
        friends.forEachIndexed { i, f ->
          if (i > 0) Divider(56.dp)
          val on = f.id in people
          PRow(f.name, leading = { Avatar(f.name, 28.dp) }, onClick = {
            people = if (on) people - f.id else people + f.id; travellers = maxOf(travellers, people.size + 1)
          }) { Icon(Sym.of(if (on) "checkmark.circle.fill" else "circle"), null, tint = if (on) C.accent else C.tertiary) }
        }
        if (friends.isNotEmpty()) Divider()
        Row(verticalAlignment = Alignment.CenterVertically) {
          FieldRow(newPerson, { newPerson = it }, "Add someone by name", modifier = Modifier.weight(1f))
          Text("Add", style = T.body, color = C.accent, modifier = Modifier.clickable {
            if (newPerson.isNotBlank()) { val f = Friend(name = newPerson.trim()); newFriends = newFriends + f; people = people + f.id; newPerson = ""; travellers = maxOf(travellers, people.size + 1) }
          }.padding(16.dp))
        }
      }
      group("Budget", footer = "Switch off \"Count in monthly budgets\" to keep this trip's spending out of your monthly budgets (it still counts in totals and Insights). Hold an item to remove it.") {
        ToggleRow("Plan a budget", budgetOn) { budgetOn = it }
        if (budgetOn) {
          items.forEachIndexed { i, r ->
            Divider()
            Row(verticalAlignment = Alignment.CenterVertically) {
              FieldRow(r.label, { v -> items = items.mapIndexed { j, x -> if (j == i) x.copy(label = v) else x } }, "Item", modifier = Modifier.weight(1f))
              FieldRow(r.budget, { v -> items = items.mapIndexed { j, x -> if (j == i) x.copy(budget = v) else x } }, "${Money.symbol}0", number = true, modifier = Modifier.width(120.dp))
              Icon(Sym.of("minus.circle.fill"), "Remove", tint = C.expense, modifier = Modifier.padding(end = 12.dp).size(20.dp).clickable { items = items.filterIndexed { j, _ -> j != i } })
            }
          }
          Divider()
          Row(verticalAlignment = Alignment.CenterVertically) {
            FieldRow(newItem, { newItem = it }, "Add an item", modifier = Modifier.weight(1f))
            Text("Add", style = T.body, color = C.accent, modifier = Modifier.clickable { if (newItem.isNotBlank()) { items = items + ItemRow(newId(), newItem.trim(), ""); newItem = "" } }.padding(16.dp))
          }
          Divider()
          PRow("Total budget", value = Money.format(items.sumOf { Money.parse(it.budget) ?: 0 }), valueColor = C.label)
        }
        Divider()
        ToggleRow("Count in monthly budgets", countIn) { countIn = it }
      }
      group("Notes") { FieldRow(notes, { notes = it }, "Bookings, ideas…") }
      item { Spacer(Modifier.height(40.dp)) }
    }
  }
  if (pickCountry) CountryPickerDialog({ pickCountry = false }) { c -> places = places + TripPlace(c.name, c.name, c.currency); pickCountry = false }
  if (pickStart) DateDialog(start, { pickStart = false }) { start = it; if (end < it) end = it }
  if (pickEnd) DateDialog(end, { pickEnd = false }) { end = maxOf(it, start) }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun DateDialog(date: LocalDate, onDismiss: () -> Unit, onPick: (LocalDate) -> Unit) {
  val st = rememberDatePickerState(initialSelectedDateMillis = date.atStartOfDay(java.time.ZoneOffset.UTC).toInstant().toEpochMilli())
  DatePickerDialog(onDismiss, confirmButton = { TextButton({
    st.selectedDateMillis?.let { onPick(Instant.ofEpochMilli(it).atZone(java.time.ZoneOffset.UTC).toLocalDate()) }; onDismiss()
  }) { Text("OK") } }) { DatePicker(st) }
}

@Composable fun CountryPickerDialog(onDismiss: () -> Unit, onPick: (World.Country) -> Unit) {
  var q by remember { mutableStateOf("") }
  val list = World.countries.filter { it.name != "India" && (q.isBlank() || it.name.contains(q.trim(), true) || it.currency.contains(q.trim(), true)) }
  AlertDialog(onDismiss, containerColor = C.card, confirmButton = { TextButton(onDismiss) { Text("Cancel", color = C.accent) } },
    title = { Text("Add a Country", style = T.headline, color = C.label) },
    text = {
      Column {
        OutlinedTextField(q, { q = it }, singleLine = true, placeholder = { Text("Country") }, modifier = Modifier.fillMaxWidth())
        LazyColumn(Modifier.heightIn(max = 420.dp).padding(top = 8.dp)) {
          items(list) { c ->
            Row(Modifier.fillMaxWidth().clickable { onPick(c) }.padding(vertical = 12.dp)) {
              Text(c.name, style = T.body, color = C.label, modifier = Modifier.weight(1f))
              Text("${c.symbol} ${c.currency}", style = T.body, color = C.secondary)
            }
          }
        }
      }
    })
}

// ---------------------------------------------------------------- Trip page

@Composable fun TripDetailScreen(id: String) {
  val db by Store.db.collectAsState()
  val trip = db.trips.firstOrNull { it.id == id } ?: run { LaunchedEffect(Unit) { Ui.pop() }; return }
  val ctx = LocalContext.current
  val scope = rememberCoroutineScope()
  val layer = rememberGraphicsLayer()
  val l = remember(db) { Lookups(db) }
  val s = TripMath.summary(trip, db.tripItems, db.tripWallets, db.liveTxns, db.txnSplitShares.associate { it.id to it.share })
  val k = TripKinds.of(trip.kind)
  val mine = db.liveTxns.filter { it.tripId == id }.sortedByDescending { it.occurredAt }
  val group = trip.groupId?.let { g -> db.splitGroups.firstOrNull { it.id == g } }
  val hidden = Prefs.hideAmounts
  var menu by remember { mutableStateOf(false) }
  var confirmDelete by remember { mutableStateOf(false) }
  val bg = C.background
  PScreen(trip.name, large = false, back = true, actions = {
    Box {
      GlassIcon("ellipsis", "More") { menu = true }
      DropdownMenu(menu, { menu = false }, modifier = Modifier.background(C.card)) {
        DropdownMenuItem({ Text("Edit") }, { menu = false; Ui.sheet = Sheet.TripForm(trip.kind, trip.id) }, leadingIcon = { Icon(Sym.of("pencil"), null) })
        DropdownMenuItem({ Text("Share Summary") }, { menu = false; scope.launch { shareBitmap(ctx, layer.toImageBitmap().asAndroidBitmap(), "Share trip", "trip.png") } },
          leadingIcon = { Icon(Sym.of("square.and.arrow.up"), null) })
        DropdownMenuItem({ Text(if (trip.countInBudgets != false) "Leave Out of Monthly Budgets" else "Count in Monthly Budgets") }, {
          menu = false; Store.update { d -> d.copy(trips = d.trips.map { if (it.id == id) it.copy(countInBudgets = it.countInBudgets == false) else it }) }
        }, leadingIcon = { Icon(Sym.of("chart.pie.fill"), null) })
        DropdownMenuItem({ Text(if (trip.archivedAt == null) "Archive" else "Unarchive") }, {
          menu = false; Store.update { d -> d.copy(trips = d.trips.map { if (it.id == id) it.copy(archivedAt = if (it.archivedAt == null) now() else null) else it }) }
        }, leadingIcon = { Icon(Sym.of("archivebox"), null) })
        DropdownMenuItem({ Text("Delete", color = C.expense) }, { menu = false; confirmDelete = true }, leadingIcon = { Icon(Sym.of("trash"), null, tint = C.expense) })
      }
    }
  }) {
    item {
      Box(Modifier.padding(16.dp).drawWithContent { layer.record { this@drawWithContent.drawContent() }; drawLayer(layer) }.background(bg)) {
        TripHero(trip, s, k, hidden)
      }
    }
    item {
      Text("Add an Expense", style = T.headline, color = Color.White, textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        modifier = Modifier.padding(horizontal = 16.dp).fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(C.accent)
          .clickable { Ui.sheet = Sheet.Add(TxnType.Expense, tripId = id) }.padding(14.dp))
    }
    if (s.items.isNotEmpty()) group(if (trip.budgetEnabled != false) "Budget" else "Spending") {
      s.items.forEachIndexed { i, it2 ->
        if (i > 0) Divider()
        Column(Modifier.padding(horizontal = 16.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
          Row(verticalAlignment = Alignment.CenterVertically) {
            Text(it2.item.label, style = T.body, color = C.label, modifier = Modifier.weight(1f))
            Text(Money.format(it2.spent, hidden), style = T.amount(16, FontWeight.SemiBold), color = C.label)
            it2.item.budget?.takeIf { b -> b > 0 }?.let { b -> Text(" / ${Money.compact(b, hidden)}", style = T.subhead, color = C.secondary) }
          }
          it2.item.budget?.takeIf { b -> b > 0 }?.let { b ->
            BudgetBar(it2.spent.toDouble() / b, 6.dp)
            Text(if (it2.remaining >= 0) "${Money.format(it2.remaining, hidden)} left" else "${Money.format(-it2.remaining, hidden)} over", style = T.caption,
              color = if (it2.remaining >= 0) C.secondary else C.expense)
          }
        }
      }
      if (s.unassigned > 0) { Divider(); PRow("Not assigned", value = Money.format(s.unassigned, hidden)) }
    }
    group("Money you carry", footer = "Pick it under \"Paid from\" when you add an expense to see what's left. Hold to remove.") {
      s.wallets.forEachIndexed { i, w ->
        if (i > 0) Divider()
        val code = w.wallet.currency ?: Money.base
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
          Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Sym.of(if (w.wallet.currency == null) "banknote.fill" else "creditcard.and.123"), null, tint = C.accent, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text(w.wallet.label, style = T.body, color = C.label, modifier = Modifier.weight(1f))
            Text("${Money.format(maxOf(0, w.left), code, hidden)} left", style = T.amount(16, FontWeight.SemiBold), color = if (w.left < 0) C.expense else C.label)
            Icon(Sym.of("xmark"), "Remove", tint = C.tertiary, modifier = Modifier.padding(start = 8.dp).size(16.dp).clickable {
              Store.update { d -> d.copy(tripWallets = d.tripWallets.filterNot { it.id == w.wallet.id }) }
            })
          }
          BudgetBar(if (w.wallet.amount > 0) w.spent.toDouble() / w.wallet.amount else 0.0, 6.dp)
          Text("Carried ${Money.format(w.wallet.amount, code, hidden)}" + if (w.wallet.currency == null) "" else " at ${Money.symbol}${"%.2f".format(w.wallet.rate)}",
            style = T.caption, color = C.secondary)
        }
      }
      if (s.wallets.isNotEmpty()) Divider()
      PRow(if (trip.international) "Add Cash or Forex Card" else "Add Cash You're Carrying", titleColor = C.accent,
        leading = { Icon(Sym.of("plus.circle"), null, tint = C.accent) }, onClick = { Ui.sheet = Sheet.Wallet(id) })
    }
    if (s.byCurrency.isNotEmpty()) group("By currency") {
      s.byCurrency.entries.sortedByDescending { it.value }.forEachIndexed { i, (code, amt) ->
        if (i > 0) Divider(); PRow(World.currencyName(code), value = Money.format(amt, code, hidden), valueColor = C.label)
      }
    }
    if (group != null && group.memberIds.isNotEmpty()) {
      val balances = Splits.balances(db.splitEntries.filter { it.groupId == group.id })
      group("People", footer = "Split an expense with \"${group.name}\" in Quick Add › Split.") {
        db.friends.filter { it.id in group.memberIds }.forEachIndexed { i, f ->
          if (i > 0) Divider(56.dp)
          val b = balances[f.id] ?: 0
          PRow(f.name, leading = { Avatar(f.name) }, chevron = true, onClick = { Ui.push(Route.Friend(f.id, group.id)) }) {
            Text(when { b > 0 -> "owes ${Money.format(b)}"; b < 0 -> "you owe ${Money.format(-b)}"; else -> "settled" }, style = T.subhead,
              color = when { b > 0 -> C.income; b < 0 -> C.expense; else -> C.secondary })
          }
        }
        Divider()
        PRow("Settle Up", titleColor = C.accent, leading = { Icon(Sym.of("checkmark.circle"), null, tint = C.accent) }, chevron = true, onClick = { Ui.push(Route.Group(group.id)) })
      }
    }
    group("Expenses (${mine.size})") {
      if (mine.isEmpty()) Text("No expenses yet. While the trip is on, new expenses link to it on their own.", style = T.subhead, color = C.secondary, modifier = Modifier.padding(16.dp))
      mine.take(100).forEachIndexed { i, t -> if (i > 0) Divider(64.dp); TxnRow(t, l) }
    }
    trip.notes?.takeIf { it.isNotBlank() }?.let { n -> group("Notes") { Text(n, style = T.body, color = C.label, modifier = Modifier.padding(16.dp)) } }
  }
  if (confirmDelete) AlertDialog({ confirmDelete = false }, containerColor = C.card, title = { Text("Delete ${trip.name}?", style = T.headline, color = C.label) },
    text = { Text("Its expenses stay in your history, just no longer linked to a trip.", style = T.body, color = C.secondary) },
    confirmButton = { TextButton({
      Store.update { d -> d.copy(
        trips = d.trips.filterNot { it.id == id }, tripItems = d.tripItems.filterNot { it.tripId == id }, tripWallets = d.tripWallets.filterNot { it.tripId == id },
        transactions = d.transactions.map { if (it.tripId == id) it.copy(tripId = null, tripItemId = null, walletId = null) else it }) }
      confirmDelete = false; Ui.pop()
    }) { Text("Delete", color = C.expense, style = T.headline) } },
    dismissButton = { TextButton({ confirmDelete = false }) { Text("Cancel", color = C.accent) } })
}

@Composable private fun TripHero(trip: Trip, s: TripMath.Summary, k: TripKinds.Kind, hidden: Boolean) {
  Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(26.dp)).background(Brush.linearGradient(listOf(hex(k.color), hex(k.color).copy(alpha = 0.7f)))).padding(20.dp),
    verticalArrangement = Arrangement.spacedBy(14.dp)) {
    Row(verticalAlignment = Alignment.CenterVertically) {
      Icon(Sym.of(k.icon), null, tint = Color.White, modifier = Modifier.size(28.dp))
      Spacer(Modifier.weight(1f))
      Text(tripStatusText(s), style = T.subhead.copy(fontWeight = FontWeight.SemiBold), color = Color.White,
        modifier = Modifier.clip(CircleShape).background(Color.White.copy(alpha = 0.2f)).padding(horizontal = 10.dp, vertical = 5.dp))
    }
    Column {
      Text(trip.name, style = T.title2.copy(fontWeight = FontWeight.Bold), color = Color.White, maxLines = 2)
      Text(listOfNotNull(tripDates(trip), trip.places.takeIf { it.isNotEmpty() }?.joinToString(", ") { it.name }).joinToString(" · "),
        style = T.subhead, color = Color.White.copy(alpha = 0.85f))
    }
    Row(verticalAlignment = Alignment.Bottom) {
      Column(Modifier.weight(1f)) {
        Text("You've spent", style = T.caption, color = Color.White.copy(alpha = 0.85f))
        Text(Money.format(s.spent, hidden), style = T.amount(34, FontWeight.Bold), color = Color.White, maxLines = 1)
      }
      Column(horizontalAlignment = Alignment.End) {
        if (s.budget > 0) {
          Text(if (s.remaining >= 0) "${Money.format(s.remaining, hidden)} left" else "${Money.format(-s.remaining, hidden)} over", style = T.subhead.copy(fontWeight = FontWeight.SemiBold), color = Color.White)
          Text("of ${Money.format(s.budget, hidden)}", style = T.caption, color = Color.White.copy(alpha = 0.85f))
        }
        if (trip.travellers > 1) Text("${Money.format(s.perPerson, hidden)} per person", style = T.caption, color = Color.White.copy(alpha = 0.85f))
      }
    }
    if (s.budget > 0) Box(Modifier.fillMaxWidth().height(8.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.25f))) {
      Box(Modifier.fillMaxWidth(s.progress.coerceIn(0.02, 1.0).toFloat()).fillMaxHeight().clip(CircleShape).background(if (s.overBudget) hex("#FFB4B4") else Color.White))
    }
  }
}

/** Cash or a forex card for a trip: what you carry, in which currency, at what rate. */
@Composable fun WalletSheet(tripId: String) {
  val db = Store.value
  val trip = db.trips.firstOrNull { it.id == tripId } ?: return
  val ctx = LocalContext.current
  val scope = rememberCoroutineScope()
  val base = Money.base
  val tripCodes = trip.places.mapNotNull { it.currency }.filter { it != base }.distinct()
  var label by remember { mutableStateOf(if (trip.international) "Forex" else "Cash") }
  var currency by remember { mutableStateOf<String?>(null) }
  var amount by remember { mutableStateOf("") }
  var rateText by remember { mutableStateOf("") }
  var picking by remember { mutableStateOf(false) }
  fun setCurrency(c: String) {
    currency = if (c == base) null else c
    if (currency != null) scope.launch { Currency.rates(ctx)?.let { Fx.rate(c, base, it.inrPer) }?.let { rateText = "%.4f".format(it) } }
  }
  LaunchedEffect(Unit) { if (trip.international) tripCodes.firstOrNull()?.let { setCurrency(it) } }
  PSheet({ Ui.sheet = null }) {
    SheetHeader(if (trip.international) "Cash or Forex" else "Cash", canSave = Money.parse(amount) != null, onCancel = { Ui.sheet = null }) {
      val a = Money.parse(amount) ?: return@SheetHeader
      val rate = if (currency == null) 1.0 else rateText.toDoubleOrNull() ?: 1.0
      Store.update { d -> d.copy(tripWallets = d.tripWallets + TripWallet(tripId = tripId, label = label.trim().ifEmpty { "Cash" }, currency = currency, amount = a, rate = rate)) }
      Ui.sheet = null
    }
    LazyColumn {
      group(footer = if (currency == null) "Cash you take along. Spends paid from it show how much is left."
        else "Use the rate you bought it at, so the trip's totals match what it really cost you.") {
        FieldRow(label, { label = it }, if (trip.international) "Name, e.g. Baht cash, Niyo forex card" else "Name, e.g. Cash")
        Divider()
        PickerRow("Currency", (listOf(base) + tripCodes + "other").map { it to (if (it == "other") "Other…" else it) }, currency ?: base) {
          if (it == "other") picking = true else setCurrency(it)
        }
        Divider()
        FieldRow(amount, { amount = it }, "Amount in ${currency ?: base}", number = true)
        if (currency != null) { Divider(); FieldRow(rateText, { rateText = it }, "${Money.symbol} per 1 $currency", number = true) }
      }
      item { Spacer(Modifier.height(32.dp)) }
    }
  }
  if (picking) CurrencyPickerDialog("Currency", onDismiss = { picking = false }) { setCurrency(it); picking = false }
}
