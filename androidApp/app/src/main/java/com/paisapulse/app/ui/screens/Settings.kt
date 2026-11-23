package com.paisapulse.app.ui.screens

import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import com.paisapulse.app.BuildConfig
import com.paisapulse.app.data.*
import com.paisapulse.app.logic.Money
import com.paisapulse.app.ui.*
import com.paisapulse.app.work.BackupOps
import com.paisapulse.app.work.BackupPassword
import com.paisapulse.app.work.Services
import com.paisapulse.app.work.Updates
import kotlinx.coroutines.launch
import java.io.File

@Composable private fun Badge(sym: String, color: String) = CategoryBadge(sym, color, 29.dp)

@Composable fun SettingsScreen() {
  val ctx = LocalContext.current
  val scope = rememberCoroutineScope()
  val notifPerm = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { Services.refreshNotifications() }
  fun notif(key: String, v: Boolean) {
    Prefs.set(key, v)
    if (v && Build.VERSION.SDK_INT >= 33) notifPerm.launch(android.Manifest.permission.POST_NOTIFICATIONS) else Services.refreshNotifications()
  }
  var checking by remember { mutableStateOf(false) }
  var upToDate by remember { mutableStateOf(false) }
  LaunchedEffect(Unit) { Updates.check() }
  PScreen("Settings") {
    Updates.available?.let { u ->
      group(footer = "Downloads the new APK. Open it to install over this one. Your data stays.") {
        PRow("Software Update", leading = { Badge("arrow.down.circle.fill", "#34C759") }, value = "Build ${u.build}", chevron = true,
          onClick = { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(u.apk ?: u.page))) })
      }
    }
    group {
      PRow("Home Screen", leading = { Badge("square.grid.2x2.fill", "#5E5CE6") }, chevron = true, onClick = { Ui.sheet = Sheet.HomeLayout })
    }
    group("Appearance") {
      PickerRow("Theme", listOf("system" to "System", "light" to "Light", "dark" to "Dark"), Prefs.theme, leading = { Badge("circle.lefthalf.filled", "#5856D6") }) { Prefs.set("theme", it) }
      Divider(56.dp)
      PRow("Accent colour", leading = { Badge("paintpalette.fill", "#FF2D55") }, chevron = true, onClick = { Ui.push(Route.Accent) }) {
        Box(Modifier.size(18.dp).background(C.accent, androidx.compose.foundation.shape.CircleShape))
      }
      Divider(56.dp)
      PRow("App icon", leading = { Badge("square.grid.2x2.fill", "#007AFF") }, chevron = true, onClick = { Ui.push(Route.AppIcon) }) {
        androidx.compose.foundation.Image(androidx.compose.ui.res.painterResource(AppIcons.preview(AppIcons.current(ctx))), null,
          modifier = Modifier.size(28.dp).clip(androidx.compose.foundation.shape.RoundedCornerShape(7.dp)))
      }
    }
    group("Money") {
      PRow("Categories", leading = { Badge("square.grid.2x2.fill", "#FF9500") }, chevron = true, onClick = { Ui.push(Route.Categories) })
      Divider(56.dp); PRow("Budgets", leading = { Badge("gauge.with.dots.needle.33percent", "#5E5CE6") }, chevron = true, onClick = { Ui.push(Route.Budgets) })
      Divider(56.dp); PRow("Recurring", leading = { Badge("repeat", "#30B0C7") }, chevron = true, onClick = { Ui.push(Route.Recurring) })
      Divider(56.dp); PRow("Subscriptions", leading = { Badge("creditcard.and.123", "#32ADE6") }, chevron = true, onClick = { Ui.push(Route.Subscriptions) })
      Divider(56.dp); PRow("Templates", leading = { Badge("bolt.fill", "#FF9500") }, chevron = true, onClick = { Ui.push(Route.Templates) })
      Divider(56.dp); PRow("Goals", leading = { Badge("target", "#1E9E5A") }, chevron = true, onClick = { Ui.push(Route.Goals) })
      Divider(56.dp); PRow("Splits", leading = { Badge("person.2.fill", "#007AFF") }, chevron = true, onClick = { Ui.push(Route.Splits) })
      Divider(56.dp); PRow("Loans", leading = { Badge("banknote.fill", "#E5484D") }, chevron = true, onClick = { Ui.push(Route.Loans) })
      Divider(56.dp); PickerRow("Month starts on", (1..28).map { it to ordinal(it) }, Prefs.monthStartDay, leading = { Badge("calendar", "#FF3B30") }) { Prefs.set("monthStartDay", it) }
      Divider(56.dp); PickerRow("Week starts on", listOf(1 to "Sunday", 2 to "Monday"), Prefs.weekStartDay, leading = { Badge("calendar.day.timeline.left", "#FF9500") }) { Prefs.set("weekStartDay", it) }
    }
    group("See") {
      PRow("Planning", leading = { Badge("airplane", "#2563EB") }, chevron = true, onClick = { Ui.push(Route.Planning) })
      Divider(56.dp)
      PRow("Insights", leading = { Badge("chart.bar.xaxis", "#AF52DE") }, chevron = true, onClick = { Ui.push(Route.Insights) })
      Divider(56.dp); PRow("Calendar", leading = { Badge("calendar", "#FF2D55") }, chevron = true, onClick = { Ui.push(Route.Calendar) })
      Divider(56.dp); PRow("Net Worth", leading = { Badge("chart.line.uptrend.xyaxis", "#34C759") }, chevron = true, onClick = { Ui.push(Route.NetWorth) })
      Divider(56.dp); PRow("Monthly Recap", leading = { Badge("sparkles", "#5E5CE6") }, chevron = true, onClick = { Ui.push(Route.Recap(-1)) })
      Divider(56.dp); PRow("Tags", leading = { Badge("number", "#8E8E93") }, chevron = true, onClick = { Ui.push(Route.Tags) })
      Divider(56.dp); PRow("Currency Converter", leading = { Badge("dollarsign.arrow.circlepath", "#30B0C7") }, chevron = true, onClick = { Ui.push(Route.Converter) })
      Divider(56.dp); PRow("Main Currency", leading = { Badge("banknote.fill", "#34C759") }, value = Prefs.baseCurrency, chevron = true, onClick = { Ui.push(Route.MainCurrency) })
    }
    group("Notifications", footer = "Budget alerts at 80% and 100%. Bill reminders 3 days before a card's due day.") {
      ToggleRow("Budget alerts", Prefs.notifyBudgets, leading = { Badge("bell.badge.fill", "#FF9500") }) { notif("notifyBudgets", it) }
      Divider(56.dp); ToggleRow("Card bill reminders", Prefs.notifyBills, leading = { Badge("creditcard.fill", "#007AFF") }) { notif("notifyBills", it) }
      Divider(56.dp); ToggleRow("Sunday summary", Prefs.notifyWeekly, leading = { Badge("envelope.fill", "#5E5CE6") }) { notif("notifyWeekly", it) }
    }
    group("Privacy", footer = "Merchant logos load from Google's icon service: only the shop's website (like swiggy.com) is sent. Off, rows show a coloured letter.") {
      ToggleRow("Fingerprint / Face Lock", Prefs.appLock, leading = { Badge("faceid", "#34C759") }) { Prefs.set("appLock", it) }
      Divider(56.dp); ToggleRow("Hide amounts", Prefs.hideAmounts, leading = { Badge("eye.slash.fill", "#8E8E93") }) { Prefs.set("hideAmounts", it) }
      Divider(56.dp); ToggleRow("Merchant logos", Prefs.merchantLogos, leading = { Badge("photo", "#FF9500") }) { Prefs.set("merchantLogos", it) }
    }
    group("Data") {
      PRow("Import Statement", leading = { Badge("doc.text.viewfinder", "#007AFF") }, chevron = true, onClick = { Ui.push(Route.Import()) })
      Divider(56.dp); PRow("Add from Screenshots", leading = { Badge("photo.on.rectangle", "#AF52DE") }, chevron = true, onClick = { Ui.push(Route.Capture("screenshot")) })
      Divider(56.dp); PRow("Say It (voice)", leading = { Badge("mic.fill", "#FF2D55") }, chevron = true, onClick = { Ui.push(Route.Capture("voice")) })
      Divider(56.dp); PRow("Clean Up Data", leading = { Badge("trash.fill", "#8E8E93") }, chevron = true, onClick = { Ui.push(Route.Cleanup) })
      Divider(56.dp); PRow("Backup & Restore", leading = { Badge("externaldrive.fill", "#5E5CE6") }, chevron = true, onClick = { Ui.push(Route.Backup) })
      Divider(56.dp); PRow("Export CSV", leading = { Badge("tablecells.fill", "#1E9E5A") }, onClick = {
        val dir = File(ctx.cacheDir, "share").apply { mkdirs() }
        val f = File(dir, "paisa-pulse-transactions.csv").apply { writeText(BackupOps.csv(Store.value)) }
        val uri = FileProvider.getUriForFile(ctx, "com.paisapulse.app.files", f)
        ctx.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/csv").putExtra(Intent.EXTRA_STREAM, uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION), "Export CSV"))
      })
    }
    item {
      Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text("Paisa Pulse ${BuildConfig.VERSION_NAME} (build ${BuildConfig.VERSION_CODE})", style = T.footnote, color = C.secondary)
        if (BuildConfig.VERSION_CODE > 1) TextButton({ scope.launch { checking = true; upToDate = !Updates.check(); checking = false } }, enabled = !checking) {
          Text(if (checking) "Checking…" else if (upToDate) "You're up to date" else "Check for Updates", style = T.footnote, color = C.accent)
        }
        Text("No account. No servers. Your data stays on this phone.", style = T.footnote, color = C.secondary)
      }
    }
  }
}

fun ordinal(n: Int) = n.toString() + if (n % 100 in 11..13) "th" else when (n % 10) { 1 -> "st"; 2 -> "nd"; 3 -> "rd"; else -> "th" }

@Composable fun BackupScreen() {
  val ctx = LocalContext.current
  var files by remember { mutableStateOf(BackupOps.list(ctx)) }
  var pending by remember { mutableStateOf<Db?>(null) }
  var error by remember { mutableStateOf<String?>(null) }
  var locked by remember { mutableStateOf<String?>(null) }
  var protected by remember { mutableStateOf(BackupPassword.get(ctx) != null) }
  var settingPassword by remember { mutableStateOf(false) }
  fun open(text: String) {
    runCatching { BackupOps.open(ctx, text) }.onSuccess { pending = it }
      .onFailure { if (it is BackupOps.NeedsPassword) locked = text else error = it.message }
  }
  val exporter = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
    uri ?: return@rememberLauncherForActivityResult
    ctx.contentResolver.openOutputStream(uri)?.use { it.write(BackupOps.exportFile(ctx).toByteArray()) }; Ui.show("Backup saved")
  }
  val importer = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
    uri ?: return@rememberLauncherForActivityResult
    runCatching { ctx.contentResolver.openInputStream(uri)!!.bufferedReader().readText() }.onSuccess { open(it) }.onFailure { error = it.message }
  }
  PScreen("Backup & Restore", back = true) {
    group(footer = "Daily backups stay on this phone (the last 14) and in your Google account's Android backup." +
      if (Prefs.lastBackupAt > 0) " Last: ${shortDate.format(java.time.Instant.ofEpochMilli(Prefs.lastBackupAt).atZone(java.time.ZoneId.systemDefault()).toLocalDate())}." else "") {
      ToggleRow("Daily backup", Prefs.autoBackup) { Prefs.set("autoBackup", it) }
      Divider(); ToggleRow("Protect with a password", protected) { on ->
        if (on) settingPassword = true else { BackupPassword.set(ctx, null); protected = false; Ui.show("Backups are no longer encrypted") }
      }
      Divider(); PRow("Back Up Now", titleColor = C.accent, onClick = { BackupOps.write(ctx); files = BackupOps.list(ctx); Ui.show("Backed up") })
    }
    group("Google Drive", footer = "Pick Google Drive in the list to keep a copy off your phone. The same file restores on iPhone.") {
      PRow("Save to Google Drive or Files…", titleColor = C.accent, leading = { Icon2("square.and.arrow.up") }, onClick = { exporter.launch(BackupOps.fileName()) })
      Divider(56.dp); PRow("Restore from a File…", titleColor = C.accent, leading = { Icon2("square.and.arrow.down") }, onClick = { importer.launch(arrayOf("application/json", "*/*")) })
    }
    if (files.isNotEmpty()) group("On this phone") {
      files.forEachIndexed { i, f -> if (i > 0) Divider()
        PRow(f.nameWithoutExtension.removePrefix("paisa-pulse-"), titleColor = C.accent, onClick = { open(f.readText()) }) }
    }
  }
  pending?.let { file ->
    AlertDialog({ pending = null }, containerColor = C.card, title = { Text("Replace everything with this backup?") },
      text = { Text("${file.transactions.size} transactions and ${file.accounts.size} accounts. Your current data on this phone is replaced.") },
      confirmButton = { TextButton({ BackupOps.restore(file); pending = null; Ui.show("Restored ${file.transactions.size} transactions") }) { Text("Restore", color = C.expense) } },
      dismissButton = { TextButton({ pending = null }) { Text("Cancel") } })
  }
  if (settingPassword) PasswordDialog("Backup password", "New backups are encrypted with it (AES-256). Keep it safe: without it a backup can't be opened, on any phone.",
    onDismiss = { settingPassword = false }) { pw -> BackupPassword.set(ctx, pw); protected = true; settingPassword = false; Ui.show("Backups are now encrypted") }
  locked?.let { text ->
    PasswordDialog("Enter the backup password", "This backup is encrypted.", onDismiss = { locked = null }) { pw ->
      runCatching { BackupOps.open(ctx, text, pw) }.onSuccess { pending = it; locked = null }.onFailure { Ui.show(it.message ?: "Wrong password") }
    }
  }
  error?.let { AlertDialog({ error = null }, confirmButton = { TextButton({ error = null }) { Text("OK") } }, title = { Text("Couldn't do that") }, text = { Text(it) }) }
}

@Composable fun OnboardingScreen() {
  val ctx = LocalContext.current
  var name by remember { mutableStateOf("Bank account") }
  var balance by remember { mutableStateOf("") }
  var lockedBackup by remember { mutableStateOf<String?>(null) }
  val importer = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
    uri ?: return@rememberLauncherForActivityResult
    val text = runCatching { ctx.contentResolver.openInputStream(uri)!!.bufferedReader().readText() }.getOrNull() ?: return@rememberLauncherForActivityResult
    runCatching { BackupOps.restore(BackupOps.open(ctx, text)) }
      .onFailure { if (it is BackupOps.NeedsPassword) lockedBackup = text else Ui.show("Not a Paisa Pulse backup") }
  }
  lockedBackup?.let { text ->
    PasswordDialog("Enter the backup password", "This backup is encrypted.", onDismiss = { lockedBackup = null }) { pw ->
      runCatching { BackupOps.restore(BackupOps.open(ctx, text, pw)) }.onSuccess { BackupPassword.set(ctx, pw); lockedBackup = null }
        .onFailure { Ui.show(it.message ?: "Wrong password") }
    }
  }
  PScreen("", large = false, bottomInset = 40.dp) {
    item {
      Column(Modifier.padding(24.dp)) {
        CategoryBadge("indianrupeesign.circle.fill", "#5E5CE6", 64.dp)
        Text("Paisa Pulse", style = T.largeTitle, color = C.label, modifier = Modifier.padding(top = 12.dp))
        Text("Track every rupee in two taps. No account, no ads, nothing leaves your phone.", style = T.body, color = C.secondary)
      }
    }
    group("Your main account") { FieldRow(name, { name = it }, "Name, e.g. Axis Salary"); Divider(); FieldRow(balance, { balance = it }, "Balance today", number = true) }
    group(footer = "Pick your salary day if you think of months from payday to payday.") {
      PickerRow("Month starts on", (1..28).map { it to ordinal(it) }, Prefs.monthStartDay) { Prefs.set("monthStartDay", it) }
    }
    group {
      PRow("Get Started", titleColor = C.accent, onClick = {
        Store.update { it.copy(accounts = it.accounts + Account(name = name.ifBlank { "Bank account" }, openingBalance = Money.parse(balance) ?: 0) +
          Account(name = "Cash", type = "cash", color = "#34C759", icon = "banknote.fill", sortOrder = 1)) }
        Prefs.set("onboarded", true)
      })
      Divider(); PRow("Restore from a Backup", titleColor = C.accent, onClick = { importer.launch(arrayOf("application/json", "*/*")) })
    }
  }
}


/** Menu picker whose options show their real colour (accent colours, app icons). */
@Composable fun ColorPickerRow(title: String, options: List<Triple<String, String, String>>, selected: String, leading: @Composable () -> Unit, onSelect: (String) -> Unit) {
  var open by remember { mutableStateOf(false) }
  Box {
    PRow(title, leading = leading, onClick = { open = true }) {
      Box(Modifier.size(14.dp).background(hex(options.firstOrNull { it.first == selected }?.third ?: "#8E8E93"), androidx.compose.foundation.shape.CircleShape))
      Spacer(Modifier.width(6.dp))
      Text(options.firstOrNull { it.first == selected }?.second ?: "", style = T.body, color = C.accent)
      Icon(Sym.of("chevron.up.chevron.down"), null, tint = C.accent, modifier = Modifier.padding(start = 2.dp).size(16.dp))
    }
    DropdownMenu(open, { open = false }, modifier = Modifier.background(C.card), offset = androidx.compose.ui.unit.DpOffset(200.dp, 0.dp)) {
      options.forEach { (k, name, color) ->
        DropdownMenuItem({ Text(name, style = T.body) }, { onSelect(k); open = false },
          leadingIcon = { Box(Modifier.size(20.dp).background(hex(color), androidx.compose.foundation.shape.CircleShape)) },
          trailingIcon = { if (k == selected) Icon(Sym.of("checkmark"), null, tint = C.accent) })
      }
    }
  }
}

/** Alternate launcher icons via activity-aliases (same set as the iPhone app). */
object AppIcons {
  val all = listOf(Triple("Default", "Default", "#5E5CE6"), Triple("Midnight", "Midnight", "#1C1C3A"), Triple("Saffron", "Saffron", "#FF9933"),
    Triple("Mint", "Mint", "#34C7A0"), Triple("Mono", "Mono", "#8E8E93"), Triple("Ocean", "Ocean", "#1D4ED8"), Triple("Rose", "Rose", "#BE185D"),
    Triple("Forest", "Forest", "#166534"), Triple("Gold", "Gold", "#B45309"), Triple("Sunset", "Sunset", "#DB2777"), Triple("Graphite", "Graphite", "#111827"))
  /** Preview picture of an icon (drawable-nodpi/icon_preview_*.png). */
  fun preview(key: String): Int = when (key) {
    "Midnight" -> com.paisapulse.app.R.drawable.icon_preview_midnight; "Saffron" -> com.paisapulse.app.R.drawable.icon_preview_saffron
    "Mint" -> com.paisapulse.app.R.drawable.icon_preview_mint; "Mono" -> com.paisapulse.app.R.drawable.icon_preview_mono
    "Ocean" -> com.paisapulse.app.R.drawable.icon_preview_ocean; "Rose" -> com.paisapulse.app.R.drawable.icon_preview_rose
    "Forest" -> com.paisapulse.app.R.drawable.icon_preview_forest; "Gold" -> com.paisapulse.app.R.drawable.icon_preview_gold
    "Sunset" -> com.paisapulse.app.R.drawable.icon_preview_sunset; "Graphite" -> com.paisapulse.app.R.drawable.icon_preview_graphite
    else -> com.paisapulse.app.R.drawable.icon_preview_default
  }
  fun current(ctx: android.content.Context): String = all.firstOrNull { (k, _, _) ->
    ctx.packageManager.getComponentEnabledSetting(android.content.ComponentName(ctx, "com.paisapulse.app.Icon$k")) == android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_ENABLED
  }?.first ?: "Default"
  fun set(ctx: android.content.Context, key: String) {
    all.forEach { (k, _, _) ->
      ctx.packageManager.setComponentEnabledSetting(android.content.ComponentName(ctx, "com.paisapulse.app.Icon$k"),
        if (k == key) android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_ENABLED else android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
        android.content.pm.PackageManager.DONT_KILL_APP)
    }
    Ui.show("Icon changes in a few seconds")
  }
}

@Composable fun PasswordDialog(title: String, message: String, onDismiss: () -> Unit, onSave: (String) -> Unit) {
  var t by remember { mutableStateOf("") }
  AlertDialog(onDismissRequest = onDismiss, containerColor = C.card, title = { Text(title, style = T.headline, color = C.label) },
    text = {
      Column {
        Text(message, style = T.footnote, color = C.secondary)
        Spacer(Modifier.height(10.dp))
        OutlinedTextField(t, { t = it }, singleLine = true, placeholder = { Text("Password") },
          visualTransformation = androidx.compose.ui.text.input.PasswordVisualTransformation(),
          keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Password))
      }
    },
    confirmButton = { TextButton({ if (t.isNotEmpty()) onSave(t) }) { Text("OK", color = C.accent, style = T.headline) } },
    dismissButton = { TextButton(onDismiss) { Text("Cancel", color = C.accent, style = T.body) } })
}
