package com.paisapulse.app.logic

/** A merchant we recognise: name, brand colour (monogram) and website (optional logo). Same list as iOS Brands.swift. */
data class Brand(val name: String, val regex: Regex, val color: String, val domain: String?) {
  val monogram: String get() = name.firstOrNull { it.isLetterOrDigit() }?.uppercase() ?: "•"
  fun logoUrl(size: Int = 128): String? = domain?.let { "https://www.google.com/s2/favicons?domain=$it&sz=$size" }
}

object Brands {
  private fun B(p: String, n: String, c: String, d: String?) = Brand(n, Regex(p, RegexOption.IGNORE_CASE), c, d)

  /** More specific patterns first (Instamart before Swiggy, Prime before Amazon). */
  val all: List<Brand> = listOf(
    B("instamart", "Swiggy Instamart", "#FC8019", "swiggy.com"),
    B("swiggy|bundl tech", "Swiggy", "#FC8019", "swiggy.com"),
    B("zomato|zomato media|eternal ltd", "Zomato", "#E23744", "zomato.com"),
    B("blinkit|grofers", "Blinkit", "#F8CB46", "blinkit.com"),
    B("zepto|kiranakart", "Zepto", "#5A1F9E", "zeptonow.com"),
    B("big\\s?basket|supermarket grocery", "BigBasket", "#84C225", "bigbasket.com"),
    B("dmart|avenue supermarts", "DMart", "#0D8F44", "dmart.in"),
    B("uber", "Uber", "#000000", "uber.com"),
    B("\\bola\\b|ani technologies|olacabs", "Ola", "#1C1C1C", "olacabs.com"),
    B("rapido|roppen", "Rapido", "#F9C935", "rapido.bike"),
    B("prime video|amazon prime", "Amazon Prime", "#00A8E1", "primevideo.com"),
    B("amazon pay|amazon", "Amazon", "#FF9900", "amazon.in"),
    B("flipkart", "Flipkart", "#2874F0", "flipkart.com"),
    B("myntra", "Myntra", "#FF3F6C", "myntra.com"),
    B("nykaa", "Nykaa", "#FC2779", "nykaa.com"),
    B("ajio", "AJIO", "#2C4152", "ajio.com"),
    B("meesho", "Meesho", "#9F2089", "meesho.com"),
    B("netflix", "Netflix", "#E50914", "netflix.com"),
    B("spotify", "Spotify", "#1DB954", "spotify.com"),
    B("youtube", "YouTube", "#FF0000", "youtube.com"),
    B("google\\s?play|google\\s?india digital|google pay|google", "Google", "#4285F4", "google.com"),
    B("apple\\s?(services|media)|itunes|apple\\.com|apple", "Apple", "#000000", "apple.com"),
    B("hotstar|jiocinema|jiohotstar|novi digital", "JioHotstar", "#1F80E0", "hotstar.com"),
    B("bookmyshow|bigtree", "BookMyShow", "#C4242B", "bookmyshow.com"),
    B("\\bpvr\\b|inox", "PVR INOX", "#F7C600", "pvrcinemas.com"),
    B("bharti airtel|airtel", "Airtel", "#E40000", "airtel.in"),
    B("reliance jio|\\bjio\\b", "Jio", "#0F3CC9", "jio.com"),
    B("vodafone|\\bvi\\b|idea cellular", "Vi", "#ED1C24", "myvi.in"),
    B("act fibernet|atria convergence", "ACT Fibernet", "#EC1C24", "actcorp.in"),
    B("tata play|tata sky", "Tata Play", "#A1006B", "tataplay.com"),
    B("bescom", "BESCOM", "#1B5E20", null),
    B("tata power", "Tata Power", "#0070C0", "tatapower.com"),
    B("adani electricity", "Adani Electricity", "#2E3192", "adanielectricity.com"),
    B("msedcl|mahadiscom", "MSEDCL", "#0B6E4F", "mahadiscom.in"),
    B("irctc", "IRCTC", "#213A8F", "irctc.co.in"),
    B("makemytrip|make my trip", "MakeMyTrip", "#EB2026", "makemytrip.com"),
    B("goibibo|ibibo", "Goibibo", "#2276E3", "goibibo.com"),
    B("indigo|interglobe", "IndiGo", "#001B94", "goindigo.in"),
    B("air india", "Air India", "#DA0E29", "airindia.com"),
    B("\\boyo\\b|oravel", "OYO", "#EE2E24", "oyorooms.com"),
    B("zerodha", "Zerodha", "#387ED1", "zerodha.com"),
    B("groww|nextbillion", "Groww", "#00D09C", "groww.in"),
    B("indian clearing|iccl|bse ltd|nse clearing", "Mutual fund / SIP", "#5856D6", null),
    B("\\blic\\b|life insurance corp", "LIC", "#0066B3", "licindia.in"),
    B("bajaj fin", "Bajaj Finance", "#005BAC", "bajajfinserv.in"),
    B("nobroker", "NoBroker", "#FD3752", "nobroker.in"),
    B("apollo pharm|apollo", "Apollo", "#00539B", "apollopharmacy.in"),
    B("pharmeasy", "PharmEasy", "#10847E", "pharmeasy.in"),
    B("tata 1mg|\\b1mg\\b", "Tata 1mg", "#FF6F61", "1mg.com"),
    B("practo", "Practo", "#14BEF0", "practo.com"),
    B("hpcl|hindustan petroleum", "HPCL", "#003A8C", "hindustanpetroleum.com"),
    B("bpcl|bharat petroleum", "BPCL", "#0055A5", "bharatpetroleum.in"),
    B("iocl|indian oil", "Indian Oil", "#F37022", "iocl.com"),
    B("shell", "Shell", "#FFD500", "shell.in"),
    B("starbucks|tata starbucks", "Starbucks", "#00704A", "starbucks.in"),
    B("mcdonald|hardcastle|westlife", "McDonald's", "#DA291C", "mcdonaldsindia.com"),
    B("domino|jubilant foodworks", "Domino's", "#006491", "dominos.co.in"),
    B("\\bkfc\\b|devyani", "KFC", "#A3080C", "kfc.co.in"),
    B("cult\\.?fit|curefit", "cult.fit", "#1C1C1C", "cult.fit"),
    B("paytm|one97", "Paytm", "#00BAF2", "paytm.com"),
    B("phonepe", "PhonePe", "#5F259F", "phonepe.com"),
    B("\\bcred\\b|dreamplug", "CRED", "#1C1C1C", "cred.club"),
    B("urban\\s?company|urbanclap", "Urban Company", "#000000", "urbancompany.com"),
    B("croma|infiniti retail", "Croma", "#00B3A0", "croma.com"),
    B("reliance digital", "Reliance Digital", "#E42529", "reliancedigital.in"),
    B("jiomart|reliance (fresh|smart|retail)", "JioMart", "#0078AD", "jiomart.com"),
    B("lenskart", "Lenskart", "#000042", "lenskart.com"),
    B("decathlon", "Decathlon", "#0082C3", "decathlon.in"),
    B("ikea", "IKEA", "#0058A3", "ikea.com"),
  )

  private val cache = java.util.concurrent.ConcurrentHashMap<String, Any>()
  private object None

  fun match(text: String?): Brand? {
    if (text.isNullOrEmpty()) return null
    cache[text]?.let { return it as? Brand }
    val b = all.firstOrNull { it.regex.containsMatchIn(text) }
    if (cache.size > 2000) cache.clear()
    cache[text] = b ?: None
    return b
  }

  /** True when white text reads better than black on this colour. */
  fun whiteOn(hex: String): Boolean {
    val n = hex.removePrefix("#").toLong(16).toInt()
    val ch = listOf((n shr 16) and 255, (n shr 8) and 255, n and 255).map { v ->
      val c = v / 255.0; if (c <= 0.03928) c / 12.92 else Math.pow((c + 0.055) / 1.055, 2.4)
    }
    val lum = 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2]
    return 1.05 / (lum + 0.05) >= (lum + 0.05) / 0.05
  }
}
