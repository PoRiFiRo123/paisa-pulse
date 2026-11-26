package com.paisapulse.app.ui.screens

import android.content.Context
import android.content.Intent
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import androidx.core.content.FileProvider
import com.paisapulse.app.data.Txn
import com.paisapulse.app.logic.*
import java.io.File
import java.time.format.DateTimeFormatter
import java.util.Locale

/** The monthly report as an A4 PDF: totals, every category against last month, the biggest expenses. Same layout as iOS ReportPDF. */
object ReportPdf {
  fun share(ctx: Context, title: String, r: Recap.Result, rows: List<Report.Row>, biggest: List<Txn>, l: Lookups) {
    val doc = PdfDocument()
    val pw = 595; val ph = 842; val m = 48f; val w = pw - 2 * m
    var pageNo = 0
    var page = doc.startPage(PdfDocument.PageInfo.Builder(pw, ph, ++pageNo).create())
    var y = m
    fun paint(size: Float, bold: Boolean = false, color: Int = 0xFF000000.toInt(), right: Boolean = false) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      textSize = size; this.color = color; typeface = Typeface.create(Typeface.DEFAULT, if (bold) Typeface.BOLD else Typeface.NORMAL)
      textAlign = if (right) Paint.Align.RIGHT else Paint.Align.LEFT
    }
    fun ensure(h: Float) { if (y + h > ph - m) { doc.finishPage(page); page = doc.startPage(PdfDocument.PageInfo.Builder(pw, ph, ++pageNo).create()); y = m } }
    fun text(s: String, size: Float, x: Float = 0f, bold: Boolean = false, color: Int = 0xFF000000.toInt(), right: Boolean = false) =
      page.canvas.drawText(s, m + x, y + size, paint(size, bold, color, right))
    fun line() = page.canvas.drawLine(m, y, pw - m, y, paint(1f, color = 0xFFE0E0E0.toInt()).apply { strokeWidth = 0.5f })
    val gray = 0xFF8E8E93.toInt(); val accent = 0xFF5E5CE6.toInt()
    fun name(id: String) = l.categories[id]?.name ?: "Uncategorised"

    text("Paisa Pulse · Monthly report", 11f, bold = true, color = accent); y += 18
    text(title, 26f, bold = true); y += 42
    listOf("Spent" to Money.format(r.spent), "Income" to Money.format(r.income), (if (r.saved >= 0) "Saved" else "Overspent") to Money.format(kotlin.math.abs(r.saved)))
      .forEachIndexed { i, (k, v) -> val x = i * w / 3; text(k, 10f, x, color = gray); y += 14; text(v, 18f, x, bold = true); y -= 14 }
    y += 40
    r.change?.let { ch -> text(if (ch >= 0) "${Math.round(ch * 100)}% more spending than last month" else "${Math.round(-ch * 100)}% less spending than last month", 11f, color = 0xFF555555.toInt()); y += 24 }
    text("By category", 14f, bold = true); y += 22
    text("This month", 9f, w - 100, color = gray, right = true); text("Last month", 9f, w, color = gray, right = true); y += 16; line(); y += 6
    rows.forEach { row ->
      ensure(22f)
      text(name(row.categoryId), 11f); text(Money.format(row.amount), 11f, w - 100, bold = true, right = true); text(Money.format(row.before), 11f, w, color = gray, right = true)
      y += 20
    }
    line(); y += 22
    val (up, down) = Report.movers(rows)
    if (up.isNotEmpty() || down.isNotEmpty()) {
      ensure(40f); text("What changed", 14f, bold = true); y += 22
      up.forEach { ensure(18f); text("${name(it.categoryId)}: ${Money.format(it.diff)} more", 11f); y += 18 }
      down.forEach { ensure(18f); text("${name(it.categoryId)}: ${Money.format(-it.diff)} less", 11f); y += 18 }
      y += 14
    }
    if (biggest.isNotEmpty()) {
      ensure(40f); text("Biggest expenses", 14f, bold = true); y += 22
      val f = DateTimeFormatter.ofPattern("d MMM", Locale.ENGLISH)
      biggest.forEach { t ->
        ensure(18f); text("${t.occurredAt.toDate().format(f)}  ${l.title(t)}", 11f); text(Money.format(t.effectiveAmount), 11f, w, bold = true, right = true); y += 18
      }
    }
    y = maxOf(y + 20, ph - m - 14)
    text("Made on this phone with Paisa Pulse. ${r.count} transactions.", 9f, color = gray)
    doc.finishPage(page)

    val dir = File(ctx.cacheDir, "share").apply { mkdirs() }
    val file = File(dir, "Paisa Pulse - $title.pdf")
    file.outputStream().use { doc.writeTo(it) }; doc.close()
    val uri = FileProvider.getUriForFile(ctx, "com.paisapulse.app.files", file)
    ctx.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("application/pdf").putExtra(Intent.EXTRA_STREAM, uri)
      .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION), "Monthly report"))
  }
}
