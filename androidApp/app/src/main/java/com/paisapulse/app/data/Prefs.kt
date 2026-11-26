package com.paisapulse.app.data

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/** Preferences with Compose-observable state. Keys match the iPhone app's PrefKey (and backup settings). */
object Prefs {
  private lateinit var sp: SharedPreferences
  var onboarded by mutableStateOf(false); private set
  var theme by mutableStateOf("system"); private set
  var accent by mutableStateOf("indigo"); private set
  var monthStartDay by mutableStateOf(1); private set
  var weekStartDay by mutableStateOf(2); private set
  var hideAmounts by mutableStateOf(false); private set
  var appLock by mutableStateOf(false); private set
  var lastAccountId by mutableStateOf(""); private set
  var notifyBudgets by mutableStateOf(false); private set
  var notifyBills by mutableStateOf(false); private set
  var notifyWeekly by mutableStateOf(false); private set
  var autoBackup by mutableStateOf(true); private set
  var lastBackupAt by mutableStateOf(0L); private set
  var merchantLogos by mutableStateOf(false); private set
  var myUpiId by mutableStateOf(""); private set
  var myName by mutableStateOf(""); private set
  var autoCleanup by mutableStateOf("off"); private set
  var autoCleanupMonths by mutableStateOf(24); private set
  var lastCleanupAt by mutableStateOf(0L); private set
  var homeOrder by mutableStateOf(""); private set
  var homeHidden by mutableStateOf(""); private set
  /** Main currency code (all stored amounts are in it). */
  var baseCurrency by mutableStateOf("INR"); private set
  var converterCurrencies by mutableStateOf("USD,EUR,GBP,AED"); private set
  /** Hex colour used when accent == "custom". */
  var customAccent by mutableStateOf("#5E5CE6"); private set
  /** Turn bank SMS / payment notifications into drafts to review. */
  var autoCapture by mutableStateOf(false); private set

  fun init(ctx: Context) {
    sp = ctx.getSharedPreferences("paisa", Context.MODE_PRIVATE)
    onboarded = sp.getBoolean("onboarded", false); theme = sp.getString("theme", "system")!!
    accent = sp.getString("accent", "indigo")!!; monthStartDay = sp.getInt("monthStartDay", 1)
    weekStartDay = sp.getInt("weekStartDay", 2); hideAmounts = sp.getBoolean("hideAmounts", false)
    appLock = sp.getBoolean("appLock", false); lastAccountId = sp.getString("lastAccountId", "")!!
    notifyBudgets = sp.getBoolean("notifyBudgets", false); notifyBills = sp.getBoolean("notifyBills", false)
    notifyWeekly = sp.getBoolean("notifyWeekly", false); autoBackup = sp.getBoolean("autoBackup", true)
    lastBackupAt = sp.getLong("lastBackupAt", 0L); merchantLogos = sp.getBoolean("merchantLogos", false)
    myUpiId = sp.getString("myUpiId", "")!!; myName = sp.getString("myName", "")!!
    autoCleanup = sp.getString("autoCleanup", "off")!!; autoCleanupMonths = sp.getInt("autoCleanupMonths", 24); lastCleanupAt = sp.getLong("lastCleanupAt", 0L)
    homeOrder = sp.getString("homeOrder", "")!!; homeHidden = sp.getString("homeHidden", "")!!
    baseCurrency = sp.getString("baseCurrency", "INR")!!; com.paisapulse.app.logic.Money.base = baseCurrency
    converterCurrencies = sp.getString("converterCurrencies", "USD,EUR,GBP,AED")!!; customAccent = sp.getString("customAccent", "#5E5CE6")!!
    autoCapture = sp.getBoolean("autoCapture", false)
  }

  fun set(key: String, v: Any) {
    sp.edit().apply {
      when (v) { is Boolean -> putBoolean(key, v); is Int -> putInt(key, v); is Long -> putLong(key, v); else -> putString(key, v.toString()) }
    }.apply()
    when (key) {
      "onboarded" -> onboarded = v as Boolean; "theme" -> theme = v as String; "accent" -> accent = v as String
      "monthStartDay" -> monthStartDay = v as Int; "weekStartDay" -> weekStartDay = v as Int
      "hideAmounts" -> hideAmounts = v as Boolean; "appLock" -> appLock = v as Boolean
      "lastAccountId" -> lastAccountId = v as String; "notifyBudgets" -> notifyBudgets = v as Boolean
      "notifyBills" -> notifyBills = v as Boolean; "notifyWeekly" -> notifyWeekly = v as Boolean
      "autoBackup" -> autoBackup = v as Boolean; "lastBackupAt" -> lastBackupAt = v as Long
      "merchantLogos" -> merchantLogos = v as Boolean
      "myUpiId" -> myUpiId = v as String; "myName" -> myName = v as String
      "autoCleanup" -> autoCleanup = v as String; "autoCleanupMonths" -> autoCleanupMonths = v as Int; "lastCleanupAt" -> lastCleanupAt = v as Long
      "homeOrder" -> homeOrder = v as String; "homeHidden" -> homeHidden = v as String
      "baseCurrency" -> { baseCurrency = v as String; com.paisapulse.app.logic.Money.base = v }
      "converterCurrencies" -> converterCurrencies = v as String; "customAccent" -> customAccent = v as String
      "autoCapture" -> autoCapture = v as Boolean
    }
  }

  /** Settings carried in backups (same keys and JSON-encoded values as the iPhone app). */
  fun toSettings(): List<Setting> = listOf(
    Setting("onboarded", onboarded.toString()), Setting("theme", "\"$theme\""), Setting("accent", "\"$accent\""),
    Setting("monthStartDay", monthStartDay.toString()), Setting("weekStartDay", weekStartDay.toString()),
    Setting("hideAmounts", hideAmounts.toString()), Setting("merchantLogos", merchantLogos.toString()),
    Setting("myUpiId", "\"$myUpiId\""), Setting("myName", "\"$myName\""), Setting("autoCleanup", "\"$autoCleanup\""),
    Setting("autoCleanupMonths", autoCleanupMonths.toString()), Setting("baseCurrency", "\"$baseCurrency\""),
    Setting("converterCurrencies", "\"$converterCurrencies\""), Setting("customAccent", "\"$customAccent\""),
  )

  fun applySettings(list: List<Setting>) {
    for (s in list) {
      val v = s.value.trim().removeSurrounding("\"")
      when (s.key) {
        "theme", "accent", "myUpiId", "myName", "autoCleanup", "baseCurrency", "converterCurrencies", "customAccent" -> set(s.key, v)
        "autoCleanupMonths" -> v.toIntOrNull()?.let { set(s.key, it) }
        "monthStartDay", "weekStartDay" -> v.toIntOrNull()?.let { set(s.key, it) }
        "hideAmounts", "merchantLogos" -> v.toBooleanStrictOrNull()?.let { set(s.key, it) }
      }
    }
    set("onboarded", true)
  }
}
