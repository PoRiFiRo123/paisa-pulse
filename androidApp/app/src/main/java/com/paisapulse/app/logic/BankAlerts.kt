package com.paisapulse.app.logic

// Bank SMS and payment-app notifications → a draft to confirm. Same rules and tests as iOS BankAlerts.swift.
// Android reads them from notifications / SMS; iPhone gets them from a Shortcuts "Message" automation.

/** A bank alert waiting for review: the raw text and when it arrived. */
data class PendingAlert(val text: String, val sender: String?, val receivedAt: Long)

object BankAlerts {
  private fun ri(p: String) = Regex(p, RegexOption.IGNORE_CASE)

  private val ignore = ri("\\b(otp|one[- ]time password|verification code|will be (auto[- ]?)?debited|is due|due (on|date|by)|minimum (amount )?due|" +
    "has requested|requested (money|rs|inr|₹)|collect request|request of|failed|declined|unsuccessful|reversal|reversed|" +
    "pre-?approved|apply now|offer|cashback of up to|e-?mandate (is )?(created|registered)|statement (is|has been) generated)\\b")
  private val debit = ri("\\b(debited|spent|sent|paid|withdrawn|purchase|deducted|transferred from|txn of|dr\\.?)\\b")
  private val credit = ri("\\b(credited|received|deposited|cr\\.?)\\b")
  private val money = ri("(?:rs\\.?|inr|₹)\\s*([\\d,]+(?:\\.\\d{1,2})?)")
  private val bareAmount = ri("\\b(?:debited|credited|spent|sent|paid)\\s+(?:by|with|for|of)?\\s*([\\d,]+(?:\\.\\d{1,2})?)\\b")
  private val notTheAmount = ri("(avl|avbl|available|total|a/c|acct)?\\.?\\s*(bal|balance|lmt|limit)\\s*:?\\s*$")
  private val last4 = ri("(?:x{2,}|\\*+|\\.{2,}|ending(?:\\s+(?:with|in))?\\s*|a/c\\s*(?:no\\.?)?\\s*[x*]*|acct\\s*[x*]*|card\\s*(?:no\\.?)?\\s*[x*]*)(\\d{3,4})\\b")
  private val ref = ri("(?:ref(?:erence)?(?:\\s*no\\.?)?|rrn|utr|upi(?:\\s*ref)?(?:\\s*no\\.?)?)[\\s:.#-]*(\\d{9,16})")
  private val upiRef = ri("upi/(?:p2[ma]/)?(\\d{9,16})")
  private val vpa = ri("\\b([\\w.-]{2,}@[a-z]{2,})\\b")
  private val cardBill = ri("(payment|amount) of .{0,40}(received|credited) (towards|to|on|for) your .{0,30}credit card|credit card .{0,40}payment .{0,20}(received|credited)")

  private val payeePatterns = listOf(
    ri("info[-:\\s]+(?:upi/(?:p2[ma]/)?\\d+/)?([a-z0-9][a-z0-9 .&'_-]{1,40}?)(?:/|\\s+not you|\\.\\s|\\.$|$)"), // Axis
    ri("trf to\\s+([a-z0-9][a-z0-9 .&'_-]{1,40}?)\\s+(?:ref\\w*|on)\\b"),                                      // SBI
    ri(";\\s*([a-z0-9][a-z0-9 .&'_-]{1,40}?)\\s+credited\\b"),                                             // ICICI
    ri("\\bto[:\\s]+(?:vpa\\s+)?([a-z0-9][a-z0-9 .&'@_-]{1,40}?)\\s+(?:on|ref\\w*|via|upi|from|dt|date)\\b"),   // HDFC, Kotak
    ri("\\bat\\s+([a-z0-9][a-z0-9 .&'*_-]{1,40}?)(?:\\s+on\\b|\\s+avl|\\.\\s|,|\\.$|$)"),                   // card spends
    ri("\\b(?:from|by)\\s+([a-z][a-z0-9 .&'_-]{1,40}?)(?:\\s+on\\b|\\s+ref\\w*|\\s+upi|\\.\\s|\\.$|$)"),         // income
  )
  private val junkPayee = ri("^(upi|neft|imps|rtgs|your|a/c|acct|account|card|bank|vpa|you|the|net ?banking|atm|pos)\\b|^\\d+$")

  fun amount(text: String): Long? {
    for (m in money.findAll(text)) {
      val before = text.substring(maxOf(0, m.range.first - 28), m.range.first)
      if (notTheAmount.containsMatchIn(before)) continue
      paise(m.groupValues[1])?.let { return it }
    }
    return bareAmount.find(text)?.let { paise(it.groupValues[1]) }
  }

  private fun paise(s: String): Long? {
    val d = s.replace(",", "").toBigDecimalOrNull() ?: return null
    val p = d.movePointRight(2).toLong()
    return if (p > 0) p else null
  }

  fun payee(text: String): String? {
    for (p in payeePatterns) {
      val raw = p.find(text)?.groupValues?.get(1)?.trim()?.trimEnd('.', '-', '/') ?: continue
      if (raw.length < 2 || junkPayee.containsMatchIn(raw)) continue
      return if ('@' in raw) raw.substringBefore('@') else raw
    }
    return vpa.find(text)?.groupValues?.get(1)?.substringBefore('@')
  }

  /** Stable id for this alert, so the same SMS (or its notification copy) is only ever added once. */
  fun key(text: String, amount: Long): String {
    val r = upiRef.find(text)?.groupValues?.get(1) ?: ref.find(text)?.groupValues?.get(1)
    if (r != null) return "alert:$r"
    val norm = text.lowercase().replace(Regex("[^a-z0-9]"), "")
    return "alert:${amount}:${norm.hashCode().toUInt().toString(16)}"
  }

  fun isBankAlert(text: String): Boolean =
    !ignore.containsMatchIn(text) && (debit.containsMatchIn(text) || credit.containsMatchIn(text)) && amount(text) != null

  fun parse(a: PendingAlert, ctx: CaptureContext): CaptureDraft? {
    val text = a.text.replace(Regex("\\s+"), " ").trim()
    if (ignore.containsMatchIn(text)) return null
    val amt = amount(text) ?: return null
    val isDebit = debit.containsMatchIn(text)
    val isCredit = !isDebit && credit.containsMatchIn(text)
    if (!isDebit && !isCredit && !cardBill.containsMatchIn(text)) return null

    val l4 = last4.findAll(text).map { it.groupValues[1] }.toList()
    var account = ctx.accounts.firstOrNull { acc -> acc.last4 != null && l4.any { acc.last4.endsWith(it) || it.endsWith(acc.last4) } }
      ?: CaptureDrafts.findAccount("$text ${a.sender ?: ""}", ctx.accounts)?.first

    var type = if (isCredit) "income" else "expense"
    var toAccountId: String? = null
    var fromId = account?.id ?: ctx.defaultAccountId ?: ctx.accounts.firstOrNull()?.id
    if (cardBill.containsMatchIn(text)) {
      val card = account?.takeIf { it.type == "card" } ?: ctx.accounts.filter { it.type == "card" }.singleOrNull()
      if (card != null) {
        type = "transfer"; toAccountId = card.id
        fromId = ctx.defaultAccountId?.takeIf { it != card.id } ?: ctx.accounts.firstOrNull { it.type == "bank" }?.id
      }
    }
    val name = payee(text)
    val brand = Brands.match(name) ?: Brands.match(text)
    val titled = name?.lowercase()?.replace(Regex("\\b\\w")) { it.value.uppercase() }
    val payeeName = if (type == "transfer") null else brand?.name ?: titled?.let { CaptureDrafts.displayName(it) }
    return CaptureDraft(
      key = key(text, amt), type = type, amount = amt, accountId = fromId, toAccountId = toAccountId,
      categoryId = if (type == "transfer") null else CaptureDrafts.guessCategory("$text ${name ?: ""}", payeeName, type, ctx),
      payee = payeeName, note = if (type == "transfer") "Card bill payment" else null, occurredAt = a.receivedAt,
      source = text.take(200), include = true,
      warning = if (account == null) "Couldn't tell which account. Check it." else null,
    )
  }
}
