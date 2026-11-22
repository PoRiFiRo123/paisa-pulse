package com.paisapulse.app.logic

import java.time.format.DateTimeFormatter
import java.util.Locale

/** Insights periods, same maths as iOS PeriodKind.swift. */
enum class PeriodKind(val label: String, val noun: String) {
  Week("Week", "week"), Month("Month", "month"), Quarter("Quarter", "quarter"), Year("Year", "year"), Custom("Custom", "period");

  fun range(offset: Int, startDay: Int, weekStart: Int, custom: Range? = null, from: java.time.LocalDate = java.time.LocalDate.now()): Range = when (this) {
    Week -> { val w = Periods.week(from, weekStart).start.toDate().plusWeeks(offset.toLong()); Range(w.ms(), w.plusWeeks(1).ms()) }
    Month -> Periods.month(offset, startDay, from)
    Quarter, Year -> {
      val size = if (this == Quarter) 3 else 12
      val m = Periods.month(from, startDay).start.toDate().monthValue - 1
      val first = -(m % size) + offset * size
      Range(Periods.month(first, startDay, from).start, Periods.month(first + size, startDay, from).start)
    }
    Custom -> { val c = custom ?: Periods.month(from, startDay); val len = c.end - c.start; Range(c.start + len * offset, c.end + len * offset) }
  }

  fun label(r: Range, startDay: Int): String {
    val s = r.start.toDate(); val e = (r.end - 1).toDate()
    fun f(p: String, d: java.time.LocalDate) = DateTimeFormatter.ofPattern(p, Locale.ENGLISH).format(d)
    return when (this) {
      Month -> Periods.label(r, startDay)
      Year -> if (startDay == 1) f("yyyy", s) else "${f("yyyy", s)}–${f("yy", e)}"
      Quarter -> "${f("MMM", s)}–${f("MMM", e)} ${s.year}"
      Week, Custom -> "${f("d MMM", s)} – ${f("d MMM", e)}"
    }
  }

  fun short(r: Range): String {
    val s = r.start.toDate()
    return when (this) {
      Week, Custom -> DateTimeFormatter.ofPattern("d MMM", Locale.ENGLISH).format(s)
      Month -> DateTimeFormatter.ofPattern("MMM", Locale.ENGLISH).format(s)
      Quarter -> "Q${(s.monthValue - 1) / 3 + 1} ’${s.year % 100}"
      Year -> s.year.toString()
    }
  }
}
