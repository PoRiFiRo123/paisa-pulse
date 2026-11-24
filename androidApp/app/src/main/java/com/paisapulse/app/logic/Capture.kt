package com.paisapulse.app.logic

import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZonedDateTime

// Screenshot and voice capture, ported from the RN app (src/features/capture). The screenshot parser is the
// same as iOS Capture.swift; voice is Android-only.

/** A transaction read from a screenshot or speech, waiting for the user to confirm it. */
data class CaptureDraft(
  val key: String, val type: String, val amount: Long, val accountId: String?, val toAccountId: String?, val categoryId: String?,
  val payee: String?, val note: String?, val occurredAt: Long, val source: String, val include: Boolean, val warning: String? = null,
)

data class CaptureAccount(val id: String, val name: String, val type: String, val institution: String?, val last4: String?)
data class CaptureCategory(val id: String, val name: String, val kind: String, val parentId: String?)
data class CaptureContext(
  val accounts: List<CaptureAccount>, val categories: List<CaptureCategory>, val learned: Map<String, String> = emptyMap(),
  val defaultAccountId: String? = null, val now: Long = System.currentTimeMillis(),
)

object CaptureDrafts {
  private fun ri(p: String) = Regex(p, RegexOption.IGNORE_CASE)
  private val generic = setOf("bank", "card", "credit", "debit", "account", "acct", "savings", "saving", "current", "salary", "my", "the", "of", "ac", "a/c")

  private fun phrases(a: CaptureAccount): List<String> {
    val p = LinkedHashSet<String>()
    val name = a.name.lowercase().trim()
    p.add(name)
    name.split(Regex("\\s+")).filter { it.length >= 3 && it !in generic }.forEach { p.add(it) }
    a.institution?.let { inst -> val i = inst.lowercase(); p.add(i); i.split(Regex("\\s+")).filter { it.length >= 3 && it !in generic }.forEach { p.add(it) } }
    val both = "$name ${a.institution ?: ""}".lowercase()
    if (Regex("baroda|\\bbob\\b").containsMatchIn(both)) p.addAll(listOf("bob", "baroda", "bank of baroda"))
    if (Regex("\\bsbi\\b|state bank").containsMatchIn(both)) p.addAll(listOf("sbi", "state bank"))
    a.last4?.let { p.add(it) }
    return p.sortedByDescending { it.length }
  }

  private const val PREP = "(?:(?:from|on|using|with|via|by|through|in|thru|frm)\\s+)?(?:(?:my|the)\\s+)?"
  private const val TAIL = "(?:\\s+(?:bank|account|acct|a/c|card|credit card|debit card|wallet))?"

  /** An account named in the text, with the matched phrase (to strip it). */
  fun findAccount(text: String, accounts: List<CaptureAccount>): Pair<CaptureAccount, String>? {
    val lower = text.lowercase()
    var best: Triple<CaptureAccount, String, Int>? = null
    for (a in accounts) for (p in phrases(a)) {
      val m = Regex("(?:^|\\s)($PREP${Regex.escape(p)}$TAIL)(?=$|[\\s,.;!?])").find(lower)
      if (m != null && (best == null || p.length > best.third)) best = Triple(a, m.groupValues[1], p.length)
    }
    if (best != null) return best.first to best.second
    for ((re, type) in listOf(Regex("(?:^|\\s)(${PREP}cash)(?=$|[\\s,.;!?])") to "cash", Regex("(?:^|\\s)(${PREP}(?:credit\\s+)?card)(?=$|[\\s,.;!?])") to "card",
      Regex("(?:^|\\s)(${PREP}wallet)(?=$|[\\s,.;!?])") to "wallet")) {
      val m = re.find(lower); val ofType = accounts.filter { it.type == type }
      if (m != null && ofType.size == 1) return ofType[0] to m.groupValues[1]
    }
    return null
  }

  private val spoken = listOf(
    ri("\\b(lunch|dinner|breakfast|brunch|snacks?|chai|tea|coffee|juice|food|meal|biryani|pizza|burger|dosa|idli|samosa|momos?|restaurant|cafe|canteen|tiffin|swiggy|zomato)\\b") to "Food & Dining",
    ri("\\b(groceries|grocery|vegetables?|veggies|sabzi|fruits?|milk|eggs|bread|atta|rice|dal|kirana|ration)\\b") to "Groceries",
    ri("\\b(petrol|diesel|fuel|cng)\\b") to "Fuel",
    ri("\\b(auto|rickshaw|cab|taxi|uber|ola|rapido|metro|bus|train ticket|local train|toll|parking|fastag)\\b") to "Metro/Auto/Cab",
    ri("\\b(rent)\\b") to "Rent",
    ri("\\b(electricity|power bill|light bill)\\b") to "Electricity",
    ri("\\b(recharge|mobile bill|phone bill|wifi|internet|broadband)\\b") to "Mobile/Internet",
    ri("\\b(medicines?|medical|doctor|pharmacy|hospital|clinic|tablets?|chemist)\\b") to "Health",
    ri("\\b(movie|movies|cinema|concert|game|netflix)\\b") to "Entertainment",
    ri("\\b(clothes|shirt|shoes|jeans|dress|kurta|shopping|amazon|flipkart|myntra)\\b") to "Shopping",
    ri("\\b(flight|hotel|trip|travel|holiday)\\b") to "Travel",
    ri("\\b(haircut|salon|spa|gym|parlour)\\b") to "Personal Care",
    ri("\\b(gift|donation|temple|church|mosque|gurudwara)\\b") to "Gifts & Donations",
    ri("\\b(fees|tuition|books?|course)\\b") to "Education",
    ri("\\b(salary|paycheck)\\b") to "Salary",
    ri("\\b(freelance|client|invoice)\\b") to "Freelance",
    ri("\\b(refund|returned)\\b") to "Refund",
    ri("\\b(cashback)\\b") to "Cashback",
    ri("\\b(interest)\\b") to "Interest",
  )

  fun guessCategory(text: String, payee: String?, type: String, ctx: CaptureContext): String? {
    if (type == "transfer") return null
    val kind = if (type == "income") "income" else "expense"
    val ofKind = ctx.categories.filter { it.kind == kind }
    payee?.let { p -> ctx.learned[p.lowercase()]?.let { id -> if (ofKind.any { it.id == id }) return id } }
    fun byName(n: String) = ofKind.firstOrNull { it.name.equals(n, ignoreCase = true) }?.id
    val hay = "${payee ?: ""} $text"
    for (c in ofKind) if (c.name.length >= 3 && Regex("\\b${Regex.escape(c.name.lowercase())}\\b").containsMatchIn(hay.lowercase())) return c.id
    for ((re, n) in spoken) if (re.containsMatchIn(hay) && byName(n) != null) return byName(n)
    return Narrations.suggestCategory(text, payee, kind != "income")?.let(::byName)
  }

  fun displayName(text: String): String {
    Brands.match(text)?.let { return it.name }
    val t = text.trim()
    return if (t.isEmpty()) t else t.substring(0, 1).uppercase() + t.substring(1)
  }

  fun context(db: com.paisapulse.app.data.Db, defaultAccountId: String?, now: Long = System.currentTimeMillis()): CaptureContext {
    val learned = db.liveTxns.filter { it.payee != null && it.categoryId != null }.groupBy { it.payee!!.lowercase() }
      .mapValues { (_, v) -> v.groupingBy { it.categoryId!! }.eachCount().maxByOrNull { it.value }!!.key }
    return CaptureContext(
      db.accounts.filter { it.archivedAt == null }.sortedBy { it.sortOrder }.map { CaptureAccount(it.id, it.name, it.type, it.institution, it.last4) },
      db.categories.filter { it.archivedAt == null }.map { CaptureCategory(it.id, it.name, it.kind, it.parentId) }, learned, defaultAccountId, now)
  }
}

object ScreenshotParser {
  private fun ri(p: String) = Regex(p, RegexOption.IGNORE_CASE)
  private val months = mapOf("jan" to 1, "feb" to 2, "mar" to 3, "apr" to 4, "may" to 5, "jun" to 6, "jul" to 7, "aug" to 8, "sep" to 9, "sept" to 9, "oct" to 10, "nov" to 11, "dec" to 12)

  fun toLines(texts: List<String>) = texts.flatMap { it.split(Regex("\r?\n")) }.map { it.replace(Regex("\\s+"), " ").trim() }.filter { it.isNotEmpty() }

  private val idLine = ri("\\b(utr|upi ref|ref(erence)?\\s*(no|number|id)?|transaction id|txn id|order id|google transaction|upi transaction|rrn)\\b")
  /** Lines with other amounts: balances, rewards, fees and limits (Paytm, PhonePe, bank apps). */
  private val otherAmount = ri("\\b(balance|bal\\b|cashback|reward|coins?|scratch|won|offer|fee|charges?|limit|points?|save|saved|discount)\\b")

  private fun paise(s: String): Long? = s.replace(",", "").toBigDecimalOrNull()?.let { Money.paise(it) }?.takeIf { it > 0 }

  fun findPaidAmount(lines: List<String>): Long? {
    val money = ri("(?:₹|rs\\.?|inr|amount\\s*(?:paid|sent|received)?\\s*:?\\s*₹?)\\s*([\\d,]+(?:\\.\\d{1,2})?)\\b")
    for (line in lines) { if (idLine.containsMatchIn(line) || otherAmount.containsMatchIn(line)) continue; money.find(line)?.let { m -> paise(m.groupValues[1])?.let { return it } } }
    // OCR often reads the ₹ sign as Z, %, ?, a dot or 2 on a line of its own amount ("Z349", "% 1,245.00", "·1,000" from CRED).
    for (line in lines) ri("^[z%?·•*~]\\s?(\\d[\\d,]*(?:\\.\\d{1,2})?)$").find(line)?.let { m -> paise(m.groupValues[1])?.let { return it } }
    for (line in lines) {
      val m = Regex("^([\\d,]{1,9}(?:\\.\\d{2})?)$").find(line) ?: continue
      if (!Regex("^\\d{10,}$").matches(m.groupValues[1].replace(",", ""))) paise(m.groupValues[1])?.let { return it }
    }
    return null
  }

  fun findReceiptDate(lines: List<String>, now: Long): Long? {
    val text = lines.joinToString(" \n ")
    var day: Int? = null; var month: Int? = null; var year: Int? = null
    val a = ri("\\b(\\d{1,2})(?:st|nd|rd|th)?[\\s-]+(jan|feb|mar|apr|may|jun|jul|aug|sept?|oct|nov|dec)[a-z]*[\\s,-]*(\\d{4})?").find(text)
    if (a != null) { day = a.groupValues[1].toInt(); month = months[a.groupValues[2].lowercase()]; year = a.groupValues[3].toIntOrNull() }
    else {
      val b = ri("\\b(jan|feb|mar|apr|may|jun|jul|aug|sept?|oct|nov|dec)[a-z]*\\s+(\\d{1,2}),?\\s*(\\d{4})?").find(text)
      if (b != null) { month = months[b.groupValues[1].lowercase()]; day = b.groupValues[2].toInt(); year = b.groupValues[3].toIntOrNull() }
      else Regex("\\b(\\d{1,2})[/.-](\\d{1,2})[/.-](\\d{2,4})\\b").find(text)?.let { c ->
        day = c.groupValues[1].toInt(); month = c.groupValues[2].toInt(); val y = c.groupValues[3].toInt(); year = if (y < 100) 2000 + y else y
      }
    }
    // "Today, 10:15 AM" / "Yesterday 9:02 pm" (Paytm, PhonePe, Navi, bank apps).
    if (day == null) ri("\\b(today|yesterday)\\b").find(text)?.let { r ->
      val base = Instant.ofEpochMilli(now).atZone(zone).toLocalDate().minusDays(if (r.groupValues[1].lowercase() == "yesterday") 1 else 0)
      day = base.dayOfMonth; month = base.monthValue; year = base.year
    }
    val d = day ?: return null; val m = month ?: return null
    var hours = 12; var minutes = 0
    ri("\\b(\\d{1,2}):(\\d{2})(?::\\d{2})?\\s*(am|pm)?\\b").find(text)?.let { t ->
      hours = t.groupValues[1].toInt() % 24; minutes = t.groupValues[2].toInt()
      val ap = t.groupValues[3].lowercase()
      if (ap == "pm" && hours < 12) hours += 12
      if (ap == "am" && hours == 12) hours = 0
    }
    val thisYear = Instant.ofEpochMilli(now).atZone(zone).year
    fun at(y: Int) = runCatching { LocalDateTime.of(y, m, d, hours, minutes).atZone(zone).toInstant().toEpochMilli() }.getOrNull()
    var result = at(year ?: thisYear) ?: return null
    if (year == null && result > now + 86_400_000) result = at(thisYear - 1) ?: result
    return result
  }

  private val received = ri("\\b(received from|money received|you received|credited to your|received)\\b")
  private val sent = ri("\\b(paid to|paid successfully|payment successful|payment success|money sent|sent to|debited from|you paid|transaction successful|completed|payment of|payment to|sent successfully|transfer successful|transferred|paid|debited|payment done|payment complete|success)\\b")
  private val failed = ri("\\b(failed|declined|unsuccessful|pending|processing|reversed|cancelled|canceled|in progress|awaiting|will be refunded)\\b")
  private val payeeLabel = ri("^(paid to|paid successfully to|money sent to|sent to|sent money to|payment to|transferred to|received from|payment from|money received from|sender( name)?|to|from|beneficiary( name)?|payee( name)?|merchant( name)?|recipient( name)?|receiver( name)?|to account|paying)\\s*:?$")
  private val notAName = ri("(@|\\d{6,}|successful|completed|transaction|upi|banking name|share|split|pay again|view|details|debited|credited|xx|\\*\\*|•|powered by|phonepe|google pay|\\bgpay\\b|paytm|\\bbhim\\b|whatsapp|mobikwik|freecharge|super\\.money|receipt|download|help|support|again|\\?)")

  private fun payeeFrom(lines: List<String>, isReceived: Boolean): Pair<String?, String?> {
    val upi = lines.firstNotNullOfOrNull { ri("\\b[\\w.-]{2,}@[a-z]{2,}\\b").find(it)?.value }
    val want = if (isReceived) ri("^(received from|from|money received from|payment from|sender)\\b") else ri("^(paid to|paid successfully to|money sent to|sent to|sent money to|payment to|transferred to|to|beneficiary|payee|merchant|recipient|receiver|paying)\\b")
    for ((i, line) in lines.withIndex()) {
      if (payeeLabel.matches(line) && want.containsMatchIn(line)) {
        val next = lines.drop(i + 1).take(2).firstOrNull { !notAName.containsMatchIn(it) && ri("[a-z]").containsMatchIn(it) && !it.startsWith("₹") }
        if (next != null) return next to upi
        continue
      }
      val inline = (if (isReceived) ri("^(?:received from|money received from|payment from|from|sender name)\\s*:?\\s+(.+)$") else ri("^(?:paid to|paid successfully to|money sent to|sent to|sent money to|payment to|transferred to|paying|to|beneficiary name|payee name|recipient name|merchant name)\\s*:?\\s+(.+)$")).find(line)
      if (inline != null && !notAName.containsMatchIn(inline.groupValues[1]) && ri("[a-z]").containsMatchIn(inline.groupValues[1]))
        return inline.groupValues[1].replace(Regex("\\s*\\(.*\\)\\s*$"), "") to upi
    }
    if (!isReceived) {
      // "Nishit Kirani paid" / "You paid" on one line, the payee on the next (CRED receipts).
      for ((i, line) in lines.withIndex()) if (ri("\\bpaid$").containsMatchIn(line)) lines.drop(i + 1).take(2).firstOrNull { nameLike(it) }?.let { return it to upi }
      // No label at all: the name just above the amount (CRED, bank apps).
      val at = lines.indexOfFirst { amountLine.containsMatchIn(it) }
      if (at > 0) lines.subList(maxOf(0, at - 3), at).reversed().firstOrNull { nameLike(it) }?.let { return it to upi }
    }
    return null to upi
  }

  private val amountLine = ri("^(?:₹|rs\\.?|inr|[z%?·•*~])?\\s?\\d[\\d,]*(?:\\.\\d{1,2})?$")
  private fun nameLike(s: String) = ri("^[a-z][a-z .'&-]{2,40}$").matches(s) && !notAName.containsMatchIn(s) && !payeeLabel.matches(s) &&
    !ri("\\b(today|yesterday|payment|paid|bank|account|balance|amount|status|cred)\\b").containsMatchIn(s)

  private fun accountFrom(lines: List<String>, ctx: CaptureContext): CaptureAccount? {
    val own = lines.filter { ri("(debited|credited|from|account|a/c|bank|xx|\\*{2,}|•{2,})").containsMatchIn(it) }
    for (line in own) {
      val last4 = ri("(?:x{2,}|\\*{2,}|•{2,}|\\.{2,}|a/c\\s*(?:no\\.?)?\\s*|ending\\s*(?:in|with)?\\s*)\\s*(\\d{4})\\b").find(line)?.groupValues?.get(1)
      if (last4 != null) ctx.accounts.firstOrNull { it.last4 == last4 }?.let { return it }
    }
    for (line in own) CaptureDrafts.findAccount(line, ctx.accounts)?.let { return it.first }
    return null
  }

  /** One payment screenshot → a draft, or null with no amount. Tested with GPay, PhonePe, Paytm, BHIM, CRED, Amazon Pay,
   *  WhatsApp, Navi, super.money, MobiKwik, Freecharge, Fi/Jupiter-style and bank apps (Axis, BoB, SBI YONO, HDFC, ICICI). */
  fun parse(texts: List<String>, ctx: CaptureContext, key: String = "shot"): CaptureDraft? {
    val lines = toLines(texts)
    val amount = findPaidAmount(lines) ?: return null
    val text = lines.joinToString("\n")
    val isReceived = received.containsMatchIn(text) && !ri("\\bpaid to\\b|\\bdebited from\\b").containsMatchIn(text)
    val (name, upi) = payeeFrom(lines, isReceived)
    val account = accountFrom(lines, ctx)
    val brand = Brands.match(name) ?: Brands.match(upi)
    val payee = brand?.name ?: name?.let { CaptureDrafts.displayName(Regex("\\b\\w").replace(it.lowercase()) { m -> m.value.uppercase() }) } ?: upi?.substringBefore('@')
    var type = if (isReceived) "income" else "expense"
    var toAccountId: String? = null
    var accountId = account?.id ?: ctx.defaultAccountId ?: ctx.accounts.firstOrNull()?.id
    if (!isReceived && ri("credit card|card bill|cc bill|card payment").containsMatchIn(text)) {
      val cards = ctx.accounts.filter { it.type == "card" }
      val last4s = Regex("(\\d{4})\\b").findAll(text).map { it.groupValues[1] }.toSet()
      val card = cards.firstOrNull { it.last4 != null && it.last4 in last4s } ?: cards.singleOrNull()
      if (card != null) {
        type = "transfer"; toAccountId = card.id
        if (accountId == card.id) accountId = ctx.accounts.firstOrNull { it.type == "bank" }?.id
      }
    }
    val isFailed = failed.containsMatchIn(text) && !ri("\\bsuccess").containsMatchIn(text)
    val warning = when {
      !(sent.containsMatchIn(text) || isReceived) -> "Couldn’t tell if this was a payment. Check the details."
      isFailed -> "This payment may have failed or be pending."
      else -> null
    }
    return CaptureDraft(key, type, amount, accountId, toAccountId, CaptureDrafts.guessCategory("${name ?: ""} ${upi ?: ""}", payee, type, ctx),
      if (type == "transfer") null else payee, if (type == "transfer") "Card bill payment" else null,
      findReceiptDate(lines, ctx.now) ?: ctx.now, lines.take(12).joinToString(" · "), !isFailed, warning)
  }
}

/** Android-only: spoken sentences → drafts ("250 lunch, 80 auto and 40 chai"). */
object VoiceParser {
  private fun ri(p: String) = Regex(p, RegexOption.IGNORE_CASE)
  private const val DAY = 86_400_000L
  private val units = mapOf("zero" to 0, "one" to 1, "a" to 1, "an" to 1, "two" to 2, "three" to 3, "four" to 4, "five" to 5, "six" to 6, "seven" to 7,
    "eight" to 8, "nine" to 9, "ten" to 10, "eleven" to 11, "twelve" to 12, "thirteen" to 13, "fourteen" to 14, "fifteen" to 15, "sixteen" to 16,
    "seventeen" to 17, "eighteen" to 18, "nineteen" to 19)
  private val tens = mapOf("twenty" to 20, "thirty" to 30, "forty" to 40, "fifty" to 50, "sixty" to 60, "seventy" to 70, "eighty" to 80, "ninety" to 90)
  private val scales = mapOf("hundred" to 100.0, "thousand" to 1000.0, "k" to 1000.0, "lakh" to 1e5, "lakhs" to 1e5, "lac" to 1e5, "lacs" to 1e5, "crore" to 1e7, "crores" to 1e7)
  private fun isNumWord(w: String) = w in units || w in tens || w in scales || w == "and" || w == "half"

  /** Splits keeping whitespace tokens, like JS text.split(/(\s+)/). */
  private fun tokens(text: String): List<String> {
    val out = mutableListOf<String>(); var last = 0
    for (m in Regex("\\s+").findAll(text)) { out.add(text.substring(last, m.range.first)); out.add(m.value); last = m.range.last + 1 }
    out.add(text.substring(last)); return out
  }

  private fun fmt(v: Double) = if (v == Math.floor(v)) v.toLong().toString() else v.toString()

  fun wordsToDigits(text: String): String {
    val words = tokens(text)
    val out = StringBuilder(); var i = 0
    fun lw(k: Int) = words.getOrNull(k)?.lowercase()
    while (i < words.size) {
      val w = words[i].lowercase()
      val starts = (w in units && w != "a" && w != "an") || w in tens || ((w == "a" || w == "an") && lw(i + 2) in scales)
      if (!starts) { out.append(words[i]); i++; continue }
      val run = mutableListOf<String>(); var j = i
      while (j < words.size) {
        val t = words[j].lowercase()
        if (Regex("^\\s+$").matches(t)) { j++; continue }
        if (!isNumWord(t) || (t == "and" && !(lw(j + 2) in units || lw(j + 2) in tens))) break
        run.add(t); j++
      }
      var end = j
      while (end > i && Regex("^\\s+$").matches(words[end - 1])) end--
      out.append(fmt(evaluate(run))); i = end
    }
    return out.toString()
  }

  private fun evaluate(run: List<String>): Double {
    val nums = run.filter { it != "and" }
    if (nums.size >= 2 && nums[0] in units && units[nums[0]]!! < 10 && (nums[1] in tens || (nums[1] in units && units[nums[1]]!! >= 10)))
      return units[nums[0]]!! * 100 + evaluate(nums.drop(1))
    var total = 0.0; var current = 0.0
    for (w in nums) when {
      w in units -> current += units[w]!!
      w in tens -> current += tens[w]!!
      w == "half" -> current += 0.5
      w == "hundred" -> current = (if (current == 0.0) 1.0 else current) * 100
      w in scales -> { total += (if (current == 0.0) 1.0 else current) * scales[w]!!; current = 0.0 }
    }
    return total + current
  }

  private val amountRe = ri("(?:₹|rs\\.?|inr)?\\s*(\\d+(?:,\\d{2,3})*(?:\\.\\d+)?)\\s*(k|thousand|hundred|lakhs?|lacs?|crores?|cr)?\\b\\s*(?:rupees?|rs\\.?|bucks|inr|/-)?")

  fun findAmount(text: String): Pair<Long, String>? {
    val m = amountRe.find(text) ?: return null
    val value = m.groupValues[1].replace(",", "").toDouble()
    val unit = m.groupValues[2].lowercase()
    val scale = if (unit.isEmpty()) 1.0 else scales[unit] ?: if (unit == "cr") 1e7 else 1.0
    val paise = Math.round(value * scale * 100)
    if (paise <= 0) return null
    return paise to m.value
  }

  fun splitPhrases(text: String): List<String> {
    val coarse = text.split(ri(",(?!\\d)|;|\n|\\.(?!\\d)|\\b(?:and then|then|also|plus|after that)\\b")).map { it.trim() }.filter { it.isNotEmpty() }
    val out = mutableListOf<String>()
    for (part in coarse) {
      val pieces = part.split(ri("\\band\\b")).map { it.trim() }.filter { it.isNotEmpty() }
      if (pieces.count { findAmount(it) != null } < 2) { out.add(part); continue }
      var buffer = ""
      for (p in pieces) {
        if (findAmount(p) != null && findAmount(buffer) != null) { out.add(buffer.trim()); buffer = p }
        else buffer = if (buffer.isNotEmpty()) "$buffer and $p" else p
      }
      if (buffer.isNotEmpty()) out.add(buffer.trim())
    }
    return out
  }

  private val weekdays = listOf("sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday")

  private fun z(ms: Long): ZonedDateTime = Instant.ofEpochMilli(ms).atZone(zone)
  private fun atHour(ms: Long, h: Int) = z(ms).withHour(h).withMinute(0).withSecond(0).withNano(0).toInstant().toEpochMilli()

  fun findDate(text: String, now: Long): Pair<Long, String>? {
    val lower = text.lowercase()
    Regex("\\b(?:on\\s+)?day before yesterday\\b").find(lower)?.let { return atHour(now - 2 * DAY, 12) to it.value }
    Regex("\\blast night\\b").find(lower)?.let { return atHour(now - DAY, 21) to it.value }
    Regex("\\byesterday(?:\\s+(?:morning|afternoon|evening|night))?\\b").find(lower)?.let { m ->
      val part = m.value.split(Regex("\\s+")).getOrNull(1)
      val hour = mapOf("morning" to 9, "afternoon" to 14, "evening" to 19, "night" to 21)[part]
      return (if (hour == null) now - DAY else atHour(now - DAY, hour)) to m.value
    }
    Regex("\\b(this morning|this afternoon|this evening|tonight|today)\\b").find(lower)?.let { m ->
      val hour = mapOf("this morning" to 9, "this afternoon" to 14, "this evening" to 19, "tonight" to 20)[m.groupValues[1]]
      return (if (hour == null) now else minOf(now, atHour(now, hour))) to m.value
    }
    Regex("\\b(\\d{1,2}|a|one|two|three|four|five|six|seven)\\s+days?\\s+ago\\b").find(lower)?.let { m ->
      val n = m.groupValues[1].toIntOrNull()?.takeIf { it > 0 } ?: units[m.groupValues[1]]?.takeIf { it > 0 } ?: 1
      return atHour(now - n * DAY, 12) to m.value
    }
    Regex("\\b(?:on\\s+|last\\s+)?(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\\b").find(lower)?.let { m ->
      val target = weekdays.indexOf(m.groupValues[1])
      val today = z(now).dayOfWeek.value % 7
      var back = (today - target + 7) % 7
      if (back == 0 && m.value.contains("last")) back = 7
      return (if (back == 0) now else atHour(now - back * DAY, 12)) to m.value
    }
    Regex("\\bon\\s+(?:the\\s+)?(\\d{1,2})(?:st|nd|rd|th)\\b").find(lower)?.let { m ->
      val day = m.groupValues[1].toInt()
      val d = z(now).toLocalDate()
      fun at(ld: LocalDate) = runCatching { ld.withDayOfMonth(day).atTime(12, 0).atZone(zone).toInstant().toEpochMilli() }.getOrNull()
      val res = if (day > d.dayOfMonth) at(d.minusMonths(1)) else at(d)
      return (res ?: now) to m.value
    }
    return null
  }

  private val income = ri("\\b(received|receive|earned|salary|credited|refund(?:ed)?|cashback|income|bonus|stipend|got paid|got back)\\b|\\bgot\\b.*\\bfrom\\b")
  private val cardBill = ri("\\b(?:paid|pay|cleared|clear)\\b.*\\b(?:credit\\s+)?card\\s+bill\\b|\\bcard\\s+(?:bill\\s+)?payment\\b")
  private val transfer = ri("\\b(?:transfer(?:red)?|moved?|sent|shift(?:ed)?|deposited|withdrew|withdrawn)\\b")
  private val filler = ri("\\b(?:i|i've|ive|i have|just|spent|spend|paid|pay|bought|buy|for|on|at|to|the|a|an|my|of|got|gave|give|was|is|it|some|from|today|rupees?|rs|bucks|expense|income|transferred|transfer|moved|sent|received|earned|credited|added|add|log|record)\\b")
  private fun tidy(t: String) = t.replace(Regex("\\s+"), " ").replace(Regex("^[\\s,.\\-–]+|[\\s,.\\-–]+$"), "").trim()
  private fun replaceFirstLiteral(s: String, find: String, with: String) = s.indexOf(find).let { if (it < 0) s else s.substring(0, it) + with + s.substring(it + find.length) }

  fun parse(sentence: String, ctx: CaptureContext): Pair<List<CaptureDraft>, List<String>> {
    val text = wordsToDigits(sentence.replace(Regex("[“”\"]"), ""))
    val drafts = mutableListOf<CaptureDraft>(); val skipped = mutableListOf<String>()
    val phrases = splitPhrases(text)
    val ownDates = phrases.map { p -> findDate(findAmount(p)?.let { replaceFirstLiteral(p, it.second, " ") } ?: p, ctx.now) }
    val closing = ownDates.firstOrNull { it != null }?.first
    var carryDate: Long? = null; var carryAccount: String? = null
    phrases.forEachIndexed { index, phrase ->
      val amount = findAmount(phrase)
      val date = ownDates[index]
      if (date != null) carryDate = date.first
      if (amount == null) { if (phrase.isNotBlank()) skipped.add(phrase.trim()); return@forEachIndexed }
      var rest = replaceFirstLiteral(phrase, amount.second, " ")
      if (date != null) rest = rest.replaceFirst(Regex(Regex.escape(date.second), RegexOption.IGNORE_CASE), " ")
      var type = if (income.containsMatchIn(phrase)) "income" else "expense"
      var accountId: String? = null; var toAccountId: String? = null
      val fromTo = ri("\\bfrom\\s+(.+?)\\s+(?:to|into)\\s+(.+)$").find(rest)
      if (fromTo != null && transfer.containsMatchIn(phrase)) {
        val a = CaptureDrafts.findAccount(fromTo.groupValues[1], ctx.accounts); val b = CaptureDrafts.findAccount(fromTo.groupValues[2], ctx.accounts)
        if (a != null && b != null && a.first.id != b.first.id) { type = "transfer"; accountId = a.first.id; toAccountId = b.first.id; rest = replaceFirstLiteral(rest, fromTo.value, " ") }
      }
      if (type != "transfer" && cardBill.containsMatchIn(phrase)) {
        val cards = ctx.accounts.filter { it.type == "card" }
        val named = CaptureDrafts.findAccount(rest.replace(ri("\\bcard\\s+bill\\b|\\bbill\\b"), " "), ctx.accounts)
        val card = if (named?.first?.type == "card") named.first else cards.singleOrNull()
        val from = if (named != null && named.first.type != "card") named.first
          else ctx.accounts.firstOrNull { it.id == ctx.defaultAccountId && it.type != "card" } ?: ctx.accounts.firstOrNull { it.type == "bank" }
        if (card != null && from != null) { type = "transfer"; accountId = from.id; toAccountId = card.id; rest = " " }
      }
      if (type != "transfer") CaptureDrafts.findAccount(rest, ctx.accounts)?.let { acc ->
        accountId = acc.first.id; carryAccount = acc.first.id
        rest = rest.replaceFirst(Regex("(^|\\s)${Regex.escape(acc.second)}(?=$|\\s|[,.;!?])", RegexOption.IGNORE_CASE), " ")
      }
      var payee: String? = null
      val named = (if (type == "income") ri("\\bfrom\\s+([a-z][\\w&'.-]*(?:\\s+[a-z][\\w&'.-]*){0,2})") else ri("\\b(?:to|at)\\s+([a-z][\\w&'.-]*(?:\\s+[a-z][\\w&'.-]*){0,2})")).find(rest)
      if (named != null) { payee = CaptureDrafts.displayName(named.groupValues[1]); rest = replaceFirstLiteral(rest, named.value, " ") }
      val description = tidy(rest.replace(filler, " "))
      var remainder = description
      val brand = if (payee != null) null else Brands.match(description)
      if (brand != null) { payee = brand.name; remainder = tidy(description.replaceFirst(brand.regex, " ")) }
      if (payee == null && description.isNotEmpty() && type != "transfer") { payee = CaptureDrafts.displayName(description); remainder = "" }
      val note = if (remainder.isNotEmpty() && remainder.lowercase() != payee?.lowercase()) CaptureDrafts.displayName(remainder) else null
      drafts.add(CaptureDraft("voice-$index", type, amount.first, accountId ?: carryAccount ?: ctx.defaultAccountId ?: ctx.accounts.firstOrNull()?.id, toAccountId,
        CaptureDrafts.guessCategory(description, payee, type, ctx), if (type == "transfer") null else payee,
        if (type == "transfer") (if (description.isNotEmpty()) CaptureDrafts.displayName(description) else null) else note,
        carryDate ?: closing ?: ctx.now, phrase.trim(), true))
    }
    return drafts to skipped
  }
}
