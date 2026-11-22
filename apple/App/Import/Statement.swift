import Compression
import Foundation

// Statement import, ported from the RN app (src/features/import) and kept identical to the Android
// app's Statement.kt (which is checked against the RN output): readers turn a file into a Sheet,
// the parser finds the header, columns, dates and amounts.

typealias Sheet = [[String]]

/// Small NSRegularExpression wrapper with JS-like helpers.
struct Rx {
  let re: NSRegularExpression
  init(_ pattern: String, caseInsensitive: Bool = true) {
    re = try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
  }
  private func range(_ s: String) -> NSRange { NSRange(location: 0, length: (s as NSString).length) }
  func test(_ s: String) -> Bool { re.firstMatch(in: s, range: range(s)) != nil }
  /// Groups of the first match ("" for groups that didn't take part); index 0 is the whole match.
  func first(_ s: String) -> [String]? {
    guard let m = re.firstMatch(in: s, range: range(s)) else { return nil }
    return groups(m, s)
  }
  func firstRange(_ s: String) -> NSRange? { re.firstMatch(in: s, range: range(s))?.range }
  func all(_ s: String) -> [[String]] { re.matches(in: s, range: range(s)).map { groups($0, s) } }
  func replace(_ s: String, with t: String) -> String {
    re.stringByReplacingMatches(in: s, range: range(s), withTemplate: NSRegularExpression.escapedTemplate(for: t))
  }
  func replace(_ s: String, _ f: ([String]) -> String) -> String {
    let ns = s as NSString
    var out = ""; var last = 0
    for m in re.matches(in: s, range: range(s)) {
      out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
      out += f(groups(m, s))
      last = m.range.location + m.range.length
    }
    return out + ns.substring(from: last)
  }
  func split(_ s: String) -> [String] {
    let ns = s as NSString
    var parts: [String] = []; var last = 0
    for m in re.matches(in: s, range: range(s)) {
      parts.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
      last = m.range.location + m.range.length
    }
    parts.append(ns.substring(from: last))
    return parts
  }
  private func groups(_ m: NSTextCheckingResult, _ s: String) -> [String] {
    let ns = s as NSString
    return (0..<m.numberOfRanges).map { i in
      let r = m.range(at: i)
      return r.location == NSNotFound ? "" : ns.substring(with: r)
    }
  }
}

enum FileKind { case csv, xlsx, html, pdf, xlsBinary, unknown }

enum StatementReaders {
  static func detect(_ data: Data) -> FileKind {
    let b = [UInt8](data.prefix(4096))
    func at(_ i: Int) -> Int { i < b.count ? Int(b[i]) : -1 }
    if at(0) == 0x25, at(1) == 0x50, at(2) == 0x44, at(3) == 0x46 { return .pdf }
    if at(0) == 0x50, at(1) == 0x4b, at(2) == 0x03, at(3) == 0x04 { return .xlsx }
    if at(0) == 0xd0, at(1) == 0xcf, at(2) == 0x11, at(3) == 0xe0 { return .xlsBinary }
    let head = String(decoding: b.map { $0 }, as: Unicode.ASCII.self).lowercased()
    let latin = String(b.map { Character(Unicode.Scalar($0)) }).lowercased()
    if Rx("<(html|table)\\b").test(head) || Rx("<(html|table)\\b").test(latin) { return .html }
    if Rx("[\\x00-\\x08\\x0e-\\x1f]").test(latin.replacingOccurrences(of: "\u{00ef}\u{00bb}\u{00bf}", with: "")) { return .unknown }
    return .csv
  }

  /// Text of a file: UTF-8, else Latin-1 (old bank exports).
  static func text(_ data: Data) -> String {
    String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
  }

  private static func detectDelimiter(_ text: String) -> Character {
    let lines = Rx("\\r?\\n").split(text).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.prefix(30)
    var best: Character = ","; var bestScore = -1
    for d in [",", ";", "\t", "|"] as [Character] {
      let counts = lines.map { l -> Int in
        var n = 0; var q = false
        for ch in l { if ch == "\"" { q.toggle() } else if ch == d && !q { n += 1 } }
        return n
      }
      let withCols = counts.filter { $0 > 0 }
      let freq = Dictionary(grouping: withCols, by: { $0 }).mapValues(\.count)
      let mode = freq.max { a, b in a.value != b.value ? a.value < b.value : a.key > b.key }?.key ?? 0
      let score = withCols.filter { $0 == mode }.count * min(mode, 12)
      if score > bestScore { bestScore = score; best = d }
    }
    return best
  }

  static func csv(_ text: String, delimiter: Character? = nil) -> Sheet {
    var src = text
    if src.hasPrefix("\u{FEFF}") { src.removeFirst() }
    let d = delimiter ?? detectDelimiter(src)
    // Unicode scalars: "\r\n" is one Character in Swift.
    let chars = Array(src.unicodeScalars)
    let dq: Unicode.Scalar = "\"", cr: Unicode.Scalar = "\r", lf: Unicode.Scalar = "\n"
    let ds = d.unicodeScalars.first!
    var rows: Sheet = []; var row: [String] = []; var cell = String.UnicodeScalarView(); var quoted = false
    var i = 0
    func cellBlank() -> Bool { String(cell).trimmingCharacters(in: .whitespaces).isEmpty }
    while i < chars.count {
      let ch = chars[i]
      if quoted {
        if ch == dq { if i + 1 < chars.count && chars[i + 1] == dq { cell.append(dq); i += 1 } else { quoted = false } } else { cell.append(ch) }
      } else if ch == dq && cellBlank() { quoted = true; cell = String.UnicodeScalarView() }
      else if ch == ds { row.append(String(cell)); cell = String.UnicodeScalarView() }
      else if ch == lf || ch == cr {
        if ch == cr && i + 1 < chars.count && chars[i + 1] == lf { i += 1 }
        row.append(String(cell)); rows.append(row); row = []; cell = String.UnicodeScalarView()
      } else { cell.append(ch) }
      i += 1
    }
    if !cell.isEmpty || !row.isEmpty { row.append(String(cell)); rows.append(row) }
    return rows.map { $0.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }.filter { $0.contains { !$0.isEmpty } }
  }

  private static let entities = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " "]
  static func decodeEntities(_ s: String) -> String {
    Rx("&(#x[0-9a-f]+|#\\d+|[a-z]+);").replace(s) { g in
      let e = g[1]
      if e.hasPrefix("#") {
        let lower = e.lowercased()
        let code = lower.hasPrefix("#x") ? Int(lower.dropFirst(2), radix: 16) : Int(e.dropFirst())
        if let code, let u = Unicode.Scalar(code) { return String(Character(u)) }
        return g[0]
      }
      return entities[e.lowercased()] ?? g[0]
    }
  }
  static func textContent(_ fragment: String) -> String {
    let noTags = Rx("<[^>]*>").replace(Rx("<br\\s*/?>").replace(fragment, with: " "), with: "")
    return Rx("\\s+").replace(decodeEntities(noTags), with: " ").trimmingCharacters(in: .whitespaces)
  }

  static func html(_ html: String) -> Sheet {
    var best: Sheet = []
    for table in Rx("<table\\b[\\s\\S]*?</table>").all(html) {
      var rows: Sheet = []
      for tr in Rx("<tr\\b[\\s\\S]*?</tr>").all(table[0]) {
        var cells: [String] = []
        for c in Rx("<t[dh]\\b[^>]*>[\\s\\S]*?</t[dh]>").all(tr[0]) {
          let span = Int(Rx("colspan=\"?(\\d+)").first(c[0])?[1] ?? "1") ?? 1
          cells.append(textContent(c[0]))
          if span > 1 { cells += Array(repeating: "", count: span - 1) }
        }
        if cells.contains(where: { !$0.isEmpty }) { rows.append(cells) }
      }
      if rows.count > best.count { best = rows }
    }
    return best
  }

  private static func attr(_ tag: String, _ name: String) -> String? { Rx("\\b\(name)=\"([^\"]*)\"", caseInsensitive: false).first(tag)?[1] }
  private static func columnIndex(_ ref: String) -> Int {
    let letters = Rx("^[A-Z]+", caseInsensitive: false).first(ref)?[0] ?? "A"
    return letters.unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 } - 1
  }

  static func xlsx(_ data: Data) -> Sheet {
    let files = Zip.entries(data) { $0.hasPrefix("xl/") }
    func text(_ n: String) -> String { files[n].map { String(decoding: $0, as: UTF8.self) } ?? "" }
    let workbook = text("xl/workbook.xml")
    let firstRel = attr(Rx("<sheet\\b[^>]*>", caseInsensitive: false).first(workbook)?[0] ?? "", "r:id")
    var target = "worksheets/sheet1.xml"
    for rel in Rx("<Relationship\\b[^>]*>", caseInsensitive: false).all(text("xl/_rels/workbook.xml.rels")) where attr(rel[0], "Id") == firstRel {
      target = Rx("^/?xl/", caseInsensitive: false).replace(attr(rel[0], "Target") ?? target, with: "")
    }
    let shared = Rx("<si>[\\s\\S]*?</si>", caseInsensitive: false).all(text("xl/sharedStrings.xml")).map { si in
      Rx("<t\\b[^>]*>([\\s\\S]*?)</t>", caseInsensitive: false).all(si[0]).map { decodeEntities($0[1]) }.joined()
    }
    var sheet: Sheet = []
    for rowXml in Rx("<row\\b[\\s\\S]*?</row>", caseInsensitive: false).all(text("xl/\(target)")) {
      var row: [String] = []
      for cell in Rx("<c\\b[^>]*/>|<c\\b[\\s\\S]*?</c>", caseInsensitive: false).all(rowXml[0]) {
        let open = Rx("<c\\b[^>]*>", caseInsensitive: false).first(cell[0])?[0] ?? cell[0]
        let ref = attr(open, "r"), type = attr(open, "t")
        let v = Rx("<v>([\\s\\S]*?)</v>", caseInsensitive: false).first(cell[0])?[1]
        var value = ""
        if type == "s", let v, let idx = Int(v.trimmingCharacters(in: .whitespaces)), idx < shared.count { value = shared[idx] }
        else if type == "inlineStr" { value = textContent(Rx("<is>([\\s\\S]*?)</is>", caseInsensitive: false).first(cell[0])?[1] ?? "") }
        else if let v { value = decodeEntities(v) }
        let index = ref.map(columnIndex) ?? row.count
        while row.count < index { row.append("") }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if row.count == index { row.append(trimmed) } else { row[index] = trimmed }
      }
      if row.contains(where: { !$0.isEmpty }) { sheet.append(row) }
    }
    return sheet
  }
}

/// Minimal ZIP reader (stored + deflate) for .xlsx files, using Apple's Compression framework.
enum Zip {
  static func entries(_ data: Data, include: (String) -> Bool) -> [String: Data] {
    let b = [UInt8](data)
    func u16(_ o: Int) -> Int { o + 1 < b.count ? Int(b[o]) | Int(b[o + 1]) << 8 : 0 }
    func u32(_ o: Int) -> Int { o + 3 < b.count ? u16(o) | u16(o + 2) << 16 : 0 }
    // End of central directory: last occurrence of PK\x05\x06.
    var eocd = -1
    var i = b.count - 22
    while i >= max(0, b.count - 65_557) { if u32(i) == 0x06054b50 { eocd = i; break }; i -= 1 }
    guard eocd >= 0 else { return [:] }
    var p = u32(eocd + 16)
    let count = u16(eocd + 10)
    var out: [String: Data] = [:]
    for _ in 0..<count {
      guard u32(p) == 0x02014b50 else { break }
      let method = u16(p + 10), csize = u32(p + 20), usize = u32(p + 24)
      let nlen = u16(p + 28), elen = u16(p + 30), clen = u16(p + 32), local = u32(p + 42)
      let name = String(decoding: b[(p + 46)..<min(b.count, p + 46 + nlen)], as: UTF8.self)
      p += 46 + nlen + elen + clen
      guard include(name), u32(local) == 0x04034b50 else { continue }
      let start = local + 30 + u16(local + 26) + u16(local + 28)
      guard start + csize <= b.count else { continue }
      let compressed = Array(b[start..<(start + csize)])
      if method == 0 { out[name] = Data(compressed) }
      else if method == 8, usize > 0 {
        var dst = [UInt8](repeating: 0, count: usize)
        let n = compressed.withUnsafeBufferPointer { src in
          compression_decode_buffer(&dst, usize, src.baseAddress!, csize, nil, COMPRESSION_ZLIB)
        }
        if n > 0 { out[name] = Data(dst.prefix(n)) }
      }
    }
    return out
  }
}

/// A positioned run of PDF text from pdf.js (points; y grows downwards).
struct TextItem: Codable { var str: String; var x, y, w, h: Double; var page: Int }

enum PdfLayout {
  private final class Cell { var text: String; let x0: Double; var x1: Double; init(_ t: String, _ a: Double, _ b: Double) { text = t; x0 = a; x1 = b } }
  private final class Line { let page: Int; let y: Double; var cells: [Cell] = []; init(_ p: Int, _ y: Double) { page = p; self.y = y } }
  private static let headerWords = Rx("\\b(date|narration|description|particulars|details|remarks|debit|credit|withdrawal|deposit|balance|amount|dr|cr|cheque|chq|ref)\\b")
  private static let dateLike = Rx("^\\d{1,2}[-/. ](\\d{1,2}|[a-z]{3})[-/. ]\\d{2,4}$|^\\d{4}-\\d{2}-\\d{2}$|^\\d{1,2} [a-z]{3},? \\d{2,4}$")
  private static let structuralHeader = Rx("date|debit|credit|withdraw|deposit|amount|balance|\\bdr\\b|\\bcr\\b")

  private static func lines(_ items: [TextItem]) -> [Line] {
    let sorted = items.filter { !$0.str.trimmingCharacters(in: .whitespaces).isEmpty }
      .sorted { ($0.page, $0.y, $0.x) < ($1.page, $1.y, $1.x) }
    var lines: [Line] = []
    for item in sorted {
      let tol = max(1.5, item.h * 0.25)
      let target: Line
      if let last = lines.last, last.page == item.page, abs(last.y - item.y) <= tol { target = last }
      else { target = Line(item.page, item.y); lines.append(target) }
      target.cells.append(Cell(item.str, item.x, item.x + item.w))
    }
    for line in lines {
      line.cells.sort { $0.x0 < $1.x0 }
      var merged: [Cell] = []
      for c in line.cells {
        if let prev = merged.last {
          let gap = c.x0 - prev.x1
          let charW = (prev.x1 - prev.x0) / Double(max(prev.text.count, 1))
          if gap < max(charW * 1.2, 3) {
            prev.text = (prev.text + (gap > charW * 0.25 ? " " : "") + c.text).trimmingCharacters(in: .whitespaces)
            prev.x1 = c.x1
            continue
          }
        }
        merged.append(Cell(c.text.trimmingCharacters(in: .whitespaces), c.x0, c.x1))
      }
      line.cells = merged
    }
    return lines
  }

  static func toSheet(_ items: [TextItem]) -> Sheet {
    let lines = lines(items)
    guard let headerIndex = lines.firstIndex(where: { l in l.cells.filter { headerWords.test($0.text) }.count >= 3 }) else {
      return lines.map { $0.cells.map(\.text) }
    }
    let header = lines[headerIndex].cells
    let headerKey = header.map { $0.text.lowercased() }.joined(separator: "|")
    func columnOf(_ c: Cell) -> Int {
      var best = 0; var bestScore = -Double.infinity
      for (i, h) in header.enumerated() {
        let overlap = min(c.x1, h.x1) - max(c.x0, h.x0)
        let distance = abs((c.x0 + c.x1) / 2 - (h.x0 + h.x1) / 2)
        let score = overlap > 0 ? 1000 + overlap : -distance
        if score > bestScore { bestScore = score; best = i }
      }
      return best
    }
    func toRow(_ line: Line) -> [String] {
      var row = Array(repeating: "", count: header.count)
      for cell in line.cells { let col = columnOf(cell); row[col] = row[col].isEmpty ? cell.text : "\(row[col]) \(cell.text)" }
      return row
    }
    let structural = Set(header.indices.filter { structuralHeader.test(header[$0].text) })
    let heights = items.map(\.h).sorted()
    let lineHeight = heights.isEmpty ? 10 : heights[heights.count / 2]
    let maxReach = lineHeight * 3.5

    final class Group { let page: Int; let y: Double; var parts: [(y: Double, row: [String])]; let anchor: Bool
      init(_ p: Int, _ y: Double, _ parts: [(y: Double, row: [String])], _ a: Bool) { page = p; self.y = y; self.parts = parts; anchor = a } }
    var groups: [Group] = []
    var pending: [(page: Int, y: Double, row: [String])] = []
    for line in lines.dropFirst(headerIndex + 1) {
      if line.cells.map({ $0.text.lowercased() }).joined(separator: "|") == headerKey { continue }
      let row = toRow(line)
      let filled = row.indices.filter { !row[$0].isEmpty }
      if row.contains(where: { dateLike.test($0) }) { groups.append(Group(line.page, line.y, [(line.y, row)], true)) }
      else if !filled.isEmpty && filled.allSatisfy({ !structural.contains($0) }) { pending.append((line.page, line.y, row)) }
      else { groups.append(Group(line.page, line.y, [(line.y, row)], false)) }
    }
    for p in pending {
      var best: Group?; var bestD = Double.infinity
      for g in groups where g.anchor && g.page == p.page {
        let d = abs(g.y - p.y) + (g.y > p.y ? 0.01 : 0)
        if d < bestD { bestD = d; best = g }
      }
      if let best, bestD <= maxReach { best.parts.append((p.y, p.row)) } else { groups.append(Group(p.page, p.y, [(p.y, p.row)], false)) }
    }
    // Stable sort like JS (ties keep insertion order).
    let ordered = groups.enumerated().sorted { a, b in
      (a.element.page, a.element.y, a.offset) < (b.element.page, b.element.y, b.offset)
    }.map(\.element)
    var sheet: Sheet = [header.map(\.text)]
    for g in ordered {
      let parts = g.parts.enumerated().sorted { ($0.element.y, $0.offset) < ($1.element.y, $1.offset) }.map(\.element)
      sheet.append(header.indices.map { i in parts.map { $0.row[i] }.filter { !$0.isEmpty }.joined(separator: " ") })
    }
    return sheet
  }
}

enum ColumnRole: String, CaseIterable, Identifiable {
  case date, valueDate, description, reference, debit, credit, amount, drcr, balance, ignore
  var id: String { rawValue }
  var label: String {
    switch self {
    case .date: "Date"; case .valueDate: "Value date"; case .description: "Description"; case .reference: "Reference / cheque"
    case .debit: "Debit (money out)"; case .credit: "Credit (money in)"; case .amount: "Amount"; case .drcr: "Dr / Cr marker"
    case .balance: "Balance"; case .ignore: "Ignore"
    }
  }
}

enum DateOrder: String { case dmy, mdy, ymd }

struct Mapping: Equatable {
  var headerRow: Int
  var columns: [ColumnRole]
  var dateOrder: DateOrder
  /// For a single signed Amount column: true when a positive number is money in.
  var positiveIsIn: Bool
}

struct StatementTemplate: Equatable { let id: String; let name: String; let card: Bool }

/// One statement line. amount is always positive; out = money left the account.
struct StatementRow: Hashable { let line: Int; let date: Date; let description: String; let reference: String; let amount: Int; let out: Bool; let balance: Int? }

enum StatementParser {
  private static let templates: [(StatementTemplate, Rx, Rx?)] = [
    (.init(id: "axis-card", name: "Axis Bank credit card", card: true), Rx("axis bank.*(credit card|card no)|myzone|flipkart axis|axis.*card statement"), Rx("transaction details.*debit/credit")),
    (.init(id: "axis-bank", name: "Axis Bank", card: false), Rx("axis bank"), Rx("tran date.*particulars.*\\bsol\\b")),
    (.init(id: "bob", name: "Bank of Baroda", card: false), Rx("bank of baroda|\\bbob\\b|barb0"), Rx("withdrawal\\s*\\(dr\\).*deposit\\s*\\(cr\\)")),
    (.init(id: "hdfc-card", name: "HDFC Bank credit card", card: true), Rx("hdfc.*credit card"), nil),
    (.init(id: "hdfc", name: "HDFC Bank", card: false), Rx("hdfc bank"), Rx("withdrawal amt.*deposit amt.*closing balance")),
    (.init(id: "icici-card", name: "ICICI Bank credit card", card: true), Rx("icici.*credit card"), nil),
    (.init(id: "icici", name: "ICICI Bank", card: false), Rx("icici bank"), Rx("transaction remarks")),
    (.init(id: "sbi-card", name: "SBI Card", card: true), Rx("sbi card"), nil),
    (.init(id: "sbi", name: "State Bank of India", card: false), Rx("state bank of india|\\bsbi\\b"), Rx("txn date.*ref no\\.?/cheque")),
  ]

  private static let rolePatterns: [(ColumnRole, Rx)] = [
    (.valueDate, Rx("^value\\s*(date|dt)\\b")),
    (.drcr, Rx("^(dr\\s*/\\s*cr|cr\\s*/\\s*dr|debit\\s*/\\s*credit|type|txn type|transaction type|dr\\s*cr)$")),
    (.debit, Rx("withdraw|debit|^dr\\b|\\bdr\\s*(amt|amount)|paid out|money out")),
    (.credit, Rx("deposit|credit|^cr\\b|\\bcr\\s*(amt|amount)|paid in|money in")),
    (.balance, Rx("balance|^bal\\b")),
    (.date, Rx("date|^dt$|^txn\\s*dt$")),
    (.reference, Rx("chq|cheque|ref|utr|instrument")),
    (.description, Rx("narration|description|particulars|details|remarks|transaction$|merchant|payee")),
    (.amount, Rx("amount|amt|inr|₹")),
  ]
  private static let dateCell = Rx("^\\d{1,2}[-/. ](\\d{1,2}|[a-z]{3,9})[-/. ,]*\\d{2,4}|^\\d{4}-\\d{1,2}-\\d{1,2}|^\\d{5}(\\.\\d+)?$")
  private static let ws = Rx("\\s+")

  static func guessRole(_ header: String) -> ColumnRole {
    let h = ws.replace(header, with: " ").trimmingCharacters(in: .whitespaces)
    if h.isEmpty { return .ignore }
    return rolePatterns.first { $0.1.test(h) }?.0 ?? .ignore
  }

  static func detectHeaderRow(_ sheet: Sheet) -> Int {
    var best = -1, bestHits = 2
    for i in 0..<min(sheet.count, 60) {
      let hits = Set(sheet[i].map(guessRole).filter { $0 != .ignore }).count
      let next = sheet[(i + 1)..<min(sheet.count, i + 6)]
      if hits > bestHits && next.contains(where: { r in r.contains { dateCell.test($0.trimmingCharacters(in: .whitespaces)) } }) { best = i; bestHits = hits }
    }
    return best
  }

  static func guessColumns(_ header: [String]) -> [ColumnRole] {
    var used = Set<ColumnRole>()
    let roles = header.map { h -> ColumnRole in
      let r = guessRole(h)
      if r == .ignore || used.contains(r) { return .ignore }
      used.insert(r); return r
    }
    if roles.contains(.debit) && roles.contains(.credit) { return roles.map { $0 == .amount ? .ignore : $0 } }
    return roles
  }

  static func detectTemplate(_ sheet: Sheet, headerRow: Int? = nil) -> StatementTemplate? {
    let hr = headerRow ?? detectHeaderRow(sheet)
    let preamble = sheet.prefix(max(hr, 0)).map { $0.joined(separator: " ") }.joined(separator: " ")
    let header = hr >= 0 ? sheet[hr].joined(separator: " ") : ""
    if !preamble.isEmpty, let t = templates.first(where: { $0.1.test(preamble) }) { return t.0 }
    return templates.first { $0.2?.test(header) == true }?.0
  }

  private static let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6, "jul": 7, "aug": 8, "sep": 9, "sept": 9, "oct": 10, "nov": 11, "dec": 12]
  private static func month(_ name: String) -> Int? { let l = name.lowercased(); return months[String(l.prefix(4))] ?? months[String(l.prefix(3))] }

  /// Local time (noon when there's no time), or nil.
  static func parseDate(_ value: String, order: DateOrder = .dmy, calendar: Calendar = .current) -> Date? {
    let s = value.trimmingCharacters(in: .whitespaces)
    if s.isEmpty { return nil }
    func at(_ y0: Int, _ m: Int, _ d: Int, _ hh: Int = 12, _ mm: Int = 0) -> Date? {
      let y = y0 < 100 ? 2000 + y0 : y0
      guard (1...12).contains(m), (1...31).contains(d), (1990...2100).contains(y) else { return nil }
      guard let date = calendar.date(from: DateComponents(year: y, month: m, day: d, hour: min(max(hh, 0), 23), minute: min(max(mm, 0), 59))),
            calendar.component(.month, from: date) == m, calendar.component(.day, from: date) == d else { return nil }
      return date
    }
    if Rx("^\\d{5}(\\.\\d+)?$").test(s) {
      let serial = Double(s) ?? 0
      guard serial >= 30000, serial <= 80000 else { return nil }
      var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
      let base = utc.date(from: DateComponents(year: 1899, month: 12, day: 30))!
      let d = utc.date(byAdding: .day, value: Int(serial), to: base)!
      let c = utc.dateComponents([.year, .month, .day], from: d)
      return at(c.year!, c.month!, c.day!)
    }
    var hh = 12, mm = 0
    if let t = Rx("(\\d{1,2}):(\\d{2})(?::\\d{2})?\\s*(am|pm)?").first(s) {
      let h = Int(t[1]) ?? 12, ap = t[3].lowercased()
      hh = ap.isEmpty ? h : h % 12 + (ap == "pm" ? 12 : 0)
      mm = Int(t[2]) ?? 0
    }
    if let g = Rx("^(\\d{4})[-/.](\\d{1,2})[-/.](\\d{1,2})").first(s) { return at(Int(g[1])!, Int(g[2])!, Int(g[3])!, hh, mm) }
    if let g = Rx("^(\\d{1,2})[-/. ]*([a-z]{3,9})[-/. ,]*(\\d{2,4})").first(s), let m = month(g[2]) { return at(Int(g[3])!, m, Int(g[1])!, hh, mm) }
    if let g = Rx("^([a-z]{3,9})[-/. ]+(\\d{1,2}),?[-/. ]+(\\d{2,4})").first(s), let m = month(g[1]) { return at(Int(g[3])!, m, Int(g[2])!, hh, mm) }
    if let g = Rx("^(\\d{1,2})[-/.](\\d{1,2})[-/.](\\d{2,4})").first(s) {
      let a = Int(g[1])!, b = Int(g[2])!, y = Int(g[3])!
      return order == .mdy ? at(y, a, b, hh, mm) : at(y, b, a, hh, mm)
    }
    return nil
  }

  /// Signed paise and a Dr/Cr marker ("d"/"c"). Blank, "-" and 0 → nil.
  static func parseAmount(_ value: String) -> (paise: Int, marker: Character?)? {
    var s = ws.replace(value, with: " ").trimmingCharacters(in: .whitespaces)
    if s.isEmpty || Rx("^[-–—]$").test(s) { return nil }
    var marker: Character?
    if let r = Rx("(?<![a-z])(dr|cr|debit|credit)\\.?$").firstRange(s), let g = Rx("(?<![a-z])(dr|cr|debit|credit)\\.?$").first(s) {
      marker = g[1].lowercased().hasPrefix("d") ? "d" : "c"
      s = (s as NSString).substring(to: r.location).trimmingCharacters(in: .whitespaces)
    }
    var negative = false
    if s.count >= 2, s.hasPrefix("("), s.hasSuffix(")") { negative = true; s = String(s.dropFirst().dropLast()) }
    s = Rx("\\s*(inr)$").replace(Rx("^(inr|rs\\.?|₹)\\s*").replace(s, with: ""), with: "")
    if s.hasPrefix("-") { negative.toggle(); s.removeFirst() } else if s.hasPrefix("+") { s.removeFirst() }
    guard Rx("^[\\d,]*\\.?\\d*$").test(s), s.contains(where: \.isNumber) else { return nil }
    let parts = s.replacingOccurrences(of: ",", with: "").split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    guard let whole = Int(parts[0].isEmpty ? "0" : parts[0]) else { return nil }
    let fracRaw = parts.count > 1 ? parts[1] : ""
    let frac = fracRaw.count > 2 ? Int((Double("0.\(fracRaw)")! * 100).rounded()) : Int(fracRaw.padding(toLength: 2, withPad: "0", startingAt: 0))!
    let paise = whole * 100 + frac
    if paise == 0 { return nil }
    return (negative ? -paise : paise, marker)
  }

  static func detectMapping(_ sheet: Sheet, template: StatementTemplate?, cardAccount: Bool) -> Mapping? {
    let hr = detectHeaderRow(sheet)
    guard hr >= 0 else { return nil }
    let columns = guessColumns(sheet[hr])
    guard let dateCol = columns.firstIndex(of: .date) else { return nil }
    let samples = sheet[(hr + 1)..<min(sheet.count, hr + 60)].map { dateCol < $0.count ? $0[dateCol] : "" }
    func score(_ o: DateOrder) -> Int { samples.filter { parseDate($0, order: o) != nil }.count }
    let order: DateOrder = score(.dmy) >= score(.mdy) ? .dmy : .mdy
    let card = template?.card ?? cardAccount
    return Mapping(headerRow: hr, columns: columns, dateOrder: order, positiveIsIn: !card)
  }

  static func extractRows(_ sheet: Sheet, _ m: Mapping) -> [StatementRow] {
    func col(_ r: ColumnRole) -> Int { m.columns.firstIndex(of: r) ?? -1 }
    let dateC = col(.date), descC = col(.description), refC = col(.reference), debitC = col(.debit), creditC = col(.credit)
    let amountC = col(.amount), drcrC = col(.drcr), balC = col(.balance)
    func cell(_ row: [String], _ i: Int) -> String { i >= 0 && i < row.count ? row[i].trimmingCharacters(in: .whitespaces) : "" }
    var out: [StatementRow] = []
    guard m.headerRow + 1 <= sheet.count else { return [] }
    for (i, row) in sheet[(m.headerRow + 1)...].enumerated() {
      guard let date = parseDate(cell(row, dateC), order: m.dateOrder) else { continue }
      var amount = 0; var isOut: Bool?
      let debit = parseAmount(cell(row, debitC)), credit = parseAmount(cell(row, creditC))
      if debit != nil || credit != nil {
        let d = abs(debit?.paise ?? 0), c = abs(credit?.paise ?? 0)
        if d >= c { amount = d; isOut = true } else { amount = c; isOut = false }
      } else if let a = parseAmount(cell(row, amountC)) {
        amount = abs(a.paise)
        let dc = cell(row, drcrC)
        let marker: Character? = a.marker ?? (Rx("^(d|dr|debit|withdrawal)").test(dc) ? "d" : Rx("^(c|cr|credit|deposit)").test(dc) ? "c" : nil)
        if let marker { isOut = marker == "d" } else if a.paise < 0 { isOut = m.positiveIsIn } else { isOut = !m.positiveIsIn }
      }
      guard let dirOut = isOut, amount > 0 else { continue }
      let bal = parseAmount(cell(row, balC))
      var description = cell(row, descC)
      if description.isEmpty {
        description = row.enumerated().filter { j, c in j != dateC && !c.isEmpty && !Rx("^[\\d,.\\s()-]+$").test(c) }.map(\.element).joined(separator: " ")
      }
      out.append(StatementRow(line: m.headerRow + 1 + i, date: date, description: ws.replace(description, with: " ").trimmingCharacters(in: .whitespaces),
                              reference: cell(row, refC), amount: amount, out: dirOut,
                              balance: bal.map { $0.marker == "d" ? -abs($0.paise) : $0.paise }))
    }
    return out
  }

  static func balanceMismatches(_ rows: [StatementRow]) -> Int? {
    let wb = rows.filter { $0.balance != nil }
    guard wb.count >= 2 else { return nil }
    func count(_ l: [StatementRow]) -> Int { (1..<l.count).filter { i in l[i - 1].balance! + (l[i].out ? -l[i].amount : l[i].amount) != l[i].balance }.count }
    return min(count(wb), count(wb.reversed()))
  }

  private static let bankWords: [String: Rx] = [
    "axis-bank": Rx("axis"), "axis-card": Rx("axis|myzone|flipkart|ace|neo|magnus"), "bob": Rx("baroda|\\bbob\\b"),
    "hdfc": Rx("hdfc"), "hdfc-card": Rx("hdfc|regalia|millennia|swiggy|tata neu|infinia"), "icici": Rx("icici"),
    "icici-card": Rx("icici|amazon pay|coral|sapphiro"), "sbi": Rx("sbi|state bank"), "sbi-card": Rx("sbi|simplyclick|cashback|elite"),
  ]
  static func guessAccount(_ accounts: [Account], _ t: StatementTemplate?) -> Account? {
    let active = accounts.filter { $0.archivedAt == nil }
    guard let t else { return active.first { $0.type == .bank } ?? active.first }
    let word = bankWords[t.id]
    let same = active.filter { t.card ? $0.type == .card : $0.type != .card }
    return same.first { word?.test("\($0.name) \($0.institution ?? "")") == true } ?? same.first ?? active.first
  }
}
