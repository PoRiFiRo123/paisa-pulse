package com.paisapulse.app

import com.paisapulse.app.logic.*
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.TimeZone

/**
 * Statement import and capture parsers against the RN app's output for the same inputs
 * (the golden files in test resources were generated from src/features/import and src/features/capture in IST).
 */
class GoldenTest {
  @Before fun ist() { TimeZone.setDefault(TimeZone.getTimeZone("Asia/Kolkata")) }

  private fun res(name: String) = javaClass.classLoader!!.getResource(name)!!.readText()
  private fun ms(y: Int, mo: Int, d: Int, h: Int, mi: Int = 0) = LocalDateTime.of(y, mo, d, h, mi).atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
  private fun iso(v: Long) = Instant.ofEpochMilli(v).toString().let { if (it.length == 20) it.replace("Z", ".000Z") else it }

  @Test fun statementsMatchTheRnApp() = assertEquals(res("import-golden.txt"), statements())
  @Test fun captureMatchesTheRnApp() = assertEquals(res("capture-golden.txt"), capture())

  private fun statements(): String {
  val fx = res("statements.ts.txt")
  val consts = Regex("export const (\\w+) = `([\\s\\S]*?)`;").findAll(fx).map { it.groupValues[1] to it.groupValues[2] }.sortedBy { it.first }
  val out = mutableListOf<String>()
  for ((name, csv) in consts) {
    val sheet = StatementReaders.csv(csv)
    val t = StatementParser.detectTemplate(sheet)
    val card = name.contains("CARD")
    val m = StatementParser.detectMapping(sheet, t, card)
    val cols = m?.columns?.joinToString(",") { c -> when (c) { ColumnRole.ValueDate -> "valueDate"; ColumnRole.DrCr -> "drcr"; else -> c.name.lowercase() } }
    val order = m?.dateOrder?.name?.lowercase()
    out.add("## $name sheet=${sheet.size}x${sheet.firstOrNull()?.size} template=${t?.id ?: "-"} header=${m?.headerRow} cols=$cols order=$order pos=${m?.let { if (it.positiveIsIn) "in" else "out" }}")
    if (m == null) continue
    val rows = StatementParser.extractRows(sheet, m)
    out.add("mismatch=${StatementParser.balanceMismatches(rows)}")
    val keys = ImportPlan.rowKeys("acc1", rows)
    rows.forEachIndexed { i, r ->
      val n = Narrations.parse(r.description)
      out.add(listOf(r.line, iso(r.date), if (r.out) "out" else "in", r.amount, r.balance ?: "", r.reference, r.description, "=>",
        n.channel, n.payee ?: "", n.upiId ?: "", n.note ?: "", Narrations.suggestCategory(r.description, n.payee, r.out) ?: "", keys[i]).joinToString(" | "))
    }
  }
  val json = res("axis-pdf-items.json")
  val items = Regex("\\{[^{}]*\\}").findAll(json).map { o ->
    fun s(k: String) = Regex("\"$k\":\\s*\"((?:[^\"\\\\]|\\\\.)*)\"").find(o.value)?.groupValues?.get(1)?.replace("\\\"", "\"")?.replace("\\\\", "\\")
    fun d(k: String) = Regex("\"$k\":\\s*(-?[\\d.eE+-]+)").find(o.value)!!.groupValues[1].toDouble()
    TextItem(s("str") ?: "", d("x"), d("y"), d("w"), d("h"), d("page").toInt())
  }.toList()
  out.add("## PDF")
  PdfLayout.toSheet(items).forEach { out.add(it.joinToString(" ¦ ")) }
  for (d in listOf("01-09-2026","01/09/26","1-Sep-2026","01 SEP 26","1 Sept 2026","Sep 1, 2026","2026-09-01","46266","01/09/2026 06:15 PM","31/02/2026","12345"))
    out.add("date $d => ${StatementParser.parseDate(d)?.let { iso(it) } ?: "null"}")
  for (a in listOf("1,23,456.78","₹ 1,234","INR 50","(120.00)","-50","120.00 Dr","1,234.50CR","10.005","","-","0.00","abc"))
    out.add("amt $a => ${StatementParser.parseAmount(a)?.let { "${it.paise} ${when (it.marker) { 'd' -> "dr"; 'c' -> "cr"; else -> "null" }}" } ?: "null"}")
  return out.joinToString("\n") + "\n"
}

  private fun capture(): String {
  val out = mutableListOf<String>()
  val sctx = CaptureContext(listOf(CaptureAccount("axis", "Axis Bank", "bank", "Axis Bank", "5678"), CaptureAccount("bob", "Bank of Baroda", "bank", "Bank of Baroda", "9012"),
    CaptureAccount("card", "Axis MyZone", "card", "Axis Bank", "3307")),
    listOf(CaptureCategory("food", "Food & Dining", "expense", null), CaptureCategory("groceries", "Groceries", "expense", null), CaptureCategory("other", "Other", "income", null)),
    emptyMap(), "axis", ms(2026, 10, 10, 18))
  val shots = listOf(
    listOf("To Swiggy", "₹420", "Completed", "10 Oct 2026, 2:15 pm", "Split with friends", "UPI transaction ID", "424412345678", "To: SWIGGY LIMITED", "swiggy@icici", "From: NISHIT KIRANI (Bank of Baroda)", "Bank of Baroda 9012", "Google transaction ID", "CICAgOCx8aqHGw"),
    listOf("Transaction Successful", "02:15 pm on 09 Oct 2026", "Paid to", "BLINKIT", "blinkit.payu@hdfcbank", "₹ 1,245", "Debited from", "XXXXXXXX5678", "UTR: 424512349876", "Transaction ID", "T2410091415221234567890"),
    listOf("Paid Successfully to\nRahul Sharma", "₹2,000", "UPI Ref No: 425112345678\n10 Oct, 09:41 AM", "From: Axis Bank - 5678"),
    listOf("Received from", "Priya Mehta", "₹500", "Completed", "8 Oct 2026, 7:02 pm", "Credited to Axis Bank XX5678"),
    listOf("payment successful", "₹8,360", "paid to Axis Bank credit card", "xxxx 3307", "05 Oct 2026, 11:20 am"),
    listOf("Payment failed", "Paid to", "Zomato", "₹350", "10 Oct 2026"), listOf("Chats", "Hello there"),
    listOf("Oct 3, 2026 9:05 PM", "₹99"), listOf("07/10/2026 14:30", "Rs 1,000", "Sent to", "Amma"), listOf("28 Dec, 10:00 AM", "INR 50 paid to rapido"))
  for (s in shots) { val d = ScreenshotParser.parse(s, sctx); out.add("shot " + (d?.let { listOf(it.type, it.amount, it.accountId ?: "", it.toAccountId ?: "", it.categoryId ?: "", it.payee ?: "", it.note ?: "", iso(it.occurredAt), it.include, it.warning ?: "").joinToString(" | ") } ?: "null")) }
  val vctx = CaptureContext(listOf(CaptureAccount("axis", "Axis Bank", "bank", "Axis Bank", "5678"), CaptureAccount("bob", "Bank of Baroda", "bank", "Bank of Baroda", null),
    CaptureAccount("card", "Axis MyZone", "card", "Axis Bank", "3307"), CaptureAccount("cash", "Cash", "cash", null, null)),
    listOf(CaptureCategory("food", "Food & Dining", "expense", null), CaptureCategory("groceries", "Groceries", "expense", null), CaptureCategory("transport", "Transport", "expense", null),
      CaptureCategory("cab", "Metro/Auto/Cab", "expense", "transport"), CaptureCategory("rent", "Rent", "expense", null), CaptureCategory("salary", "Salary", "income", null)),
    mapOf("rahul" to "rent"), "axis", ms(2026, 10, 10, 15, 30))
  for (w in listOf("two hundred and fifty for lunch", "one fifty auto", "fifteen hundred groceries", "two lakh fifty thousand", "a thousand rupees", "a coffee", "bread and butter", "one and a half thousand")) out.add("words " + VoiceParser.wordsToDigits(w))
  for (a in listOf("₹1,500 dinner", "spent 1.5k on shoes", "rent 18 thousand", "salary 1.2 lakh", "99.50 rupees", "lunch")) out.add("amt " + (VoiceParser.findAmount(a)?.first ?: "null"))
  for (p in listOf("250 lunch, 80 auto and 40 chai", "60 bread and butter", "1,500 groceries then 200 petrol")) out.add("split " + VoiceParser.splitPhrases(p).joinToString(" || "))
  for (s in listOf("250 lunch, 80 auto and 40 chai", "250 lunch, 80 auto and 40 chai yesterday, paid 1.5k on zomato", "250 lunch today, 80 auto yesterday", "650 zomato dinner with team",
    "Yesterday I paid 420 on swiggy using my card, and two thousand to Rahul in cash", "got salary 90k from acme in axis", "moved 5000 from axis to baroda", "paid the credit card bill 8360",
    "coffee with Priya, 180 coffee", "on monday 300 petrol from bob", "last night 1200 dinner at Truffles", "3 days ago 45 chai", "on the 12th rent eighteen thousand to Rahul")) {
    val (drafts, skipped) = VoiceParser.parse(s, vctx)
    out.add("voice $s"); drafts.forEach { d -> out.add("  " + listOf(d.type, d.amount, d.accountId ?: "", d.toAccountId ?: "", d.categoryId ?: "", d.payee ?: "", d.note ?: "", iso(d.occurredAt), d.source).joinToString(" | ")) }
    out.add("  skipped " + skipped.joinToString(" || "))
  }
  return out.joinToString("\n") + "\n"
}
}
