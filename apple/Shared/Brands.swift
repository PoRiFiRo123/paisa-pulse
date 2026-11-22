import Foundation
import SwiftUI

/// A merchant we recognise: name, brand colour (for the monogram) and website (for an optional logo).
/// Same list and order as the Android app (logic/Brands.kt), ported from the RN app's brands.ts.
struct Brand: Hashable {
  let name: String
  let pattern: String
  let color: String
  let domain: String?

  var monogram: String {
    name.first(where: { $0.isLetter || $0.isNumber }).map { String($0).uppercased() } ?? "•"
  }
  func logoURL(size: Int = 128) -> URL? {
    domain.flatMap { URL(string: "https://www.google.com/s2/favicons?domain=\($0)&sz=\(size)") }
  }
}

enum Brands {
  private static func B(_ p: String, _ n: String, _ c: String, _ d: String?) -> Brand { Brand(name: n, pattern: p, color: c, domain: d) }

  /// More specific patterns first (Instamart before Swiggy, Prime before Amazon).
  static let all: [Brand] = [
    B(#"instamart"#, "Swiggy Instamart", "#FC8019", "swiggy.com"),
    B(#"swiggy|bundl tech"#, "Swiggy", "#FC8019", "swiggy.com"),
    B(#"zomato|zomato media|eternal ltd"#, "Zomato", "#E23744", "zomato.com"),
    B(#"blinkit|grofers"#, "Blinkit", "#F8CB46", "blinkit.com"),
    B(#"zepto|kiranakart"#, "Zepto", "#5A1F9E", "zeptonow.com"),
    B(#"big\s?basket|supermarket grocery"#, "BigBasket", "#84C225", "bigbasket.com"),
    B(#"dmart|avenue supermarts"#, "DMart", "#0D8F44", "dmart.in"),
    B(#"uber"#, "Uber", "#000000", "uber.com"),
    B(#"\bola\b|ani technologies|olacabs"#, "Ola", "#1C1C1C", "olacabs.com"),
    B(#"rapido|roppen"#, "Rapido", "#F9C935", "rapido.bike"),
    B(#"prime video|amazon prime"#, "Amazon Prime", "#00A8E1", "primevideo.com"),
    B(#"amazon pay|amazon"#, "Amazon", "#FF9900", "amazon.in"),
    B(#"flipkart"#, "Flipkart", "#2874F0", "flipkart.com"),
    B(#"myntra"#, "Myntra", "#FF3F6C", "myntra.com"),
    B(#"nykaa"#, "Nykaa", "#FC2779", "nykaa.com"),
    B(#"ajio"#, "AJIO", "#2C4152", "ajio.com"),
    B(#"meesho"#, "Meesho", "#9F2089", "meesho.com"),
    B(#"netflix"#, "Netflix", "#E50914", "netflix.com"),
    B(#"spotify"#, "Spotify", "#1DB954", "spotify.com"),
    B(#"youtube"#, "YouTube", "#FF0000", "youtube.com"),
    B(#"google\s?play|google\s?india digital|google pay|google"#, "Google", "#4285F4", "google.com"),
    B(#"apple\s?(services|media)|itunes|apple\.com|apple"#, "Apple", "#000000", "apple.com"),
    B(#"hotstar|jiocinema|jiohotstar|novi digital"#, "JioHotstar", "#1F80E0", "hotstar.com"),
    B(#"bookmyshow|bigtree"#, "BookMyShow", "#C4242B", "bookmyshow.com"),
    B(#"\bpvr\b|inox"#, "PVR INOX", "#F7C600", "pvrcinemas.com"),
    B(#"bharti airtel|airtel"#, "Airtel", "#E40000", "airtel.in"),
    B(#"reliance jio|\bjio\b"#, "Jio", "#0F3CC9", "jio.com"),
    B(#"vodafone|\bvi\b|idea cellular"#, "Vi", "#ED1C24", "myvi.in"),
    B(#"act fibernet|atria convergence"#, "ACT Fibernet", "#EC1C24", "actcorp.in"),
    B(#"tata play|tata sky"#, "Tata Play", "#A1006B", "tataplay.com"),
    B(#"bescom"#, "BESCOM", "#1B5E20", nil),
    B(#"tata power"#, "Tata Power", "#0070C0", "tatapower.com"),
    B(#"adani electricity"#, "Adani Electricity", "#2E3192", "adanielectricity.com"),
    B(#"msedcl|mahadiscom"#, "MSEDCL", "#0B6E4F", "mahadiscom.in"),
    B(#"irctc"#, "IRCTC", "#213A8F", "irctc.co.in"),
    B(#"makemytrip|make my trip"#, "MakeMyTrip", "#EB2026", "makemytrip.com"),
    B(#"goibibo|ibibo"#, "Goibibo", "#2276E3", "goibibo.com"),
    B(#"indigo|interglobe"#, "IndiGo", "#001B94", "goindigo.in"),
    B(#"air india"#, "Air India", "#DA0E29", "airindia.com"),
    B(#"\boyo\b|oravel"#, "OYO", "#EE2E24", "oyorooms.com"),
    B(#"zerodha"#, "Zerodha", "#387ED1", "zerodha.com"),
    B(#"groww|nextbillion"#, "Groww", "#00D09C", "groww.in"),
    B(#"indian clearing|iccl|bse ltd|nse clearing"#, "Mutual fund / SIP", "#5856D6", nil),
    B(#"\blic\b|life insurance corp"#, "LIC", "#0066B3", "licindia.in"),
    B(#"bajaj fin"#, "Bajaj Finance", "#005BAC", "bajajfinserv.in"),
    B(#"nobroker"#, "NoBroker", "#FD3752", "nobroker.in"),
    B(#"apollo pharm|apollo"#, "Apollo", "#00539B", "apollopharmacy.in"),
    B(#"pharmeasy"#, "PharmEasy", "#10847E", "pharmeasy.in"),
    B(#"tata 1mg|\b1mg\b"#, "Tata 1mg", "#FF6F61", "1mg.com"),
    B(#"practo"#, "Practo", "#14BEF0", "practo.com"),
    B(#"hpcl|hindustan petroleum"#, "HPCL", "#003A8C", "hindustanpetroleum.com"),
    B(#"bpcl|bharat petroleum"#, "BPCL", "#0055A5", "bharatpetroleum.in"),
    B(#"iocl|indian oil"#, "Indian Oil", "#F37022", "iocl.com"),
    B(#"shell"#, "Shell", "#FFD500", "shell.in"),
    B(#"starbucks|tata starbucks"#, "Starbucks", "#00704A", "starbucks.in"),
    B(#"mcdonald|hardcastle|westlife"#, "McDonald's", "#DA291C", "mcdonaldsindia.com"),
    B(#"domino|jubilant foodworks"#, "Domino's", "#006491", "dominos.co.in"),
    B(#"\bkfc\b|devyani"#, "KFC", "#A3080C", "kfc.co.in"),
    B(#"cult\.?fit|curefit"#, "cult.fit", "#1C1C1C", "cult.fit"),
    B(#"paytm|one97"#, "Paytm", "#00BAF2", "paytm.com"),
    B(#"phonepe"#, "PhonePe", "#5F259F", "phonepe.com"),
    B(#"\bcred\b|dreamplug"#, "CRED", "#1C1C1C", "cred.club"),
    B(#"urban\s?company|urbanclap"#, "Urban Company", "#000000", "urbancompany.com"),
    B(#"croma|infiniti retail"#, "Croma", "#00B3A0", "croma.com"),
    B(#"reliance digital"#, "Reliance Digital", "#E42529", "reliancedigital.in"),
    B(#"jiomart|reliance (fresh|smart|retail)"#, "JioMart", "#0078AD", "jiomart.com"),
    B(#"lenskart"#, "Lenskart", "#000042", "lenskart.com"),
    B(#"decathlon"#, "Decathlon", "#0082C3", "decathlon.in"),
    B(#"ikea"#, "IKEA", "#0058A3", "ikea.com"),
  ]

  private static let compiled: [(Brand, NSRegularExpression)] = all.compactMap { b in
    (try? NSRegularExpression(pattern: b.pattern, options: [.caseInsensitive])).map { (b, $0) }
  }
  nonisolated(unsafe) private static var cache: [String: Brand?] = [:]
  private static let lock = NSLock()

  /// The brand a payee or narration refers to, if we know it.
  static func match(_ text: String?) -> Brand? {
    guard let text, !text.isEmpty else { return nil }
    lock.lock(); defer { lock.unlock() }
    if let hit = cache[text] { return hit }
    let range = NSRange(text.startIndex..., in: text)
    let brand = compiled.first { $0.1.firstMatch(in: text, range: range) != nil }?.0
    if cache.count > 2000 { cache.removeAll() }
    cache[text] = brand
    return brand
  }

  /// Black or white text for a background colour (WCAG relative luminance).
  static func onColor(_ hex: String) -> Color {
    let n = Int(hex.dropFirst(), radix: 16) ?? 0
    let ch = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map { v -> Double in
      let c = Double(v) / 255
      return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    let lum = 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2]
    return 1.05 / (lum + 0.05) >= (lum + 0.05) / 0.05 ? .white : .black
  }
}
