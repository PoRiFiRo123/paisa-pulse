#!/usr/bin/env python3
"""Generates the bank and world-currency lists for both apps from one source:
apple/Shared/ReferenceData.swift and androidApp/.../logic/ReferenceData.kt.
Run: python3 scripts/gen-reference-data.py"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# (id, short name, full name, brand colour, kind). kind: psu | private | sfb | payments | foreign | coop | wallet
BANKS = [
    ("sbi", "SBI", "State Bank of India", "#22409A", "psu"),
    ("hdfc", "HDFC Bank", "HDFC Bank", "#004C8F", "private"),
    ("icici", "ICICI Bank", "ICICI Bank", "#F37021", "private"),
    ("axis", "Axis Bank", "Axis Bank", "#97144D", "private"),
    ("kotak", "Kotak", "Kotak Mahindra Bank", "#ED1C24", "private"),
    ("bob", "Bank of Baroda", "Bank of Baroda", "#F15A29", "psu"),
    ("pnb", "PNB", "Punjab National Bank", "#A20A3A", "psu"),
    ("canara", "Canara Bank", "Canara Bank", "#0091D5", "psu"),
    ("union", "Union Bank", "Union Bank of India", "#E31E24", "psu"),
    ("idfc", "IDFC FIRST", "IDFC FIRST Bank", "#9C1D27", "private"),
    ("indusind", "IndusInd", "IndusInd Bank", "#8B2332", "private"),
    ("yes", "YES Bank", "YES Bank", "#0060AA", "private"),
    ("federal", "Federal Bank", "Federal Bank", "#F7A800", "private"),
    ("au", "AU Bank", "AU Small Finance Bank", "#6E2B8B", "sfb"),
    ("boi", "Bank of India", "Bank of India", "#F58220", "psu"),
    ("indian", "Indian Bank", "Indian Bank", "#1A4D8F", "psu"),
    ("central", "Central Bank", "Central Bank of India", "#C8102E", "psu"),
    ("iob", "IOB", "Indian Overseas Bank", "#005BAA", "psu"),
    ("uco", "UCO Bank", "UCO Bank", "#004B8D", "psu"),
    ("bom", "Bank of Maharashtra", "Bank of Maharashtra", "#E2231A", "psu"),
    ("psb", "Punjab & Sind", "Punjab & Sind Bank", "#00A859", "psu"),
    ("idbi", "IDBI Bank", "IDBI Bank", "#00836C", "private"),
    ("bandhan", "Bandhan Bank", "Bandhan Bank", "#E31E26", "private"),
    ("rbl", "RBL Bank", "RBL Bank", "#21409A", "private"),
    ("southindian", "South Indian Bank", "South Indian Bank", "#E31E24", "private"),
    ("karnataka", "Karnataka Bank", "Karnataka Bank", "#ED1C24", "private"),
    ("kvb", "Karur Vysya", "Karur Vysya Bank", "#1D5A2E", "private"),
    ("cub", "City Union", "City Union Bank", "#A6192E", "private"),
    ("tmb", "TMB", "Tamilnad Mercantile Bank", "#00539B", "private"),
    ("dcb", "DCB Bank", "DCB Bank", "#00A0AF", "private"),
    ("csb", "CSB Bank", "CSB Bank", "#E30613", "private"),
    ("jk", "J&K Bank", "Jammu & Kashmir Bank", "#ED1C24", "private"),
    ("dhanlaxmi", "Dhanlaxmi", "Dhanlaxmi Bank", "#7B2C83", "private"),
    ("nainital", "Nainital Bank", "Nainital Bank", "#004B87", "private"),
    ("equitas", "Equitas", "Equitas Small Finance Bank", "#F7941D", "sfb"),
    ("ujjivan", "Ujjivan", "Ujjivan Small Finance Bank", "#00A0E3", "sfb"),
    ("jana", "Jana Bank", "Jana Small Finance Bank", "#00A651", "sfb"),
    ("suryoday", "Suryoday", "Suryoday Small Finance Bank", "#F58220", "sfb"),
    ("esaf", "ESAF", "ESAF Small Finance Bank", "#00843D", "sfb"),
    ("utkarsh", "Utkarsh", "Utkarsh Small Finance Bank", "#8DC63F", "sfb"),
    ("unity", "Unity Bank", "Unity Small Finance Bank", "#1C3F94", "sfb"),
    ("shivalik", "Shivalik", "Shivalik Small Finance Bank", "#F15A22", "sfb"),
    ("capital", "Capital SFB", "Capital Small Finance Bank", "#00529B", "sfb"),
    ("northeast", "North East SFB", "North East Small Finance Bank", "#E31837", "sfb"),
    ("airtel", "Airtel Payments", "Airtel Payments Bank", "#E40000", "payments"),
    ("ippb", "India Post", "India Post Payments Bank", "#D71921", "payments"),
    ("fino", "Fino", "Fino Payments Bank", "#00539F", "payments"),
    ("jio", "Jio Payments", "Jio Payments Bank", "#0A2885", "payments"),
    ("nsdl", "NSDL Payments", "NSDL Payments Bank", "#1A5BA6", "payments"),
    ("sbm", "SBM India", "SBM Bank India", "#B3093A", "foreign"),
    ("hsbc", "HSBC", "HSBC India", "#DB0011", "foreign"),
    ("sc", "Standard Chartered", "Standard Chartered", "#0473EA", "foreign"),
    ("citi", "Citi", "Citibank India", "#056DAE", "foreign"),
    ("dbs", "DBS", "DBS Bank India", "#E3001B", "foreign"),
    ("deutsche", "Deutsche Bank", "Deutsche Bank", "#0018A8", "foreign"),
    ("barclays", "Barclays", "Barclays India", "#00AEEF", "foreign"),
    ("saraswat", "Saraswat Bank", "Saraswat Co-operative Bank", "#E31E24", "coop"),
    ("cosmos", "Cosmos Bank", "Cosmos Co-operative Bank", "#003F87", "coop"),
    ("svc", "SVC Bank", "SVC Co-operative Bank", "#0072BC", "coop"),
    ("abhyudaya", "Abhyudaya", "Abhyudaya Co-operative Bank", "#00843D", "coop"),
    ("tjsb", "TJSB", "TJSB Sahakari Bank", "#004A8F", "coop"),
    ("paytm", "Paytm", "Paytm Wallet", "#00BAF2", "wallet"),
    ("amazonpay", "Amazon Pay", "Amazon Pay", "#FF9900", "wallet"),
    ("phonepe", "PhonePe", "PhonePe Wallet", "#5F259F", "wallet"),
    ("mobikwik", "MobiKwik", "MobiKwik", "#0071BC", "wallet"),
    ("freecharge", "Freecharge", "Freecharge", "#F26722", "wallet"),
    ("airtelthanks", "Airtel Money", "Airtel Money", "#E40000", "wallet"),
    ("jiomoney", "JioMoney", "JioMoney", "#0A2885", "wallet"),
]
# Shown first in the picker.
POPULAR = ["sbi", "hdfc", "icici", "axis", "kotak", "bob", "pnb", "canara", "union", "idfc", "indusind", "yes", "federal", "au"]

# (country, currency code, symbol)
COUNTRIES = [
    ("India", "INR", "₹"), ("United States", "USD", "$"), ("United Kingdom", "GBP", "£"), ("UAE", "AED", "AED"),
    ("Singapore", "SGD", "S$"), ("Thailand", "THB", "฿"), ("Malaysia", "MYR", "RM"), ("Indonesia", "IDR", "Rp"),
    ("Vietnam", "VND", "₫"), ("Sri Lanka", "LKR", "Rs"), ("Nepal", "NPR", "Rs"), ("Bhutan", "BTN", "Nu."),
    ("Maldives", "MVR", "Rf"), ("Bangladesh", "BDT", "৳"), ("Japan", "JPY", "¥"), ("South Korea", "KRW", "₩"),
    ("China", "CNY", "CN¥"), ("Hong Kong", "HKD", "HK$"), ("Taiwan", "TWD", "NT$"), ("Philippines", "PHP", "₱"),
    ("Cambodia", "KHR", "៛"), ("Laos", "LAK", "₭"), ("Myanmar", "MMK", "K"), ("Mongolia", "MNT", "₮"),
    ("Australia", "AUD", "A$"), ("New Zealand", "NZD", "NZ$"), ("Fiji", "FJD", "FJ$"), ("Canada", "CAD", "C$"),
    ("Mexico", "MXN", "MX$"), ("Brazil", "BRL", "R$"), ("Argentina", "ARS", "AR$"), ("Chile", "CLP", "CL$"),
    ("Colombia", "COP", "CO$"), ("Peru", "PEN", "S/"), ("Saudi Arabia", "SAR", "SAR"), ("Qatar", "QAR", "QAR"),
    ("Oman", "OMR", "OMR"), ("Kuwait", "KWD", "KWD"), ("Bahrain", "BHD", "BHD"), ("Jordan", "JOD", "JOD"),
    ("Israel", "ILS", "₪"), ("Turkey", "TRY", "₺"), ("Egypt", "EGP", "E£"), ("Morocco", "MAD", "MAD"),
    ("Kenya", "KES", "KSh"), ("Tanzania", "TZS", "TSh"), ("South Africa", "ZAR", "R"), ("Mauritius", "MUR", "Rs"),
    ("Seychelles", "SCR", "SR"), ("Nigeria", "NGN", "₦"), ("Ghana", "GHS", "GH₵"), ("Ethiopia", "ETB", "Br"),
    ("Germany", "EUR", "€"), ("France", "EUR", "€"), ("Italy", "EUR", "€"), ("Spain", "EUR", "€"),
    ("Netherlands", "EUR", "€"), ("Belgium", "EUR", "€"), ("Austria", "EUR", "€"), ("Portugal", "EUR", "€"),
    ("Greece", "EUR", "€"), ("Ireland", "EUR", "€"), ("Finland", "EUR", "€"), ("Croatia", "EUR", "€"),
    ("Malta", "EUR", "€"), ("Cyprus", "EUR", "€"), ("Luxembourg", "EUR", "€"), ("Estonia", "EUR", "€"),
    ("Latvia", "EUR", "€"), ("Lithuania", "EUR", "€"), ("Slovakia", "EUR", "€"), ("Slovenia", "EUR", "€"),
    ("Switzerland", "CHF", "CHF"), ("Norway", "NOK", "kr"), ("Sweden", "SEK", "kr"), ("Denmark", "DKK", "kr"),
    ("Iceland", "ISK", "kr"), ("Poland", "PLN", "zł"), ("Czech Republic", "CZK", "Kč"), ("Hungary", "HUF", "Ft"),
    ("Romania", "RON", "lei"), ("Bulgaria", "BGN", "лв"), ("Serbia", "RSD", "din"), ("Russia", "RUB", "₽"),
    ("Ukraine", "UAH", "₴"), ("Georgia", "GEL", "₾"), ("Armenia", "AMD", "֏"), ("Azerbaijan", "AZN", "₼"),
    ("Kazakhstan", "KZT", "₸"), ("Uzbekistan", "UZS", "soʻm"), ("Pakistan", "PKR", "Rs"), ("Afghanistan", "AFN", "؋"),
    ("Iran", "IRR", "IRR"), ("Iraq", "IQD", "IQD"), ("Lebanon", "LBP", "LBP"),
]

def swift_str(s): return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'

def write_swift():
    lines = ["// Generated by scripts/gen-reference-data.py. Edit the script, not this file.", "", "import Foundation", "",
             "/// Indian banks and wallets for the account picker: short name, full name, brand colour.",
             "enum Banks {",
             "  struct Bank: Identifiable, Hashable { let id, short, name, color, kind: String }",
             "  static let all: [Bank] = ["]
    for b in BANKS:
        lines.append("    Bank(id: %s, short: %s, name: %s, color: %s, kind: %s)," % tuple(swift_str(x) for x in b))
    lines += ["  ]",
              "  static let popular: [String] = [" + ", ".join(swift_str(x) for x in POPULAR) + "]",
              "  static func byId(_ id: String?) -> Bank? { all.first { $0.id == id } }",
              "  /// Matches a typed or stored bank name (\"Axis Bank\", \"axis\", \"State Bank of India\").",
              "  static func match(_ name: String?) -> Bank? {",
              "    guard let n = name?.lowercased().trimmingCharacters(in: .whitespaces), !n.isEmpty else { return nil }",
              "    return all.first { $0.short.lowercased() == n || $0.name.lowercased() == n || $0.id == n }",
              "      ?? all.first { n.contains($0.short.lowercased()) || n.contains($0.name.lowercased()) }",
              "  }",
              "}", "",
              "/// Countries and their currencies (trip destinations, main currency, converter).",
              "enum World {",
              "  struct Country: Hashable { let name, currency, symbol: String }",
              "  static let countries: [Country] = ["]
    for c in COUNTRIES:
        lines.append("    Country(name: %s, currency: %s, symbol: %s)," % tuple(swift_str(x) for x in c))
    lines += ["  ]",
              "  /// One entry per currency code, in list order.",
              "  static let currencies: [(code: String, symbol: String)] = {",
              "    var seen = Set<String>()",
              "    return countries.compactMap { seen.insert($0.currency).inserted ? ($0.currency, $0.symbol) : nil }",
              "  }()",
              "  static func symbol(_ code: String) -> String { countries.first { $0.currency == code }?.symbol ?? code }",
              "  static func currencyName(_ code: String) -> String { Locale(identifier: \"en_US\").localizedString(forCurrencyCode: code) ?? code }",
              "}", ""]
    open(os.path.join(ROOT, "apple/Shared/ReferenceData.swift"), "w").write("\n".join(lines))

def write_kotlin():
    lines = ["// Generated by scripts/gen-reference-data.py. Edit the script, not this file.", "package com.paisapulse.app.logic", "",
             "/** Indian banks and wallets for the account picker: short name, full name, brand colour. */",
             "object Banks {",
             "  data class Bank(val id: String, val short: String, val name: String, val color: String, val kind: String)",
             "  val all = listOf("]
    for b in BANKS:
        lines.append("    Bank(%s, %s, %s, %s, %s)," % tuple(swift_str(x).replace("$", "\\$") for x in b))
    lines += ["  )",
              "  val popular = listOf(" + ", ".join(swift_str(x) for x in POPULAR) + ")",
              "  fun byId(id: String?) = all.firstOrNull { it.id == id }",
              "  /** Matches a typed or stored bank name (\"Axis Bank\", \"axis\", \"State Bank of India\"). */",
              "  fun match(name: String?): Bank? {",
              "    val n = name?.trim()?.lowercase()?.takeIf { it.isNotEmpty() } ?: return null",
              "    return all.firstOrNull { it.short.lowercase() == n || it.name.lowercase() == n || it.id == n }",
              "      ?: all.firstOrNull { n.contains(it.short.lowercase()) || n.contains(it.name.lowercase()) }",
              "  }",
              "}", "",
              "/** Countries and their currencies (trip destinations, main currency, converter). */",
              "object World {",
              "  data class Country(val name: String, val currency: String, val symbol: String)",
              "  val countries = listOf("]
    for c in COUNTRIES:
        lines.append("    Country(%s, %s, %s)," % tuple(swift_str(x).replace("$", "\\$") for x in c))
    lines += ["  )",
              "  /** One entry per currency code, in list order. */",
              "  val currencies: List<Pair<String, String>> by lazy { countries.distinctBy { it.currency }.map { it.currency to it.symbol } }",
              "  fun symbol(code: String) = countries.firstOrNull { it.currency == code }?.symbol ?: code",
              "  fun currencyName(code: String): String = runCatching { java.util.Currency.getInstance(code).getDisplayName(java.util.Locale.US) }.getOrDefault(code)",
              "}", ""]
    open(os.path.join(ROOT, "androidApp/app/src/main/java/com/paisapulse/app/logic/ReferenceData.kt"), "w").write("\n".join(lines))

write_swift(); write_kotlin()
print(len(BANKS), "banks,", len(COUNTRIES), "countries")
