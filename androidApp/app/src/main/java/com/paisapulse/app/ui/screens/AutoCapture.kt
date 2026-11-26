package com.paisapulse.app.ui.screens

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.paisapulse.app.data.Prefs
import com.paisapulse.app.ui.*
import com.paisapulse.app.work.AlertQueue

/** Auto-capture: bank SMS and payment notifications → drafts on Home to confirm. Read on this phone only. */
@Composable fun AutoCaptureScreen() {
  val ctx = LocalContext.current
  var listener by remember { mutableStateOf(AlertQueue.hasNotificationAccess(ctx)) }
  var sms by remember { mutableStateOf(ContextCompat.checkSelfPermission(ctx, Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED) }
  val waiting by AlertQueue.count.collectAsState()
  LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { listener = AlertQueue.hasNotificationAccess(ctx); AlertQueue.refresh(ctx) }
  val askSms = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { sms = it }
  val askNotify = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {}
  var explain by remember { mutableStateOf<String?>(null) }
  if (explain == "sms") DisclosureDialog("Read bank SMS",
    "Paisa Pulse reads incoming SMS to find bank debit and credit messages and turn them into drafts you confirm. Other messages are ignored, OTPs included, and nothing is uploaded: it all stays on this phone.",
    onAllow = { askSms.launch(Manifest.permission.RECEIVE_SMS) }, onDismiss = { explain = null })
  if (explain == "notifications") DisclosureDialog("Read payment notifications",
    "Paisa Pulse looks at notifications from your messages, bank and UPI apps for debit and credit alerts and turns them into drafts you confirm. Everything else is ignored and nothing is uploaded: it all stays on this phone.",
    onAllow = { AlertQueue.openNotificationAccess(ctx) }, onDismiss = { explain = null })

  PScreen("Auto-capture", back = true) {
    group(footer = "Each bank message becomes a draft with the amount, account and payee filled in. Nothing is added until you confirm it.") {
      ToggleRow("Auto-capture", Prefs.autoCapture, leading = { Badge("message.badge.filled.fill", "#34C759") }) { on ->
        Prefs.set("autoCapture", on)
        if (on && android.os.Build.VERSION.SDK_INT >= 33) askNotify.launch(Manifest.permission.POST_NOTIFICATIONS)
        if (on && !listener && !sms) explain = "notifications"
      }
      Divider(56.dp)
      PRow(if (waiting == 0) "No messages waiting" else "Review $waiting message${if (waiting == 1) "" else "s"}",
        titleColor = if (waiting == 0) C.secondary else C.accent, leading = { Badge("tray", "#5E5CE6") }, chevron = waiting > 0,
        onClick = if (waiting > 0) ({ Ui.push(com.paisapulse.app.ui.Route.Capture("alerts")) }) else null)
    }
    if (Prefs.autoCapture) group("Read from", footer = if (com.paisapulse.app.BuildConfig.STORE_BUILD) "Notifications from your messages, bank and UPI apps (GPay, PhonePe, Paytm)." else "Use either or both. Notifications also catch bank apps, GPay, PhonePe and Paytm; SMS works even when your messages app is muted.") {
      PRow("Notifications", value = if (listener) "Allowed" else "Allow", valueColor = if (listener) C.income else C.accent,
        leading = { Badge("bell.badge", "#FF9500") }, chevron = true, onClick = { if (listener) AlertQueue.openNotificationAccess(ctx) else explain = "notifications" })
      // The Google Play build has no SMS permission (Play restricts it); notifications cover bank alerts there.
      if (!com.paisapulse.app.BuildConfig.STORE_BUILD) {
        Divider(56.dp)
        PRow("Bank SMS", value = if (sms) "Allowed" else "Allow", valueColor = if (sms) C.income else C.accent,
          leading = { Badge("message.badge", "#007AFF") }, chevron = !sms, onClick = { if (!sms) explain = "sms" })
      }
    }
    item {
      Text("Messages are read on this phone and never uploaded. OTPs, payment requests and due-date reminders are ignored.",
        style = T.footnote, color = C.secondary, modifier = Modifier.padding(horizontal = 32.dp, vertical = 8.dp))
    }
  }
}
