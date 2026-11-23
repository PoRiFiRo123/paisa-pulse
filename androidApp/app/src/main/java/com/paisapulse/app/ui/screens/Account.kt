package com.paisapulse.app.ui.screens

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.ContactsContract
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.paisapulse.app.cloud.Cloud
import com.paisapulse.app.data.*
import com.paisapulse.app.logic.*
import com.paisapulse.app.ui.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// Paisa Pulse accounts: sign in with an email code, your profile, people, invites and the inbox.
// Same screens on iPhone (apple/App/Cloud/AccountViews.swift).

/** Runs a cloud call, showing its error as a toast. */
private fun CoroutineScopeRun(scope: kotlinx.coroutines.CoroutineScope, busy: MutableState<Boolean>, block: suspend () -> Unit) {
  scope.launch {
    busy.value = true
    try { block() } catch (e: Cloud.CloudError) { Ui.show(e.message ?: "Something went wrong") }
    catch (e: java.io.IOException) { Ui.show("No connection. Try again.") }
    finally { busy.value = false }
  }
}

@Composable fun AccountScreen() {
  val scope = rememberCoroutineScope()
  val ctx = LocalContext.current
  val busy = remember { mutableStateOf(false) }
  if (!Cloud.configured) {
    PScreen("Account", back = true) {
      item { Box(Modifier.padding(top = 40.dp)) { EmptyHint("Accounts are coming", "person.crop.circle", "This build doesn't have accounts switched on yet. Everything else works without one.") } }
    }
    return
  }
  if (!Cloud.signedIn) { SignInScreen(); return }
  val s = Cloud.state
  val me = s.me
  if (me != null && me.username == null) { PickUsername(me.name); return }
  var name by remember(me?.name) { mutableStateOf(me?.name ?: "") }
  var upi by remember(me?.upiId) { mutableStateOf(me?.upiId ?: "") }
  var phone by remember { mutableStateOf("") }
  var confirmDelete by remember { mutableStateOf(false) }
  var changing by remember { mutableStateOf(false) }
  var newPassword by remember { mutableStateOf("") }
  LaunchedEffect(Unit) { Cloud.syncNow() }
  PScreen("Account", back = true) {
    group {
      Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Avatar(me?.label ?: "?", 72.dp)
        Text(me?.label ?: "…", style = T.title2, color = C.label, modifier = Modifier.padding(top = 10.dp))
        Text(listOfNotNull(me?.username?.let { "@$it" }, s.email).joinToString(" · "), style = T.subhead, color = C.secondary)
        Text(when { Cloud.syncing -> "Syncing…"; Cloud.error != null -> Cloud.error!!; else -> "Up to date" }, style = T.caption,
          color = if (Cloud.error != null) C.expense else C.secondary, modifier = Modifier.padding(top = 6.dp))
      }
    }
    group {
      PRow("People", leading = { Icon2("person.2.fill") }, value = "${s.people.count { it.connected }}", chevron = true, onClick = { Ui.push(Route.People()) })
      Divider(56.dp)
      PRow("Inbox", leading = { Icon2("bell.fill") }, chevron = true, onClick = { Ui.push(Route.Inbox) }) {
        val n = s.unread + (Cloud.me?.let { s.pendingShares(it).size + s.pendingSettlements(it).size } ?: 0)
        if (n > 0) Text("$n", style = T.caption.copy(fontWeight = FontWeight.Bold), color = Color.White,
          modifier = Modifier.clip(CircleShape).background(C.expense).padding(horizontal = 8.dp, vertical = 2.dp))
      }
    }
    group("Profile", footer = "Friends see your name and UPI ID. Your phone number is kept only as a fingerprint (a hash), so friends who have it can find you; nobody can read it.") {
      FieldRow(name, { name = it }, "Your name")
      Divider(); FieldRow(upi, { upi = it }, "UPI ID, e.g. you@okaxis")
      Divider(); FieldRow(phone, { phone = it.filter { c -> c.isDigit() || c == '+' || c == ' ' } }, if (s.hasPhone) "Phone saved · type to change" else "Phone (optional)", number = true)
      Divider(); PRow(if (busy.value) "Saving…" else "Save", titleColor = C.accent, onClick = {
        CoroutineScopeRun(scope, busy) {
          Cloud.updateProfile(null, name.trim(), upi.trim(), phone.takeIf { it.isNotBlank() })
          Prefs.set("myName", name.trim()); Prefs.set("myUpiId", upi.trim()); phone = ""; Ui.show("Saved")
        }
      })
      Divider(); PRow("Change Password", titleColor = C.accent, onClick = { changing = true })
      if (s.hasPhone) { Divider(); PRow("Remove Phone Number", titleColor = C.expense, onClick = { CoroutineScopeRun(scope, busy) { Cloud.updateProfile(null, null, null, "") } }) }
    }
    group(footer = "Only things you share go to the server: your profile, people you add, shared splits, groups and trips. Your accounts, balances and other transactions never leave this phone.") {
      PRow("Download My Data", leading = { Icon2("square.and.arrow.down") }, onClick = {
        CoroutineScopeRun(scope, busy) {
          val f = java.io.File(java.io.File(ctx.cacheDir, "share").apply { mkdirs() }, "paisa-pulse-account.json").apply { writeText(Cloud.exportData()) }
          val uri = FileProvider.getUriForFile(ctx, ctx.packageName + ".files", f)
          ctx.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("application/json").putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION), "Your account data"))
        }
      })
      Divider(56.dp); PRow("Sign Out", leading = { Icon2("rectangle.portrait.and.arrow.right") }, onClick = { Cloud.signOut() })
      Divider(56.dp); PRow("Delete Account", titleColor = C.expense, leading = { Icon(Sym.of("trash"), null, tint = C.expense) }, onClick = { confirmDelete = true })
    }
  }
  if (changing) AlertDialog({ changing = false; newPassword = "" }, containerColor = C.card, title = { Text("New password", style = T.headline, color = C.label) },
    text = { Column { PasswordRow(newPassword, { newPassword = it }, "At least 8 characters") } },
    confirmButton = { TextButton({
      if (newPassword.length >= 8) { val p = newPassword; changing = false; newPassword = ""; CoroutineScopeRun(scope, busy) { Cloud.changePassword(p); Ui.show("Password changed") } }
    }) { Text("Change", color = if (newPassword.length >= 8) C.accent else C.tertiary, style = T.headline) } },
    dismissButton = { TextButton({ changing = false; newPassword = "" }) { Text("Cancel", color = C.accent) } })
  if (confirmDelete) AlertDialog({ confirmDelete = false }, containerColor = C.card, title = { Text("Delete your account?", style = T.headline, color = C.label) },
    text = { Text("Your profile, invites and everything you shared are removed from the server for good. Your splits stay on this phone.", style = T.body, color = C.secondary) },
    confirmButton = { TextButton({ confirmDelete = false; CoroutineScopeRun(scope, busy) { Cloud.deleteAccount(); Ui.show("Account deleted") } }) { Text("Delete", color = C.expense, style = T.headline) } },
    dismissButton = { TextButton({ confirmDelete = false }) { Text("Cancel", color = C.accent) } })
}

@Composable private fun SignInScreen() {
  val scope = rememberCoroutineScope()
  val busy = remember { mutableStateOf(false) }
  var creating by remember { mutableStateOf(true) }
  var email by remember { mutableStateOf("") }
  var password by remember { mutableStateOf("") }
  var again by remember { mutableStateOf("") }
  val valid = Regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$").matches(email.trim())
  val ready = valid && password.length >= 8 && (!creating || again == password)
  PScreen("Account", back = true) {
    item {
      Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.size(84.dp).clip(RoundedCornerShape(24.dp)).background(C.accent), contentAlignment = Alignment.Center) {
          Icon(Sym.of("person.2.fill"), null, tint = Color.White, modifier = Modifier.size(40.dp))
        }
        Text("Split with friends on Paisa Pulse", style = T.title2, color = C.label, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 16.dp))
        Text("Add friends, split bills and trips, and they see their share on their phone.",
          style = T.subhead, color = C.secondary, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 6.dp))
      }
    }
    item { Segmented(listOf("Create Account", "Sign In"), if (creating) 0 else 1, Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) { creating = it == 0 } }
    group(footer = when {
      creating && password.isNotEmpty() && password.length < 8 -> "At least 8 characters."
      creating && again.isNotEmpty() && again != password -> "The passwords don't match."
      creating -> "Keep your password safe: there's no email reset yet. Only what you share goes to the server; your own money stays on this phone."
      else -> "Forgot it? There's no email reset yet; make a new account and add your friends again."
    }) {
      FieldRow(email, { email = it.trim() }, "Email")
      Divider(); PasswordRow(password, { password = it }, "Password")
      if (creating) { Divider(); PasswordRow(again, { again = it }, "Password again") }
      Divider()
      PRow(if (busy.value) "Please wait…" else if (creating) "Create Account" else "Sign In", titleColor = if (ready && !busy.value) C.accent else C.tertiary, onClick = {
        if (ready && !busy.value) CoroutineScopeRun(scope, busy) { if (creating) Cloud.signUp(email, password) else Cloud.signIn(email, password) }
      })
    }
  }
}

@Composable private fun PasswordRow(value: String, onChange: (String) -> Unit, placeholder: String) {
  var show by remember { mutableStateOf(false) }
  Row(verticalAlignment = Alignment.CenterVertically) {
    androidx.compose.foundation.text.BasicTextField(value, onChange, singleLine = true, textStyle = T.body.copy(color = C.label),
      cursorBrush = androidx.compose.ui.graphics.SolidColor(C.accent),
      visualTransformation = if (show) androidx.compose.ui.text.input.VisualTransformation.None else androidx.compose.ui.text.input.PasswordVisualTransformation(),
      keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Password),
      modifier = Modifier.weight(1f).padding(16.dp),
      decorationBox = { inner -> Box { if (value.isEmpty()) Text(placeholder, style = T.body, color = C.tertiary); inner() } })
    Icon(Sym.of(if (show) "eye.slash" else "eye"), if (show) "Hide" else "Show", tint = C.secondary,
      modifier = Modifier.padding(end = 16.dp).size(20.dp).clickable { show = !show })
  }
}

@Composable private fun PickUsername(current: String) {
  val scope = rememberCoroutineScope()
  val busy = remember { mutableStateOf(false) }
  var name by remember { mutableStateOf(current.ifBlank { Prefs.myName }) }
  var user by remember { mutableStateOf(CloudLogic.cleanUsername(Prefs.myName.replace(' ', '_'))) }
  var free by remember { mutableStateOf<Boolean?>(null) }
  LaunchedEffect(user) {
    free = null
    if (CloudLogic.validUsername(user)) { delay(400); free = runCatching { Cloud.usernameAvailable(user) }.getOrNull() }
  }
  PScreen("Your Profile", back = true) {
    item { Text("Pick how friends find you. You can change it later.", style = T.subhead, color = C.secondary, modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) }
    group(footer = when { user.isEmpty() -> "3 to 20 letters, numbers or _"; !CloudLogic.validUsername(user) -> "3 to 20 letters, numbers or _"
      free == true -> "@$user is free"; free == false -> "@$user is taken"; else -> "Checking…" }) {
      FieldRow(name, { name = it }, "Your name")
      Divider(); FieldRow(user, { user = CloudLogic.cleanUsername(it) }, "username")
    }
    group {
      PRow(if (busy.value) "Saving…" else "Continue", titleColor = if (free == true && name.isNotBlank()) C.accent else C.tertiary, onClick = {
        if (free == true && name.isNotBlank() && !busy.value) CoroutineScopeRun(scope, busy) { Cloud.updateProfile(user, name.trim(), Prefs.myUpiId.ifBlank { null }, null) }
      })
    }
  }
}

/** Find people, add them, share your invite, and link friends in your splits to their accounts. */
@Composable fun PeopleScreen(invite: String?, link: String?) {
  val ctx = LocalContext.current
  val scope = rememberCoroutineScope()
  val busy = remember { mutableStateOf(false) }
  val db by Store.db.collectAsState()
  val s = Cloud.state
  var q by remember { mutableStateOf("") }
  var results by remember { mutableStateOf<List<CloudLogic.Person>>(emptyList()) }
  var contacts by remember { mutableStateOf<List<Pair<CloudLogic.Person, String>>?>(null) }
  var code by remember { mutableStateOf<String?>(null) }
  var typed by remember { mutableStateOf("") }
  var pendingInvite by remember { mutableStateOf(invite) }
  val linking = link?.let { id -> db.friends.firstOrNull { it.id == id } }
  if (!Cloud.signedIn) { AccountScreen(); return }
  LaunchedEffect(q) { delay(350); results = if (q.trim().length >= 2) runCatching { Cloud.find(q.trim()) }.getOrDefault(emptyList()) else emptyList() }
  LaunchedEffect(Unit) { code = runCatching { Cloud.inviteCode() }.getOrNull() }
  val readContacts = {
    CoroutineScopeRun(scope, busy) {
      val phones = mutableListOf<String>()
      ctx.contentResolver.query(ContactsContract.CommonDataKinds.Phone.CONTENT_URI, arrayOf(ContactsContract.CommonDataKinds.Phone.NUMBER), null, null, null)?.use { c ->
        while (c.moveToNext()) c.getString(0)?.let { phones += it }
      }
      contacts = Cloud.matchContacts(phones.distinct())
    }
  }
  val askContacts = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok -> if (ok) readContacts() else Ui.show("Contacts permission is off") }

  fun choose(p: CloudLogic.Person) = CoroutineScopeRun(scope, busy) {
    if (!p.connected) Cloud.connect(p.id)
    if (linking != null) {
      // The mirror may already have made a friend for them: fold it into the one you picked.
      val dup = Store.value.friends.firstOrNull { it.userId == p.id && it.id != linking.id }
      Store.update { d -> d.copy(
        friends = d.friends.filterNot { it.id == dup?.id }.map { if (it.id == linking.id) it.copy(userId = p.id, upiId = it.upiId ?: p.upiId) else it },
        splitEntries = if (dup == null) d.splitEntries else d.splitEntries.map { if (it.friendId == dup.id) it.copy(friendId = linking.id) else it },
        splitGroups = if (dup == null) d.splitGroups else d.splitGroups.map { g -> g.copy(memberIds = g.memberIds.map { if (it == dup.id) linking.id else it }.distinct()) }) }
      Ui.show("${linking.name} is linked to @${p.username}"); Ui.pop(); Cloud.syncSoon()
    } else Ui.show("Added ${p.label}")
  }

  @Composable fun PersonRow(p: CloudLogic.Person, extra: String? = null) {
    val local = db.friends.firstOrNull { it.userId == p.id }
    PRow(p.label, subtitle = listOfNotNull(p.username?.let { "@$it" }, extra).joinToString(" · "), leading = { Avatar(p.label) },
      chevron = linking == null && p.connected && local != null,
      onClick = { if (linking != null || !p.connected) choose(p) else local?.let { Ui.push(Route.Friend(it.id)) } }) {
      if (linking != null) Text("Link", style = T.subhead, color = C.accent)
      else if (!p.connected) Text("Add", style = T.subhead.copy(fontWeight = FontWeight.SemiBold), color = Color.White,
        modifier = Modifier.clip(CircleShape).background(C.accent).padding(horizontal = 14.dp, vertical = 6.dp))
    }
  }

  PScreen(if (linking != null) "Link ${linking.name}" else "People", back = true) {
    if (linking != null) item {
      Text("Pick ${linking.name}'s Paisa Pulse account. Splits with them then show up on their phone too.", style = T.subhead, color = C.secondary,
        modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
    }
    group(footer = "Search by @username, email or phone number.") {
      FieldRow(q, { q = it }, "Username, email or phone")
      results.forEach { Divider(56.dp); PersonRow(it) }
      if (q.trim().length >= 2 && results.isEmpty()) { Divider(); Text("No one found. Send them your invite below.", style = T.subhead, color = C.secondary, modifier = Modifier.padding(16.dp)) }
    }
    group("From your contacts", footer = "Phone numbers are turned into fingerprints on this phone before matching; the numbers themselves aren't sent.") {
      if (contacts == null) PRow("Find Friends from Contacts", titleColor = C.accent, leading = { Icon2("person.crop.circle.badge.plus") }, onClick = {
        if (ContextCompat.checkSelfPermission(ctx, Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED) readContacts()
        else askContacts.launch(Manifest.permission.READ_CONTACTS)
      })
      else if (contacts!!.isEmpty()) Text("None of your contacts are on Paisa Pulse yet.", style = T.subhead, color = C.secondary, modifier = Modifier.padding(16.dp))
      else contacts!!.forEachIndexed { i, (p, phone) -> if (i > 0) Divider(56.dp); PersonRow(p, phone) }
    }
    if (linking == null) {
      val mine = s.people.filter { it.connected }.sortedBy { it.label.lowercase() }
      if (mine.isNotEmpty()) group("Your people") { mine.forEachIndexed { i, p -> if (i > 0) Divider(56.dp); PersonRow(p) } }
      group("Invite", footer = "Friends scan this with their camera, or open the link, to add you. Or type their code below.") {
        code?.let { c ->
          val link2 = Cloud.inviteLink(c)
          val bmp = remember(link2) { qrBitmap(link2, 560).asImageBitmap() }
          Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Image(bmp, "Invite QR code", modifier = Modifier.size(200.dp).clip(RoundedCornerShape(16.dp)).background(Color.White).padding(8.dp))
            Text("Your code: $c", style = T.headline, color = C.label, modifier = Modifier.padding(top = 10.dp))
          }
          Divider()
          PRow("Share Invite Link", titleColor = C.accent, leading = { Icon2("square.and.arrow.up") }, onClick = {
            ctx.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain")
              .putExtra(Intent.EXTRA_TEXT, "Add me on Paisa Pulse to split bills and trips: $link2"), "Invite"))
          })
        } ?: Text("Getting your invite…", style = T.subhead, color = C.secondary, modifier = Modifier.padding(16.dp))
        Divider()
        Row(verticalAlignment = Alignment.CenterVertically) {
          FieldRow(typed, { typed = it.uppercase().filter { c -> c.isLetterOrDigit() }.take(12) }, "Friend's code", modifier = Modifier.weight(1f))
          Text("Add", style = T.body, color = if (typed.length >= 6) C.accent else C.tertiary, modifier = Modifier.clickable {
            if (typed.length >= 6) CoroutineScopeRun(scope, busy) { val p = Cloud.acceptInvite(typed); typed = ""; Ui.show("Added ${p.label}") }
          }.padding(16.dp))
        }
      }
    }
  }
  pendingInvite?.let { c ->
    AlertDialog({ pendingInvite = null }, containerColor = C.card, title = { Text("Add this person?", style = T.headline, color = C.label) },
      text = { Text("Accept the invite with code $c to split bills and trips with them.", style = T.body, color = C.secondary) },
      confirmButton = { TextButton({ pendingInvite = null; CoroutineScopeRun(scope, busy) { val p = Cloud.acceptInvite(c); Ui.show("Added ${p.label}") } }) { Text("Add", color = C.accent, style = T.headline) } },
      dismissButton = { TextButton({ pendingInvite = null }) { Text("Not Now", color = C.accent) } })
  }
}

/** Splits and settle-ups waiting for you, and what happened lately. */
@Composable fun InboxScreen() {
  val scope = rememberCoroutineScope()
  val busy = remember { mutableStateOf(false) }
  val s = Cloud.state
  val me = Cloud.me ?: run { AccountScreen(); return }
  val shares = s.pendingShares(me)
  val settles = s.pendingSettlements(me)
  LaunchedEffect(Unit) { while (true) { runCatching { Cloud.syncNow(); Cloud.markRead() }; delay(20_000) } }
  fun who(id: String?) = s.person(id)?.label ?: "Someone"
  PScreen("Inbox", back = true) {
    if (shares.isNotEmpty()) group("To accept", footer = "Accepted shares go into your balance with that person.") {
      shares.forEachIndexed { i, e ->
        if (i > 0) Divider()
        val my = e.shares.first { it.userId == me }
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
          Text(e.title, style = T.headline, color = C.label)
          Text((if (e.paidBy == me) "${who(e.createdBy)} says you paid ${Money.format(e.amount, e.currency)}" else "${who(e.paidBy)} paid ${Money.format(e.amount, e.currency)}") +
            " · " + shortDate.format(java.time.Instant.ofEpochMilli(e.occurredAt).atZone(java.time.ZoneId.systemDefault()).toLocalDate()), style = T.subhead, color = C.secondary)
          if (e.paidBy != me) Text("Your share: ${Money.format(my.amount, e.currency)}", style = T.amount(17), color = C.expense)
          else Text("They owe you ${Money.format(e.shares.filter { it.userId != me }.sumOf { it.amount }, e.currency)}", style = T.amount(17), color = C.income)
          Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Button({ CoroutineScopeRun(scope, busy) { Cloud.respondShare(e.id, true) } }, colors = ButtonDefaults.buttonColors(containerColor = C.accent)) { Text("Accept") }
            OutlinedButton({ CoroutineScopeRun(scope, busy) { Cloud.respondShare(e.id, false) } }) { Text("Decline", color = C.expense) }
          }
        }
      }
    }
    if (settles.isNotEmpty()) group("To confirm") {
      settles.forEachIndexed { i, st ->
        if (i > 0) Divider()
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
          Text(if (st.to == me) "${who(st.from)} paid you ${Money.format(st.amount, st.currency)}" else "${who(st.to)} says you paid them ${Money.format(st.amount, st.currency)}",
            style = T.headline, color = C.label)
          st.note?.let { Text(it, style = T.subhead, color = C.secondary) }
          Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Button({ CoroutineScopeRun(scope, busy) { Cloud.respondSettlement(st.id, true) } }, colors = ButtonDefaults.buttonColors(containerColor = C.accent)) { Text("Confirm") }
            OutlinedButton({ CoroutineScopeRun(scope, busy) { Cloud.respondSettlement(st.id, false) } }) { Text(if (st.to == me) "Didn't Get It" else "Not Me", color = C.expense) }
          }
        }
      }
    }
    if (s.inbox.isEmpty() && shares.isEmpty() && settles.isEmpty()) item {
      Box(Modifier.padding(top = 40.dp)) { EmptyHint("Nothing new", "bell", "When friends split something with you or add you to a trip, it shows up here.") }
    }
    if (s.inbox.isNotEmpty()) group("Recent") {
      s.inbox.take(60).forEachIndexed { i, n ->
        if (i > 0) Divider(56.dp)
        PRow(n.title, subtitle = listOfNotNull(n.body, shortDate.format(java.time.Instant.ofEpochMilli(n.at).atZone(java.time.ZoneId.systemDefault()).toLocalDate())).joinToString(" · "),
          leading = { Avatar(who(n.actor)) }, titleColor = if (n.read) C.label else C.accent)
      }
    }
  }
}

/** Settings row: your account, or an invitation to make one. */
@Composable fun AccountRow() {
  val me = Cloud.state.me
  val n = Cloud.me?.let { Cloud.state.unread + Cloud.state.pendingShares(it).size + Cloud.state.pendingSettlements(it).size } ?: 0
  PRow(if (Cloud.signedIn) me?.label ?: "Your account" else "Sign In to Split with Friends",
    subtitle = if (Cloud.signedIn) me?.username?.let { "@$it" } else "Friends see shared splits and trips on their phone",
    leading = { if (Cloud.signedIn && me != null) Avatar(me.label, 40.dp) else CategoryBadge("person.crop.circle.fill", "#5E5CE6", 40.dp) },
    chevron = true, onClick = { Ui.push(Route.Account) }) {
    if (n > 0) Text("$n", style = T.caption.copy(fontWeight = FontWeight.Bold), color = Color.White,
      modifier = Modifier.clip(CircleShape).background(C.expense).padding(horizontal = 8.dp, vertical = 2.dp))
  }
}

/** On a friend's page: their Paisa Pulse account, or a way to link one. */
@Composable fun FriendAccountGroupContent(f: Friend) {
  val p = f.userId?.let { u -> Cloud.state.person(u) }
  if (f.userId != null) {
    PRow("On Paisa Pulse", subtitle = p?.username?.let { "@$it" } ?: "Linked", leading = { Icon2("checkmark.seal.fill") })
    Divider(56.dp)
    PRow("Unlink", titleColor = C.expense, leading = { Icon(Sym.of("link"), null, tint = C.expense) }, onClick = { Cloud.link(f.id, null) })
  } else {
    PRow("Link to Their Paisa Pulse Account", titleColor = C.accent, leading = { Icon2("link") }, onClick = {
      if (Cloud.signedIn) Ui.push(Route.People(link = f.id)) else Ui.push(Route.Account)
    })
  }
}
