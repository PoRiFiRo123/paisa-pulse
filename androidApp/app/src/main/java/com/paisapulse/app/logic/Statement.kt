package com.paisapulse.app.logic

import java.time.LocalDate
import java.time.LocalDateTime
import java.util.zip.ZipInputStream

// Statement import, ported from the RN app (src/features/import) and kept identical to the iPhone app's
// Statement.swift: readers turn a file into a Sheet (rows of text cells), the normaliser finds the
// header, columns, dates and amounts.

typealias Sheet = List<List<String>>

enum class FileKind { Csv, Xlsx, Html, Pdf, XlsBinary, Unknown }

object StatementReaders {
  /** By bytes, not extension (many ".xls" downloads are HTML). */
  fun detect(bytes: ByteArray): FileKind {
    fun b(i: Int) = if (i < bytes.size) bytes[i].toInt() and 0xff else -1
    if (b(0) == 0x25 && b(1) == 0x50 && b(2) == 0x44 && b(3) == 0x46) return FileKind.Pdf
    if (b(0) == 0x50 && b(1) == 0x4b && b(2) == 0x03 && b(3) == 0x04) return FileKind.Xlsx
    if (b(0) == 0xd0 && b(1) == 0xcf && b(2) == 0x11 && b(3) == 0xe0) return FileKind.XlsBinary
    val head = String(bytes, 0, minOf(bytes.size, 4096), Charsets.ISO_8859_1).lowercase()
    if (Regex("<(html|table)\\b").containsMatchIn(head)) return FileKind.Html
    if (Regex("[\\x00-\\x08\\x0e-\\x1f]").containsMatchIn(head.replace("\u00ef\u00bb\u00bf", ""))) return FileKind.Unknown
    return FileKind.Csv
  }

  private val delimiters = listOf(',', ';', '\t', '|')

  private fun detectDelimiter(text: String): Char {
    val lines = text.split(Regex("\r?\n")).filter { it.isNotBlank() }.take(30)
    var best = ','; var bestScore = -1
    for (d in delimiters) {
      val counts = lines.map { l -> var n = 0; var q = false; for (ch in l) { if (ch == '"') q = !q else if (ch == d && !q) n++ }; n }
      val withCols = counts.filter { it > 0 }
      val mode = withCols.groupingBy { it }.eachCount().maxByOrNull { it.value }?.key ?: 0
      val score = withCols.count { it == mode } * minOf(mode, 12)
      if (score > bestScore) { bestScore = score; best = d }
    }
    return best
  }

  fun csv(text: String, delimiter: Char? = null): Sheet {
    val src = text.removePrefix("\uFEFF")
    val d = delimiter ?: detectDelimiter(src)
    val rows = mutableListOf<List<String>>()
    var row = mutableListOf<String>(); val cell = StringBuilder(); var quoted = false
    var i = 0
    while (i < src.length) {
      val ch = src[i]
      if (quoted) {
        if (ch == '"') { if (i + 1 < src.length && src[i + 1] == '"') { cell.append('"'); i++ } else quoted = false } else cell.append(ch)
      } else if (ch == '"' && cell.isBlank()) { quoted = true; cell.clear() }
      else if (ch == d) { row.add(cell.toString()); cell.clear() }
      else if (ch == '\n' || ch == '\r') {
        if (ch == '\r' && i + 1 < src.length && src[i + 1] == '\n') i++
        row.add(cell.toString()); rows.add(row); row = mutableListOf(); cell.clear()
      } else cell.append(ch)
      i++
    }
    if (cell.isNotEmpty() || row.isNotEmpty()) { row.add(cell.toString()); rows.add(row) }
    return rows.map { r -> r.map { it.trim() } }.filter { r -> r.any { it.isNotEmpty() } }
  }

  private val entities = mapOf("amp" to "&", "lt" to "<", "gt" to ">", "quot" to "\"", "apos" to "'", "nbsp" to " ")
  fun decodeEntities(s: String): String = Regex("&(#x[0-9a-fA-F]+|#\\d+|[a-zA-Z]+);").replace(s) { m ->
    val e = m.groupValues[1]
    if (e.startsWith("#")) {
      val code = if (e.length > 1 && e[1].lowercaseChar() == 'x') e.drop(2).toIntOrNull(16) else e.drop(1).toIntOrNull()
      code?.let { String(Character.toChars(it)) } ?: m.value
    } else entities[e.lowercase()] ?: m.value
  }
  fun textContent(fragment: String): String =
    decodeEntities(fragment.replace(Regex("<br\\s*/?>", RegexOption.IGNORE_CASE), " ").replace(Regex("<[^>]*>"), "")).replace(Regex("\\s+"), " ").trim()

  /** The largest HTML table (banks' ".xls" downloads). */
  fun html(html: String): Sheet {
    var best: Sheet = emptyList()
    val ic = setOf(RegexOption.IGNORE_CASE)
    for (table in Regex("<table\\b[\\s\\S]*?</table>", ic).findAll(html)) {
      val rows = mutableListOf<List<String>>()
      for (tr in Regex("<tr\\b[\\s\\S]*?</tr>", ic).findAll(table.value)) {
        val cells = mutableListOf<String>()
        for (c in Regex("<t[dh]\\b[^>]*>[\\s\\S]*?</t[dh]>", ic).findAll(tr.value)) {
          val span = Regex("colspan=\"?(\\d+)", ic).find(c.value)?.groupValues?.get(1)?.toIntOrNull() ?: 1
          cells.add(textContent(c.value)); repeat(span - 1) { cells.add("") }
        }
        if (cells.any { it.isNotEmpty() }) rows.add(cells)
      }
      if (rows.size > best.size) best = rows
    }
    return best
  }

  private fun attr(tag: String, name: String) = Regex("\\b$name=\"([^\"]*)\"").find(tag)?.groupValues?.get(1)
  private fun columnIndex(ref: String): Int {
    val letters = Regex("^[A-Z]+").find(ref)?.value ?: "A"
    return letters.fold(0) { n, c -> n * 26 + (c - 'A' + 1) } - 1
  }

  /** First worksheet of an .xlsx. */
  fun xlsx(bytes: ByteArray): Sheet {
    val files = HashMap<String, String>()
    ZipInputStream(bytes.inputStream()).use { zip ->
      while (true) {
        val e = zip.nextEntry ?: break
        if (e.name.startsWith("xl/") && e.name.endsWith(".xml") || e.name.endsWith(".rels")) files[e.name] = zip.readBytes().toString(Charsets.UTF_8)
      }
    }
    fun text(n: String) = files[n] ?: ""
    val workbook = text("xl/workbook.xml")
    val firstRel = attr(Regex("<sheet\\b[^>]*>").find(workbook)?.value ?: "", "r:id")
    var target = "worksheets/sheet1.xml"
    for (rel in Regex("<Relationship\\b[^>]*>").findAll(text("xl/_rels/workbook.xml.rels"))) {
      if (attr(rel.value, "Id") == firstRel) target = (attr(rel.value, "Target") ?: target).replace(Regex("^/?xl/"), "")
    }
    val shared = Regex("<si>[\\s\\S]*?</si>").findAll(text("xl/sharedStrings.xml")).map { si ->
      Regex("<t\\b[^>]*>([\\s\\S]*?)</t>").findAll(si.value).joinToString("") { decodeEntities(it.groupValues[1]) }
    }.toList()
    val sheet = mutableListOf<List<String>>()
    for (rowXml in Regex("<row\\b[\\s\\S]*?</row>").findAll(text("xl/$target"))) {
      val row = mutableListOf<String>()
      for (cell in Regex("<c\\b[^>]*/>|<c\\b[\\s\\S]*?</c>").findAll(rowXml.value)) {
        val open = Regex("<c\\b[^>]*>").find(cell.value)?.value ?: cell.value
        val ref = attr(open, "r"); val type = attr(open, "t")
        val v = Regex("<v>([\\s\\S]*?)</v>").find(cell.value)?.groupValues?.get(1)
        val value = when {
          type == "s" && v != null -> shared.getOrNull(v.trim().toIntOrNull() ?: -1) ?: ""
          type == "inlineStr" -> textContent(Regex("<is>([\\s\\S]*?)</is>").find(cell.value)?.groupValues?.get(1) ?: "")
          v != null -> decodeEntities(v)
          else -> ""
        }
        val index = ref?.let { columnIndex(it) } ?: row.size
        while (row.size < index) row.add("")
        if (row.size == index) row.add(value.trim()) else row[index] = value.trim()
      }
      if (row.any { it.isNotEmpty() }) sheet.add(row)
    }
    return sheet
  }
}

/** A positioned run of PDF text from pdf.js (points; y grows downwards). */
data class TextItem(val str: String, val x: Double, val y: Double, val w: Double, val h: Double, val page: Int)

object PdfLayout {
  private class Cell(var text: String, val x0: Double, var x1: Double)
  private class Line(val page: Int, val y: Double, var cells: MutableList<Cell>)
  private val headerWords = Regex("\\b(date|narration|description|particulars|details|remarks|debit|credit|withdrawal|deposit|balance|amount|dr|cr|cheque|chq|ref)\\b", RegexOption.IGNORE_CASE)
  private val dateLike = Regex("^\\d{1,2}[-/. ](\\d{1,2}|[a-z]{3})[-/. ]\\d{2,4}$|^\\d{4}-\\d{2}-\\d{2}$|^\\d{1,2} [a-z]{3},? \\d{2,4}$", RegexOption.IGNORE_CASE)
  private val structuralHeader = Regex("date|debit|credit|withdraw|deposit|amount|balance|\\bdr\\b|\\bcr\\b", RegexOption.IGNORE_CASE)

  private fun lines(items: List<TextItem>): List<Line> {
    val sorted = items.filter { it.str.isNotBlank() }.sortedWith(compareBy({ it.page }, { it.y }, { it.x }))
    val lines = mutableListOf<Line>()
    for (item in sorted) {
      val last = lines.lastOrNull()
      val tol = maxOf(1.5, item.h * 0.25)
      val target = if (last != null && last.page == item.page && Math.abs(last.y - item.y) <= tol) last else Line(item.page, item.y, mutableListOf()).also { lines.add(it) }
      target.cells.add(Cell(item.str, item.x, item.x + item.w))
    }
    for (line in lines) {
      line.cells.sortBy { it.x0 }
      val merged = mutableListOf<Cell>()
      for (c in line.cells) {
        val prev = merged.lastOrNull()
        val gap = if (prev != null) c.x0 - prev.x1 else Double.POSITIVE_INFINITY
        val charW = if (prev != null) (prev.x1 - prev.x0) / maxOf(prev.text.length, 1) else 0.0
        if (prev != null && gap < maxOf(charW * 1.2, 3.0)) {
          prev.text = (prev.text + (if (gap > charW * 0.25) " " else "") + c.text).trim(); prev.x1 = c.x1
        } else merged.add(Cell(c.text.trim(), c.x0, c.x1))
      }
      line.cells = merged
    }
    return lines
  }

  fun toSheet(items: List<TextItem>): Sheet {
    val lines = lines(items)
    val headerIndex = lines.indexOfFirst { l -> l.cells.count { headerWords.containsMatchIn(it.text) } >= 3 }
    if (headerIndex < 0) return lines.map { l -> l.cells.map { it.text } }
    val header = lines[headerIndex].cells
    val headerKey = header.joinToString("|") { it.text.lowercase() }
    fun columnOf(c: Cell): Int {
      var best = 0; var bestScore = Double.NEGATIVE_INFINITY
      header.forEachIndexed { i, h ->
        val overlap = minOf(c.x1, h.x1) - maxOf(c.x0, h.x0)
        val distance = Math.abs((c.x0 + c.x1) / 2 - (h.x0 + h.x1) / 2)
        val score = if (overlap > 0) 1000 + overlap else -distance
        if (score > bestScore) { bestScore = score; best = i }
      }
      return best
    }
    fun toRow(line: Line): MutableList<String> {
      val row = MutableList(header.size) { "" }
      for (cell in line.cells) { val col = columnOf(cell); row[col] = if (row[col].isNotEmpty()) "${row[col]} ${cell.text}" else cell.text }
      return row
    }
    val structural = header.indices.filter { structuralHeader.containsMatchIn(header[it].text) }.toSet()
    val heights = items.map { it.h }.sorted()
    val lineHeight = heights.getOrNull(heights.size / 2) ?: 10.0
    val maxReach = lineHeight * 3.5

    class Part(val y: Double, val row: List<String>)
    class Group(val page: Int, val y: Double, val parts: MutableList<Part>, val anchor: Boolean)
    val groups = mutableListOf<Group>()
    val pending = mutableListOf<Triple<Int, Double, List<String>>>()
    for (line in lines.drop(headerIndex + 1)) {
      if (line.cells.joinToString("|") { it.text.lowercase() } == headerKey) continue
      val row = toRow(line)
      val filled = row.indices.filter { row[it].isNotEmpty() }
      when {
        row.any { dateLike.matches(it) } -> groups.add(Group(line.page, line.y, mutableListOf(Part(line.y, row)), true))
        filled.isNotEmpty() && filled.all { it !in structural } -> pending.add(Triple(line.page, line.y, row))
        else -> groups.add(Group(line.page, line.y, mutableListOf(Part(line.y, row)), false))
      }
    }
    for ((page, y, row) in pending) {
      var best: Group? = null; var bestD = Double.POSITIVE_INFINITY
      for (g in groups) {
        if (!g.anchor || g.page != page) continue
        val d = Math.abs(g.y - y) + if (g.y > y) 0.01 else 0.0
        if (d < bestD) { bestD = d; best = g }
      }
      if (best != null && bestD <= maxReach) best.parts.add(Part(y, row)) else groups.add(Group(page, y, mutableListOf(Part(y, row)), false))
    }
    groups.sortWith(compareBy({ it.page }, { it.y }))
    val sheet = mutableListOf(header.map { it.text })
    for (g in groups) {
      val parts = g.parts.sortedBy { it.y }
      sheet.add(header.indices.map { i -> parts.map { it.row[i] }.filter { it.isNotEmpty() }.joinToString(" ") })
    }
    return sheet
  }
}

enum class ColumnRole(val label: String) {
  Date("Date"), ValueDate("Value date"), Description("Description"), Reference("Reference / cheque"), Debit("Debit (money out)"),
  Credit("Credit (money in)"), Amount("Amount"), DrCr("Dr / Cr marker"), Balance("Balance"), Ignore("Ignore")
}

enum class DateOrder { Dmy, Mdy, Ymd }

data class Mapping(val headerRow: Int, val columns: List<ColumnRole>, val dateOrder: DateOrder, val positiveIsIn: Boolean)

data class StatementTemplate(val id: String, val name: String, val card: Boolean)

/** One statement line. amount is always positive; out = money left the account. */
data class StatementRow(val line: Int, val date: Long, val description: String, val reference: String, val amount: Long, val out: Boolean, val balance: Long?)

object StatementParser {
  private fun ri(p: String) = Regex(p, RegexOption.IGNORE_CASE)

  private data class T(val t: StatementTemplate, val match: Regex, val header: Regex?)
  private val templates = listOf(
    T(StatementTemplate("axis-card", "Axis Bank credit card", true), ri("axis bank.*(credit card|card no)|myzone|flipkart axis|axis.*card statement"), ri("transaction details.*debit/credit")),
    T(StatementTemplate("axis-bank", "Axis Bank", false), ri("axis bank"), ri("tran date.*particulars.*\\bsol\\b")),
    T(StatementTemplate("bob", "Bank of Baroda", false), ri("bank of baroda|\\bbob\\b|barb0"), ri("withdrawal\\s*\\(dr\\).*deposit\\s*\\(cr\\)")),
    T(StatementTemplate("hdfc-card", "HDFC Bank credit card", true), ri("hdfc.*credit card"), null),
    T(StatementTemplate("hdfc", "HDFC Bank", false), ri("hdfc bank"), ri("withdrawal amt.*deposit amt.*closing balance")),
    T(StatementTemplate("icici-card", "ICICI Bank credit card", true), ri("icici.*credit card"), null),
    T(StatementTemplate("icici", "ICICI Bank", false), ri("icici bank"), ri("transaction remarks")),
    T(StatementTemplate("sbi-card", "SBI Card", true), ri("sbi card"), null),
    T(StatementTemplate("sbi", "State Bank of India", false), ri("state bank of india|\\bsbi\\b"), ri("txn date.*ref no\\.?/cheque")),
  )

  private val rolePatterns = listOf(
    ColumnRole.ValueDate to ri("^value\\s*(date|dt)\\b"),
    ColumnRole.DrCr to ri("^(dr\\s*/\\s*cr|cr\\s*/\\s*dr|debit\\s*/\\s*credit|type|txn type|transaction type|dr\\s*cr)$"),
    ColumnRole.Debit to ri("withdraw|debit|^dr\\b|\\bdr\\s*(amt|amount)|paid out|money out"),
    ColumnRole.Credit to ri("deposit|credit|^cr\\b|\\bcr\\s*(amt|amount)|paid in|money in"),
    ColumnRole.Balance to ri("balance|^bal\\b"),
    ColumnRole.Date to ri("date|^dt$|^txn\\s*dt$"),
    ColumnRole.Reference to ri("chq|cheque|ref|utr|instrument"),
    ColumnRole.Description to ri("narration|description|particulars|details|remarks|transaction$|merchant|payee"),
    ColumnRole.Amount to ri("amount|amt|inr|₹"),
  )
  private val dateCell = ri("^\\d{1,2}[-/. ](\\d{1,2}|[a-z]{3,9})[-/. ,]*\\d{2,4}|^\\d{4}-\\d{1,2}-\\d{1,2}|^\\d{5}(\\.\\d+)?$")

  fun guessRole(header: String): ColumnRole {
    val h = header.replace(Regex("\\s+"), " ").trim()
    if (h.isEmpty()) return ColumnRole.Ignore
    return rolePatterns.firstOrNull { it.second.containsMatchIn(h) }?.first ?: ColumnRole.Ignore
  }

  fun detectHeaderRow(sheet: Sheet): Int {
    var best = -1; var bestHits = 2
    for (i in 0 until minOf(sheet.size, 60)) {
      val hits = sheet[i].map(::guessRole).filter { it != ColumnRole.Ignore }.toSet().size
      if (hits > bestHits && sheet.subList(i + 1, minOf(sheet.size, i + 6)).any { r -> r.any { dateCell.containsMatchIn(it.trim()) } }) { best = i; bestHits = hits }
    }
    return best
  }

  fun guessColumns(header: List<String>): List<ColumnRole> {
    val used = mutableSetOf<ColumnRole>()
    val roles = header.map { h -> val r = guessRole(h); if (r == ColumnRole.Ignore || r in used) ColumnRole.Ignore else { used.add(r); r } }
    return if (ColumnRole.Debit in roles && ColumnRole.Credit in roles) roles.map { if (it == ColumnRole.Amount) ColumnRole.Ignore else it } else roles
  }

  fun detectTemplate(sheet: Sheet, headerRow: Int = detectHeaderRow(sheet)): StatementTemplate? {
    val preamble = sheet.take(maxOf(headerRow, 0)).joinToString(" ") { it.joinToString(" ") }
    val header = if (headerRow >= 0) sheet[headerRow].joinToString(" ") else ""
    return (if (preamble.isNotEmpty()) templates.firstOrNull { it.match.containsMatchIn(preamble) } else null)?.t
      ?: templates.firstOrNull { it.header?.containsMatchIn(header) == true }?.t
  }

  private val months = mapOf("jan" to 1, "feb" to 2, "mar" to 3, "apr" to 4, "may" to 5, "jun" to 6, "jul" to 7, "aug" to 8, "sep" to 9, "sept" to 9, "oct" to 10, "nov" to 11, "dec" to 12)
  private fun month(name: String): Int? { val l = name.lowercase(); return months[l.take(4)] ?: months[l.take(3)] }

  /** Local time (noon when there's no time) as epoch ms, or null. */
  fun parseDate(value: String, order: DateOrder = DateOrder.Dmy): Long? {
    val s = value.trim()
    if (s.isEmpty()) return null
    fun at(y0: Int, m: Int, d: Int, hh: Int = 12, mm: Int = 0): Long? {
      val y = if (y0 < 100) 2000 + y0 else y0
      if (m !in 1..12 || d !in 1..31 || y !in 1990..2100) return null
      return runCatching { LocalDateTime.of(y, m, d, hh.coerceIn(0, 23), mm.coerceIn(0, 59)).atZone(zone).toInstant().toEpochMilli() }.getOrNull()
    }
    if (Regex("^\\d{5}(\\.\\d+)?$").matches(s)) {
      val serial = s.toDouble()
      if (serial < 30000 || serial > 80000) return null
      val d = LocalDate.of(1899, 12, 30).plusDays(serial.toLong())
      return at(d.year, d.monthValue, d.dayOfMonth)
    }
    var hh = 12; var mm = 0
    ri("(\\d{1,2}):(\\d{2})(?::\\d{2})?\\s*(am|pm)?").find(s)?.let { t ->
      val h = t.groupValues[1].toInt(); val ap = t.groupValues[3].lowercase()
      hh = if (ap.isNotEmpty()) h % 12 + if (ap == "pm") 12 else 0 else h
      mm = t.groupValues[2].toInt()
    }
    Regex("^(\\d{4})[-/.](\\d{1,2})[-/.](\\d{1,2})").find(s)?.let { return at(it.groupValues[1].toInt(), it.groupValues[2].toInt(), it.groupValues[3].toInt(), hh, mm) }
    ri("^(\\d{1,2})[-/. ]*([a-z]{3,9})[-/. ,]*(\\d{2,4})").find(s)?.let { n ->
      month(n.groupValues[2])?.let { m -> return at(n.groupValues[3].toInt(), m, n.groupValues[1].toInt(), hh, mm) }
    }
    ri("^([a-z]{3,9})[-/. ]+(\\d{1,2}),?[-/. ]+(\\d{2,4})").find(s)?.let { n ->
      month(n.groupValues[1])?.let { m -> return at(n.groupValues[3].toInt(), m, n.groupValues[2].toInt(), hh, mm) }
    }
    Regex("^(\\d{1,2})[-/.](\\d{1,2})[-/.](\\d{2,4})").find(s)?.let { n ->
      val a = n.groupValues[1].toInt(); val b = n.groupValues[2].toInt(); val y = n.groupValues[3].toInt()
      return if (order == DateOrder.Mdy) at(y, a, b, hh, mm) else at(y, b, a, hh, mm)
    }
    return null
  }

  data class Amount(val paise: Long, val marker: Char?) // 'd' | 'c'

  /** Signed paise: "1,23,456.78", "₹ 1,234", "(120.00)", "-50", "120.00 Dr". Blank, "-", 0 → null. */
  fun parseAmount(value: String): Amount? {
    var s = value.replace(Regex("\\s+"), " ").trim()
    if (s.isEmpty() || Regex("^[-–—]$").matches(s)) return null
    var marker: Char? = null
    ri("(?<![a-z])(dr|cr|debit|credit)\\.?$").find(s)?.let { m -> marker = if (m.groupValues[1].lowercase().startsWith("d")) 'd' else 'c'; s = s.substring(0, m.range.first).trim() }
    var negative = false
    if (s.length >= 2 && s.startsWith("(") && s.endsWith(")")) { negative = true; s = s.substring(1, s.length - 1) }
    s = s.replace(ri("^(inr|rs\\.?|₹)\\s*"), "").replace(ri("\\s*(inr)$"), "")
    if (s.startsWith("-")) { negative = !negative; s = s.drop(1) } else if (s.startsWith("+")) s = s.drop(1)
    if (!Regex("^[\\d,]*\\.?\\d*$").matches(s) || !s.any { it.isDigit() }) return null
    val clean = s.replace(",", "")
    val parts = clean.split(".")
    val whole = parts[0].ifEmpty { "0" }.toLongOrNull() ?: return null
    val fracRaw = parts.getOrNull(1) ?: ""
    val frac = if (fracRaw.length > 2) Math.round(("0.$fracRaw").toDouble() * 100) else (fracRaw.padEnd(2, '0').ifEmpty { "00" }).toLong()
    val paise = whole * 100 + frac
    if (paise == 0L) return null
    return Amount(if (negative) -paise else paise, marker)
  }

  fun detectMapping(sheet: Sheet, template: StatementTemplate?, cardAccount: Boolean): Mapping? {
    val headerRow = detectHeaderRow(sheet)
    if (headerRow < 0) return null
    val columns = guessColumns(sheet[headerRow])
    val dateCol = columns.indexOf(ColumnRole.Date)
    if (dateCol < 0) return null
    val samples = sheet.subList(headerRow + 1, minOf(sheet.size, headerRow + 60)).map { it.getOrNull(dateCol) ?: "" }
    fun score(o: DateOrder) = samples.count { parseDate(it, o) != null }
    val order = if (score(DateOrder.Dmy) >= score(DateOrder.Mdy)) DateOrder.Dmy else DateOrder.Mdy
    val card = template?.card ?: cardAccount
    return Mapping(headerRow, columns, order, positiveIsIn = !card)
  }

  fun extractRows(sheet: Sheet, m: Mapping): List<StatementRow> {
    fun col(r: ColumnRole) = m.columns.indexOf(r)
    val dateC = col(ColumnRole.Date); val descC = col(ColumnRole.Description); val refC = col(ColumnRole.Reference)
    val debitC = col(ColumnRole.Debit); val creditC = col(ColumnRole.Credit); val amountC = col(ColumnRole.Amount)
    val drcrC = col(ColumnRole.DrCr); val balC = col(ColumnRole.Balance)
    fun cell(row: List<String>, i: Int) = if (i >= 0) (row.getOrNull(i) ?: "").trim() else ""
    val out = mutableListOf<StatementRow>()
    sheet.drop(m.headerRow + 1).forEachIndexed { i, row ->
      val date = parseDate(cell(row, dateC), m.dateOrder) ?: return@forEachIndexed
      var amount = 0L; var isOut: Boolean? = null
      val debit = parseAmount(cell(row, debitC)); val credit = parseAmount(cell(row, creditC))
      if (debit != null || credit != null) {
        val d = Math.abs(debit?.paise ?: 0); val c = Math.abs(credit?.paise ?: 0)
        if (d >= c) { amount = d; isOut = true } else { amount = c; isOut = false }
      } else parseAmount(cell(row, amountC))?.let { a ->
        amount = Math.abs(a.paise)
        val dc = cell(row, drcrC)
        val marker = a.marker ?: if (ri("^(d|dr|debit|withdrawal)").containsMatchIn(dc)) 'd' else if (ri("^(c|cr|credit|deposit)").containsMatchIn(dc)) 'c' else null
        isOut = when { marker != null -> marker == 'd'; a.paise < 0 -> m.positiveIsIn; else -> !m.positiveIsIn }
      }
      val dirOut = isOut ?: return@forEachIndexed
      if (amount <= 0) return@forEachIndexed
      val bal = parseAmount(cell(row, balC))
      val description = cell(row, descC).ifEmpty {
        row.filterIndexed { j, c -> j != dateC && c.isNotEmpty() && !Regex("^[\\d,.\\s()-]+$").matches(c) }.joinToString(" ")
      }
      out.add(StatementRow(m.headerRow + 1 + i, date, description.replace(Regex("\\s+"), " ").trim(), cell(row, refC), amount, dirOut,
        bal?.let { if (it.marker == 'd') -Math.abs(it.paise) else it.paise }))
    }
    return out
  }

  /** Rows whose running balance doesn't reconcile (either order), or null without a balance column. */
  fun balanceMismatches(rows: List<StatementRow>): Int? {
    val wb = rows.filter { it.balance != null }
    if (wb.size < 2) return null
    fun count(l: List<StatementRow>) = (1 until l.size).count { i -> l[i - 1].balance!! + (if (l[i].out) -l[i].amount else l[i].amount) != l[i].balance }
    return minOf(count(wb), count(wb.reversed()))
  }

  /** The account a statement most likely belongs to. */
  private val bankWords = mapOf(
    "axis-bank" to ri("axis"), "axis-card" to ri("axis|myzone|flipkart|ace|neo|magnus"), "bob" to ri("baroda|\\bbob\\b"),
    "hdfc" to ri("hdfc"), "hdfc-card" to ri("hdfc|regalia|millennia|swiggy|tata neu|infinia"), "icici" to ri("icici"),
    "icici-card" to ri("icici|amazon pay|coral|sapphiro"), "sbi" to ri("sbi|state bank"), "sbi-card" to ri("sbi|simplyclick|cashback|elite"),
  )
  fun guessAccount(accounts: List<com.paisapulse.app.data.Account>, t: StatementTemplate?): com.paisapulse.app.data.Account? {
    val active = accounts.filter { it.archivedAt == null }
    if (t == null) return active.firstOrNull { it.type == "bank" } ?: active.firstOrNull()
    val word = bankWords[t.id]
    val same = active.filter { if (t.card) it.type == "card" else it.type != "card" }
    return same.firstOrNull { word?.containsMatchIn("${it.name} ${it.institution ?: ""}") == true } ?: same.firstOrNull() ?: active.firstOrNull()
  }
}
