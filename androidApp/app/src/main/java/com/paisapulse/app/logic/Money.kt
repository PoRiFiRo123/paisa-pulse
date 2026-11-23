package com.paisapulse.app.logic

import java.math.BigDecimal
import java.math.RoundingMode
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.util.Locale
import kotlin.math.abs

/** Money in the main currency (₹ by default, lakh/crore grouping; other currencies group in thousands).
 *  Never a minus sign: colour (and words like "due") carry direction. */
object Money {
  /** The main currency code (Settings › Main Currency); set by Prefs. */
  @Volatile var base: String = "INR"
  val symbol get() = World.symbol(base)
  private val indian get() = base == "INR"

  private fun group(units: Long, indian: Boolean): String {
    val s = units.toString()
    if (s.length <= 3) return s
    val last3 = s.takeLast(3)
    if (!indian) return s.reversed().chunked(3).joinToString(",").reversed()
    val rest = s.dropLast(3).reversed().chunked(2).joinToString(",").reversed()
    return "$rest,$last3"
  }

  /** Minor units (paise, cents) in the main currency → "₹1,23,456" / "₹1,23,456.50". */
  fun format(paise: Long, hidden: Boolean = false): String = format(paise, base, hidden)

  /** Any currency: "$1,234.50", "€90", "₹1,23,456". */
  fun format(minor: Long, code: String, hidden: Boolean = false): String {
    val sym = World.symbol(code).let { if (it.length > 1 && it.all { c -> c.isLetter() }) "$it " else it }
    if (hidden) return "$sym••••"
    val p = abs(minor)
    val whole = group(p / 100, code == "INR")
    val frac = p % 100
    return if (frac == 0L) "$sym$whole" else "$sym$whole.${frac.toString().padStart(2, '0')}"
  }

  fun compact(paise: Long, hidden: Boolean = false): String {
    val sym = symbol.let { if (it.length > 1 && it.all { c -> c.isLetter() }) "$it " else it }
    if (hidden) return "$sym••"
    val r = abs(paise) / 100.0
    fun trim(v: Double): String {
      val s = DecimalFormat(if (v < 10) "0.#" else "0", DecimalFormatSymbols(Locale.US)).apply { roundingMode = RoundingMode.HALF_EVEN }.format(v)
      return s
    }
    return if (indian) when {
      r >= 1_00_00_000 -> sym + trim(r / 1_00_00_000) + "Cr"
      r >= 1_00_000 -> sym + trim(r / 1_00_000) + "L"
      r >= 1_000 -> sym + trim(r / 1_000) + "K"
      else -> sym + trim(r)
    } else when {
      r >= 1_000_000_000 -> sym + trim(r / 1_000_000_000) + "B"
      r >= 1_000_000 -> sym + trim(r / 1_000_000) + "M"
      r >= 1_000 -> sym + trim(r / 1_000) + "K"
      else -> sym + trim(r)
    }
  }

  /** "1,250.5" → 125050; null when empty, invalid or not positive. */
  fun parse(text: String): Long? {
    val c = text.replace(",", "").replace("₹", "").replace(symbol, "").trim()
    if (c.isEmpty()) return null
    val d = c.toBigDecimalOrNull() ?: return null
    val p = d.multiply(BigDecimal(100)).setScale(0, RoundingMode.HALF_UP).toLong()
    return if (p > 0) p else null
  }

  fun paise(rupees: BigDecimal): Long = maxOf(0L, rupees.multiply(BigDecimal(100)).setScale(0, RoundingMode.HALF_UP).toLong())
}

/** Quick Add keypad sums: "250+80×2" (× and ÷ first). */
object KeypadMath {
  fun evaluate(expr: String): BigDecimal? {
    val nums = mutableListOf<BigDecimal>(); val ops = mutableListOf<Char>(); var cur = ""
    for (ch in expr) {
      if (ch in "+−×÷-*/") {
        nums.add(cur.toBigDecimalOrNull() ?: return null); cur = ""
        ops.add(when (ch) { '-' -> '−'; '*' -> '×'; '/' -> '÷'; else -> ch })
      } else cur += ch
    }
    if (cur.isEmpty()) { if (ops.isNotEmpty()) ops.removeAt(ops.lastIndex) } else nums.add(cur.toBigDecimalOrNull() ?: return null)
    if (nums.isEmpty() || nums.size != ops.size + 1) return null
    val stack = mutableListOf(nums[0]); val addOps = mutableListOf<Char>()
    ops.forEachIndexed { i, op ->
      val rhs = nums[i + 1]
      when (op) {
        '×' -> stack[stack.lastIndex] = stack.last().multiply(rhs)
        '÷' -> { if (rhs.signum() == 0) return null; stack[stack.lastIndex] = stack.last().divide(rhs, 10, RoundingMode.HALF_UP) }
        else -> { stack.add(rhs); addOps.add(op) }
      }
    }
    var total = stack[0]
    addOps.forEachIndexed { i, op -> total = if (op == '+') total.add(stack[i + 1]) else total.subtract(stack[i + 1]) }
    return total
  }

  fun isExpression(s: String) = s.drop(1).any { it in "+−×÷" }
}
