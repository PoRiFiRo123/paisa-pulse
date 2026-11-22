package com.paisapulse.app.logic

/** What a bank narration says: channel, a clean payee, the UPI id and any remark. Same rules as iOS Narration.swift. */
data class Narration(val channel: String, val payee: String?, val upiId: String?, val note: String?)

object Narrations {
  private fun ri(p: String) = Regex(p, RegexOption.IGNORE_CASE)

  private val stop = setOf(
    "upi", "p2m", "p2a", "dr", "cr", "neft", "imps", "rtgs", "ach", "nach", "pos", "ecom", "mob", "mb", "ib", "inb", "net",
    "to transfer", "by transfer", "transfer", "payment", "pay", "paid", "paid via", "sent using", "upi payment", "collect",
    "request", "purchase", "txn", "ref", "na", "null", "others", "other", "self", "fund transfer", "fund trf", "trf", "ft",
    "credit", "debit", "cash", "from", "to", "by", "via", "ok", "upiintent", "intent", "no remarks",
  )
  private val bankCode = ri("^[a-z]{4}(0[a-z0-9]{6})?$")
  private val banks = ri("^(icic|hdfc|sbin|utib|barb|yesb|kkbk|punb|cnrb|ubin|idib|indb|idfb|pytm|airp|fdrl|bkid|ioba|maha|cbin|jaka|scbl|citi|hsbc|rbl|au|axis|icici|sbi|bob|kotak|paytm|ybl|ibl|axl|okaxis|oksbi|okhdfcbank|okicici|apl|jupiteraxis|fam)$")

  private val categoryRules = listOf(
    ri("salary|\\bsal\\b|payroll|wages") to "Salary",
    ri("interest|int\\.?\\s?pd|int\\.?\\s?cr|\\bsb int") to "Interest",
    ri("cashback|cash back") to "Cashback",
    ri("refund|reversal|\\brev\\b|chargeback") to "Refund",
    ri("swiggy|zomato|starbucks|mcdonald|domino|kfc|restaurant|cafe|hotel|dhaba|food|eatery|bakery|chai|pizza|biryani") to "Food & Dining",
    ri("blinkit|zepto|bigbasket|instamart|dmart|grocery|kirana|supermarket|more retail|reliance fresh|nature'?s basket|milk|dairy") to "Groceries",
    ri("hpcl|bpcl|indian oil|shell|petrol|fuel|filling station") to "Fuel",
    ri("uber|\\bola\\b|rapido|metro|namma|bmtc|auto|cab|fastag|parking") to "Metro/Auto/Cab",
    ri("bescom|tata power|adani electricity|msedcl|electricity|power|kseb|tneb|bses") to "Electricity",
    ri("airtel|\\bjio\\b|\\bvi\\b|vodafone|act fibernet|broadband|recharge|postpaid|prepaid|hathway") to "Mobile/Internet",
    ri("tata play|dish ?tv|d2h|sun direct|\\bdth\\b") to "DTH",
    ri("\\brent\\b|nobroker|housing\\.com|landlord") to "Rent",
    ri("\\bemi\\b|loan|bajaj fin|home credit|nach.*fin") to "EMI/Loans",
    ri("netflix|spotify|prime|hotstar|youtube|apple|google play|subscription|jiocinema") to "Subscriptions",
    ri("bookmyshow|pvr|inox|cinema|movie|steam|playstation") to "Entertainment",
    ri("irctc|makemytrip|goibibo|indigo|air india|vistara|cleartrip|yatra|oyo|airbnb|redbus|flight|railway") to "Travel",
    ri("apollo|pharm|1mg|practo|hospital|clinic|medical|diagnostic|lab\\b|dental") to "Health",
    ri("zerodha|groww|sip|mutual fund|iccl|nse|bse|smallcase|kuvera|ppf|nps") to "Investments",
    ri("\\blic\\b|insurance|policy") to "Bills & Utilities",
    ri("amazon|flipkart|myntra|nykaa|ajio|meesho|decathlon|ikea|croma|reliance digital|mall|store|shop") to "Shopping",
    ri("school|college|university|course|udemy|coursera|byju|unacademy|tuition|fees") to "Education",
    ri("salon|spa|parlour|barber|urban company|cult\\.?fit|gym") to "Personal Care",
    ri("donation|temple|charity|gift") to "Gifts & Donations",
  )
  private val incomeOnly = setOf("Salary", "Interest", "Cashback", "Refund")

  private val cardPayment = ri("credit card|cc payment|card payment|cc bill|card bill|autopay.*card|billdesk.*card|bbps.*card|cred club|\\bcred\\b|payment received|payment - thank|thank you for (your )?payment|bbps payment received")
  private val atm = ri("\\batm\\b|atm-wdl|atw-|nwd-|nfs/cash|cash wdl|cash withdrawal|cardless cash")
  private val charges = ri("charges?|chrgs|\\bgst\\b|annual fee|amc|sms alert|debit card fee|penalty|min bal|late fee|finance charge")

  private fun titleCase(s: String): String =
    Regex("\\b(Upi|Neft|Imps|Atm|Emi|Lic|Llp)\\b").replace(Regex("\\b([a-z])").replace(s.lowercase()) { it.value.uppercase() }) { it.value.uppercase() }

  fun cleanPayee(raw: String): String {
    Brands.match(raw)?.let { return it.name }
    val cleaned = raw.replace(ri("\\b(private|pvt|limited|ltd|llp|india|p ltd|pvt ltd|co|inc)\\b\\.?"), " ")
      .replace(ri("[^a-z0-9&'. ]"), " ").replace(Regex("\\s+"), " ").trim()
    return titleCase(cleaned.ifEmpty { raw.trim() })
  }

  private fun isName(t: String): Boolean {
    val s = t.trim()
    return s.length >= 3 && s.any { it.isLetter() } && !s.contains('@') && s.lowercase() !in stop && !bankCode.matches(s) &&
      !banks.matches(s) && !ri("^[a-z]{0,4}\\d{5,}$").matches(s) && !ri("^x+\\d+$").matches(s) && !(s.firstOrNull()?.isDigit() ?: false) &&
      !ri("^(neft|imps|rtgs|ach|nach|ecs|upi|mmt|bil|onl|trf|pos)\\b").containsMatchIn(s) &&
      !ri("^(payment|paid|pay|sent|collect|received|transfer)\\b").containsMatchIn(s)
  }

  fun parse(text: String): Narration {
    val raw = text.replace(Regex("\\s+"), " ").trim()
    val tokens = raw.split(Regex("[/|\\\\]|(?<=\\S)-(?=\\S)|\\s-\\s|:")).map { it.trim() }.filter { it.isNotEmpty() }
    val upiId = ri("[a-z0-9._-]+@[a-z]{2,}").find(raw)?.value
    val channel = when {
      cardPayment.containsMatchIn(raw) -> "CARD_PAYMENT"
      ri("\\bupi\\b").containsMatchIn(raw) || upiId != null -> "UPI"
      atm.containsMatchIn(raw) -> "ATM"
      ri("\\bneft\\b").containsMatchIn(raw) -> "NEFT"
      ri("\\bimps\\b|mmt/imps").containsMatchIn(raw) -> "IMPS"
      ri("\\brtgs\\b").containsMatchIn(raw) -> "RTGS"
      ri("\\b(nach|ach|ecs)\\b").containsMatchIn(raw) -> "NACH"
      ri("^pos\\b|\\bpos\\s|ecom|card txn|\\bvps\\b|\\bvin\\b").containsMatchIn(raw) -> "POS"
      ri("interest|int\\.?\\s?pd|int\\.?\\s?cr").containsMatchIn(raw) -> "INTEREST"
      ri("refund|reversal|\\brev\\b").containsMatchIn(raw) -> "REFUND"
      charges.containsMatchIn(raw) -> "CHARGES"
      else -> "OTHER"
    }
    val fixed = mapOf("ATM" to "ATM withdrawal", "INTEREST" to "Interest", "CHARGES" to "Bank charges", "CARD_PAYMENT" to "Credit card payment")
    fixed[channel]?.let { return Narration(channel, it, upiId, null) }
    val brand = Brands.match(raw)?.name
    var payee: String?; var note: String? = null
    when (channel) {
      "UPI" -> {
        val at = tokens.indexOfFirst { it.contains('@') }
        val before = if (at > 0) tokens.subList(0, at).reversed().firstOrNull(::isName) else null
        val names = tokens.filter(::isName)
        payee = brand ?: before ?: names.maxByOrNull { it.length } ?: upiId?.substringBefore('@')?.replace(Regex("[._-]?\\d+$"), "")
        val after = if (at >= 0) tokens.drop(at + 1).filter { isName(it) && !banks.matches(it.replace(ri("\\s*bank$"), "")) } else emptyList()
        note = after.joinToString(" ").ifEmpty { null }
      }
      "POS" -> {
        val m = ri("(?:pos|ecom|vps|vin)[\\s/]*(?:[x\\d*]{6,}\\s*)?(.+)$").find(raw)
        payee = brand ?: m?.groupValues?.get(1)?.split("/")?.first() ?: tokens.firstOrNull(::isName)
      }
      else -> {
        val names = tokens.filter(::isName)
        payee = brand ?: names.firstOrNull()
        note = if (names.size > 1) names.drop(1).joinToString(" ") else null
      }
    }
    return Narration(channel, payee?.let(::cleanPayee) ?: if (raw.isNotEmpty()) cleanPayee(raw.take(40)) else null, upiId, note)
  }

  fun suggestCategory(narration: String, payee: String?, out: Boolean): String? {
    val text = "${payee ?: ""} $narration"
    for ((re, name) in categoryRules) {
      if (!re.containsMatchIn(text)) continue
      if ((name in incomeOnly) == !out) return name
    }
    return null
  }
}
