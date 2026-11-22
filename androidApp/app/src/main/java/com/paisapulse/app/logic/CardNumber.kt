package com.paisapulse.app.logic

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.net.URL

/** Card details from scanned text (mirrors CardNumber.swift). Only network, last 4, expiry and name are kept. */
object CardNumber {
  data class Scan(val network: String, val last4: String, val month: Int?, val year: Int?, val name: String?)

  fun luhn(d: String): Boolean {
    var sum = 0
    d.reversed().forEachIndexed { i, ch -> var v = ch.digitToIntOrNull() ?: return false; if (i % 2 == 1) { v *= 2; if (v > 9) v -= 9 }; sum += v }
    return sum % 10 == 0
  }

  fun network(d: String): String {
    fun p(n: Int) = d.take(n).toIntOrNull() ?: -1
    return when {
      d.startsWith("4") -> "visa"
      d.startsWith("34") || d.startsWith("37") -> "amex"
      p(2) in 51..55 || p(4) in 2221..2720 -> "mastercard"
      p(2) in listOf(60, 65, 81, 82) || p(3) == 508 || p(3) == 353 || p(3) == 356 -> "rupay"
      d.startsWith("36") || d.startsWith("38") || p(3) in 300..305 -> "diners"
      d.startsWith("6011") || p(3) in 644..649 -> "discover"
      else -> "other"
    }
  }

  fun networkName(n: String) = when (n) { "visa" -> "Visa"; "mastercard" -> "Mastercard"; "rupay" -> "RuPay"; "amex" -> "Amex"; "diners" -> "Diners"; "discover" -> "Discover"; else -> "Card" }
  val networks = listOf("visa", "mastercard", "rupay", "amex", "diners", "discover", "other")

  private val skip = setOf("VISA", "RUPAY", "MASTERCARD", "DEBIT", "CREDIT", "PLATINUM", "PLATINUM DEBIT", "SIGNATURE", "VALID THRU", "VALID FROM")

  fun parse(lines: List<String>): Scan? {
    var found: String? = null
    for (line in lines) {
      val digits = line.filter { it.isDigit() }
      val groups = line.split(' ', '-').filter { it.isNotBlank() }
      if (digits.length in 13..19 && (groups.size >= 3 || digits.length == line.count { !it.isWhitespace() }) && luhn(digits)) { found = digits; break }
    }
    if (found == null) {
      val all = lines.joinToString(" ").filter { it.isDigit() }
      outer@ for (len in listOf(16, 15, 19, 14, 13)) {
        if (all.length < len) continue
        for (start in 0..all.length - len) { val s = all.substring(start, start + len); if (luhn(s) && network(s) != "other") { found = s; break@outer } }
      }
    }
    val number = found ?: return null
    val text = lines.joinToString(" ")
    val m = Regex("""(0[1-9]|1[0-2])\s?/\s?(\d{2,4})""").find(text)
    val month = m?.groupValues?.get(1)?.toInt()
    val year = m?.groupValues?.get(2)?.toInt()?.let { if (it < 100) 2000 + it else it }
    val name = lines.map { it.trim() }.firstOrNull { t -> t.length in 5..26 && t == t.uppercase() && t.all { it.isLetter() || it == ' ' || it == '.' } && t !in skip }
    return Scan(network(number), number.takeLast(4), month, year, name)
  }
}

/** Foreign currency (mirrors Currency in CardNumber.swift): open.er-api.com, cached 12 h, offline from cache, or a typed rate. */
object Currency {
  data class C(val code: String, val name: String, val symbol: String)
  val common = listOf(C("INR", "Indian Rupee", "₹"), C("USD", "US Dollar", "$"), C("EUR", "Euro", "€"), C("GBP", "British Pound", "£"),
    C("AED", "UAE Dirham", "AED"), C("SGD", "Singapore Dollar", "S$"), C("JPY", "Japanese Yen", "¥"), C("AUD", "Australian Dollar", "A$"),
    C("CAD", "Canadian Dollar", "C$"), C("CHF", "Swiss Franc", "CHF"), C("THB", "Thai Baht", "฿"), C("MYR", "Malaysian Ringgit", "RM"),
    C("SAR", "Saudi Riyal", "SAR"), C("CNY", "Chinese Yuan", "CN¥"), C("HKD", "Hong Kong Dollar", "HK$"), C("NZD", "NZ Dollar", "NZ$"),
    C("LKR", "Sri Lankan Rupee", "Rs"), C("NPR", "Nepalese Rupee", "Rs"), C("BDT", "Bangladeshi Taka", "৳"), C("IDR", "Indonesian Rupiah", "Rp"))
  fun symbol(code: String) = common.firstOrNull { it.code == code }?.symbol ?: code

  @Serializable data class Rates(val at: Long, val inrPer: Map<String, Double>)
  const val MAX_AGE = 12 * 3_600_000L

  fun cached(ctx: Context): Rates? = ctx.getSharedPreferences("paisa", Context.MODE_PRIVATE).getString("fx.rates", null)
    ?.let { runCatching { Json.decodeFromString(Rates.serializer(), it) }.getOrNull() }

  suspend fun rates(ctx: Context, force: Boolean = false): Rates? = withContext(Dispatchers.IO) {
    val c = cached(ctx)
    if (!force && c != null && System.currentTimeMillis() - c.at < MAX_AGE) return@withContext c
    runCatching {
      val o = Json.parseToJsonElement(URL("https://open.er-api.com/v6/latest/INR").readText()).jsonObject
      val r = Rates(System.currentTimeMillis(), o["rates"]!!.jsonObject.mapValues { 1 / it.value.jsonPrimitive.double })
      ctx.getSharedPreferences("paisa", Context.MODE_PRIVATE).edit().putString("fx.rates", Json.encodeToString(Rates.serializer(), r)).apply()
      r
    }.getOrDefault(c)
  }

  fun toPaise(minor: Long, rate: Double) = Math.round(minor * rate)
}
