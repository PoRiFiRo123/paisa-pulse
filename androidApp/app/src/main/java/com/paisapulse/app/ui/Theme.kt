package com.paisapulse.app.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.paisapulse.app.R
import com.paisapulse.app.data.Prefs

/** iOS system colours (mirrors apple/Shared/Theme.swift and the iOS defaults). */
@Immutable data class Palette(
  val dark: Boolean,
  val background: Color, val card: Color, val label: Color, val secondary: Color, val tertiary: Color,
  val separator: Color, val fill: Color, val accent: Color, val expense: Color, val income: Color,
  val glass: Color, val glassBorder: Color,
)

fun hex(s: String): Color {
  val v = s.removePrefix("#").toLongOrNull(16) ?: 0x8E8E93
  return Color(0xFF000000 or v)
}

val accents = listOf(
  Triple("indigo", "Indigo", "#5E5CE6" to "#7D7AFF"), Triple("blue", "Blue", "#007AFF" to "#0A84FF"),
  Triple("purple", "Purple", "#AF52DE" to "#BF5AF2"), Triple("pink", "Pink", "#FF2D55" to "#FF375F"),
  Triple("orange", "Orange", "#FF9500" to "#FF9F0A"), Triple("green", "Green", "#34C759" to "#30D158"),
  Triple("teal", "Teal", "#30B0C7" to "#40C8E0"),
)
val swatches = listOf("#FF3B30", "#FF9500", "#FFB800", "#34C759", "#30B0C7", "#32ADE6", "#007AFF",
  "#5E5CE6", "#5856D6", "#AF52DE", "#FF2D55", "#A2845E", "#8E8E93", "#1E9E5A")

fun palette(dark: Boolean, accentKey: String): Palette {
  val a = accents.firstOrNull { it.first == accentKey } ?: accents[0]
  return if (dark) Palette(true, Color.Black, hex("#1C1C1E"), Color.White, hex("#8E8E93"), hex("#5A5A5F"), hex("#38383A"),
    Color(0x3D767680), hex(a.third.second), hex("#FF6B6B"), hex("#30D158"), Color(0xB31C1C1E), Color(0x26FFFFFF))
  else Palette(false, hex("#F2F2F7"), Color.White, Color.Black, hex("#8A8A8E"), hex("#C4C4C7"), hex("#E3E3E8"),
    Color(0x1F767680), hex(a.third.first), hex("#E5484D"), hex("#1E9E5A"), Color(0xCCF9F9FB), Color(0x14000000))
}

val LocalPalette = staticCompositionLocalOf { palette(false, "indigo") }
val C: Palette @Composable get() = LocalPalette.current

val Inter = FontFamily(
  Font(R.font.inter_regular, FontWeight.Normal), Font(R.font.inter_medium, FontWeight.Medium),
  Font(R.font.inter_semibold, FontWeight.SemiBold), Font(R.font.inter_bold, FontWeight.Bold),
)

/** iOS Dynamic Type sizes at the default setting. */
object T {
  private fun s(size: Int, w: FontWeight = FontWeight.Normal, track: Double = 0.0) =
    TextStyle(fontFamily = Inter, fontSize = size.sp, fontWeight = w, letterSpacing = track.sp)
  val largeTitle = s(34, FontWeight.Bold, -0.6)
  val title2 = s(22, FontWeight.Bold, -0.3)
  val title3 = s(20, FontWeight.SemiBold, -0.3)
  val headline = s(17, FontWeight.SemiBold, -0.2)
  val body = s(17, track = -0.2)
  val callout = s(16, track = -0.2)
  val subhead = s(15, track = -0.1)
  val footnote = s(13)
  val caption = s(12)
  val caption2 = s(11)
  /** Amounts: tabular figures so digits line up. */
  fun amount(size: Int, w: FontWeight = FontWeight.SemiBold) = s(size, w, -0.4).copy(fontFeatureSettings = "tnum")
}

@Composable
fun PaisaTheme(content: @Composable () -> Unit) {
  val dark = when (Prefs.theme) { "light" -> false; "dark" -> true; else -> isSystemInDarkTheme() }
  val p = palette(dark, Prefs.accent)
  val scheme = if (dark) darkColorScheme(primary = p.accent, background = p.background, surface = p.card, onSurface = p.label)
  else lightColorScheme(primary = p.accent, background = p.background, surface = p.card, onSurface = p.label)
  CompositionLocalProvider(LocalPalette provides p) {
    MaterialTheme(colorScheme = scheme, content = content)
  }
}
