package com.paisapulse.app.work

import android.app.Notification
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.provider.Telephony
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.paisapulse.app.MainActivity
import com.paisapulse.app.R
import com.paisapulse.app.logic.BankAlerts
import com.paisapulse.app.logic.PendingAlert
import com.paisapulse.app.logic.Money
import kotlinx.coroutines.flow.MutableStateFlow
import org.json.JSONArray
import org.json.JSONObject

/**
 * Auto-capture: bank SMS and payment-app notifications become drafts to confirm (Home › "N to review").
 * Only messages that look like a debit or credit are kept, on this phone; OTPs, requests and due reminders are skipped.
 */
object AlertQueue {
  private const val CHANNEL = "paisa-alerts"
  val count = MutableStateFlow(0)
  private fun sp(ctx: Context) = ctx.getSharedPreferences("paisa-alerts", Context.MODE_PRIVATE)

  fun all(ctx: Context): List<PendingAlert> = runCatching {
    val a = JSONArray(sp(ctx).getString("queue", "[]"))
    (0 until a.length()).map { a.getJSONObject(it) }.map { PendingAlert(it.getString("text"), it.optString("sender").ifEmpty { null }, it.getLong("at")) }
  }.getOrDefault(emptyList())

  fun save(ctx: Context, list: List<PendingAlert>) {
    val a = JSONArray(); list.takeLast(200).forEach { a.put(JSONObject().put("text", it.text).put("sender", it.sender ?: "").put("at", it.receivedAt)) }
    sp(ctx).edit().putString("queue", a.toString()).apply()
    count.value = list.size
  }

  fun refresh(ctx: Context) { count.value = all(ctx).size }

  /** Keeps a message if it reads like a payment, and says so in a notification. */
  fun offer(ctx: Context, text: String, sender: String?, at: Long = System.currentTimeMillis()) {
    val on = ctx.getSharedPreferences("paisa", Context.MODE_PRIVATE).getBoolean("autoCapture", false)
    if (!on || !BankAlerts.isBankAlert(text)) return
    val list = all(ctx)
    val amt = BankAlerts.amount(text) ?: return
    val key = BankAlerts.key(text, amt)
    // The same alert often arrives twice (the SMS and the bank app's notification).
    if (list.any { it.text == text || BankAlerts.key(it.text, BankAlerts.amount(it.text) ?: 0) == key }) return
    save(ctx, list + PendingAlert(text, sender, at))
    notifyNew(ctx, amt, BankAlerts.payee(text))
  }

  private fun notifyNew(ctx: Context, amount: Long, payee: String?) {
    val nm = NotificationManagerCompat.from(ctx)
    if (!nm.areNotificationsEnabled()) return
    nm.createNotificationChannel(androidx.core.app.NotificationChannelCompat.Builder(CHANNEL, NotificationManagerCompat.IMPORTANCE_DEFAULT).setName("Payments to review").build())
    val open = PendingIntent.getActivity(ctx, 7, Intent(Intent.ACTION_VIEW, Uri.parse("paisapulse://capture?mode=alerts"), ctx, MainActivity::class.java),
      PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    val n = NotificationCompat.Builder(ctx, CHANNEL).setSmallIcon(R.mipmap.ic_launcher)
      .setContentTitle("${Money.format(amount)}${payee?.let { " · $it" } ?: ""}").setContentText("Tap to add it to Paisa Pulse")
      .setContentIntent(open).setAutoCancel(true).build()
    runCatching { nm.notify(7001, n) }
  }

  fun hasNotificationAccess(ctx: Context): Boolean =
    NotificationManagerCompat.getEnabledListenerPackages(ctx).contains(ctx.packageName)

  fun openNotificationAccess(ctx: Context) {
    val i = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    if (android.os.Build.VERSION.SDK_INT >= 30) {
      runCatching {
        ctx.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
          .putExtra(Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME, ComponentName(ctx, AlertListener::class.java).flattenToString()))
      }.onFailure { ctx.startActivity(i) }
    } else ctx.startActivity(i)
  }
}

/** Reads bank and payment notifications (SMS apps, bank apps, GPay, PhonePe…). Ignores Paisa Pulse's own. */
class AlertListener : NotificationListenerService() {
  override fun onNotificationPosted(sbn: StatusBarNotification) {
    if (sbn.packageName == packageName) return
    val e = sbn.notification.extras
    val title = e.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
    val body = (e.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: e.getCharSequence(Notification.EXTRA_TEXT))?.toString().orEmpty()
    if (body.isBlank()) return
    AlertQueue.offer(applicationContext, body, title.ifBlank { sbn.packageName }, sbn.postTime)
  }
}

/** Incoming SMS (with the SMS permission): works even when the messages app's notifications are muted. */
class SmsAlertReceiver : BroadcastReceiver() {
  override fun onReceive(ctx: Context, intent: Intent) {
    if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
    val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
    val text = parts.joinToString("") { it.messageBody ?: "" }
    AlertQueue.offer(ctx.applicationContext, text, parts.firstOrNull()?.originatingAddress, parts.firstOrNull()?.timestampMillis ?: System.currentTimeMillis())
  }
}
