package com.paisapulse.app.ui

import android.content.Context
import android.graphics.RuntimeShader
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.paisapulse.app.data.*
import com.paisapulse.app.logic.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.launch
import kotlin.random.Random

// Small things that make the app feel alive: one timing everywhere, rolling numbers, pressable
// buttons, skeletons, a live liquid shader, and one big celebration. Same on iPhone (Core/Polish.swift).

/** Every animation in the app: about 0.2 seconds. */
fun <T> quick(): FiniteAnimationSpec<T> = tween(200, easing = FastOutSlowInEasing)

/** Amounts roll digit by digit when they change (like iOS numericText). */
@Composable fun RollingText(text: String, style: TextStyle, color: Color, modifier: Modifier = Modifier) {
  Row(modifier.clearAndSetSemantics { contentDescription = text }) {
    text.forEachIndexed { i, ch ->
      key(i) {
        AnimatedContent(ch, transitionSpec = {
          val up = targetState > initialState
          (slideInVertically(quick()) { if (up) it else -it } + fadeIn(quick())) togetherWith
            (slideOutVertically(quick()) { if (up) -it else it } + fadeOut(quick())) using SizeTransform(clip = true)
        }, label = "digit") { c -> Text(c.toString(), style = style, color = color, maxLines = 1, softWrap = false) }
      }
    }
  }
}

/** Shrinks a tiny bit while pressed. Doesn't take the touch, so the click still works. */
fun Modifier.pressScale(): Modifier = composed {
  var pressed by remember { mutableStateOf(false) }
  val s by animateFloatAsState(if (pressed) 0.96f else 1f, quick(), label = "press")
  this.pointerInput(Unit) {
    awaitEachGesture {
      awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
      pressed = true
      waitForUpOrCancellation(PointerEventPass.Initial)
      pressed = false
    }
  }.graphicsLayer { scaleX = s; scaleY = s; alpha = if (pressed) 0.85f else 1f }
}

/** Taps that match what happened. */
object Haptics {
  fun success(v: View) { v.performHapticFeedback(if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.VIRTUAL_KEY) }
  fun error(v: View) { v.performHapticFeedback(if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.REJECT else HapticFeedbackConstants.LONG_PRESS) }
  /** A soft tap when a row lands in a new place. */
  fun soft(v: View) { v.performHapticFeedback(if (Build.VERSION.SDK_INT >= 34) HapticFeedbackConstants.SEGMENT_TICK else HapticFeedbackConstants.CLOCK_TICK) }
}

// ------------------------------------------------------------ skeletons

/** Placeholder rows while something loads, instead of a spinner. */
@Composable fun SkeletonRows(count: Int = 4) {
  val t = rememberInfiniteTransition(label = "skeleton")
  val a by t.animateFloat(0.45f, 0.9f, infiniteRepeatable(tween(900), RepeatMode.Reverse), label = "pulse")
  Column(Modifier.clearAndSetSemantics { contentDescription = "Loading" }) {
    repeat(count) { i ->
      if (i > 0) Divider(60.dp)
      Row(Modifier.fillMaxWidth().padding(16.dp).graphicsLayer { alpha = a }, verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(32.dp).clip(CircleShape).background(C.fill))
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
          Box(Modifier.fillMaxWidth(0.6f).height(12.dp).clip(CircleShape).background(C.fill))
          Box(Modifier.fillMaxWidth(0.4f).height(10.dp).clip(CircleShape).background(C.fill))
        }
        Box(Modifier.size(56.dp, 12.dp).clip(CircleShape).background(C.fill))
      }
    }
  }
}

// ------------------------------------------------------------ live shader (Android 13+)

private const val LIQUID = """
uniform float2 size; uniform float time;
layout(color) uniform half4 a; layout(color) uniform half4 b;
half4 main(float2 p) {
  float2 uv = p / max(size, float2(1.0));
  float t = time * 0.35;
  float v = sin(uv.x * 3.1 + t) + sin(uv.y * 4.3 - t * 1.3) + sin((uv.x + uv.y) * 2.7 + t * 0.7)
          + sin(length(uv - float2(0.5 + 0.3 * sin(t * 0.5), 0.5)) * 6.0 - t);
  return mix(a, b, half(0.5 + 0.5 * sin(v * 1.2)));
}"""

private const val WAVE = """
uniform float2 size; uniform float time; layout(color) uniform half4 tint;
half4 main(float2 p) {
  float2 uv = p / max(size, float2(1.0));
  float sheen = 0.5 + 0.5 * sin(uv.x * 9.0 - time * 2.4 + sin(uv.y * 3.14 + time) * 0.8);
  return half4(tint.rgb * half(0.86 + 0.14 * sheen), tint.a);
}"""

/** Seconds for shaders, about 30 times a second; holds still in Battery Saver or with animations turned off. */
@Composable private fun shaderTime(): State<Float> {
  val ctx = LocalContext.current
  val still = remember {
    (ctx.getSystemService(Context.POWER_SERVICE) as PowerManager).isPowerSaveMode ||
      Settings.Global.getFloat(ctx.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
  }
  return produceState(7f, still) {
    if (still) return@produceState
    val start = System.nanoTime()
    while (true) { withFrameNanos { }; value = 7f + (System.nanoTime() - start) / 1e9f; delay(33) }
  }
}

/** A slow liquid gradient in the accent colours (behind Home's balance). Still gradient before Android 13. */
fun Modifier.liquidBackground(): Modifier = composed {
  val a = C.accent
  val b = lerp(C.accent, Color(0xFFFF2D55), 0.35f)
  val alpha = if (C.dark) 0.28f else 0.16f
  if (Build.VERSION.SDK_INT < 33) return@composed this.background(Brush.linearGradient(listOf(a, b)), alpha = alpha)
  val shader = remember { RuntimeShader(LIQUID) }
  val time by shaderTime()
  this.drawBehind {
    shader.setFloatUniform("size", size.width, size.height)
    shader.setFloatUniform("time", time)
    shader.setColorUniform("a", a.toArgb()); shader.setColorUniform("b", b.toArgb())
    drawRect(ShaderBrush(shader), alpha = alpha)
  }
}

/** A progress bar whose fill moves gently, like liquid (budgets, goals, trips). */
@Composable fun LiquidProgress(value: Double, tint: Color, modifier: Modifier = Modifier, height: Dp = 8.dp) {
  val v by animateFloatAsState(value.coerceIn(0.0, 1.0).toFloat(), quick(), label = "progress")
  Box(modifier.fillMaxWidth().height(height).clip(CircleShape).background(C.fill)) {
    if (v > 0f) {
      val fill = Modifier.fillMaxWidth(v).fillMaxHeight().clip(CircleShape)
      if (Build.VERSION.SDK_INT >= 33) {
        val shader = remember { RuntimeShader(WAVE) }
        val time by shaderTime()
        Box(fill.drawBehind {
          shader.setFloatUniform("size", size.width, size.height); shader.setFloatUniform("time", time)
          shader.setColorUniform("tint", tint.toArgb())
          drawRect(ShaderBrush(shader))
        })
      } else Box(fill.background(tint))
    }
  }
}

// ------------------------------------------------------------ celebration

/** The one big moment: confetti in the app's colours plus a success tap. Fired by [Celebrations]. */
object Celebration {
  var count by mutableIntStateOf(0); private set
  var message by mutableStateOf(""); private set
  fun fire(text: String) { message = text; count++ }
}

private class Piece(val x: Float, val vx: Float, val vy: Float, val spin: Float, val size: Float, val color: Color, val round: Boolean)

@Composable fun ConfettiOverlay() {
  val view = LocalView.current
  val ctx = LocalContext.current
  var pieces by remember { mutableStateOf<List<Piece>>(emptyList()) }
  var t by remember { mutableFloatStateOf(0f) }
  var banner by remember { mutableStateOf<String?>(null) }
  val colors = listOf(C.accent, C.income, Color(0xFFFF9500), Color(0xFFFF2D55), Color(0xFFFFB800), Color(0xFF007AFF), Color(0xFFAF52DE))
  LaunchedEffect(Celebration.count) {
    if (Celebration.count == 0) return@LaunchedEffect
    Haptics.success(view)
    banner = Celebration.message
    val still = Settings.Global.getFloat(ctx.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    if (!still) {
      pieces = List(140) { Piece(Random.nextFloat(), Random.nextFloat() * 4 - 2, 0.5f + Random.nextFloat() * 3.5f, Random.nextFloat() * 4 - 2,
        6f + Random.nextFloat() * 6, colors.random(), Random.nextBoolean()) }
      val start = System.nanoTime()
      while (t < 2.6f) { withFrameNanos { }; t = (System.nanoTime() - start) / 1e9f }
    } else delay(2600)
    pieces = emptyList(); t = 0f; banner = null
  }
  Box(Modifier.fillMaxSize()) {
    if (pieces.isNotEmpty()) Canvas(Modifier.fillMaxSize()) {
      val fade = (1f - ((t - 2.0f) / 0.6f).coerceIn(0f, 1f))
      val d = density
      for (p in pieces) {
        val x = p.x * size.width + p.vx * t * 60 * d
        val y = -20 * d + p.vy * t * 60 * d + 0.5f * 900f * t * t / 2 * d
        if (y > size.height + 20 * d) continue
        translate(x, y) {
          rotate(p.spin * t * 360, Offset.Zero) {
            val s = p.size * d
            if (p.round) drawCircle(p.color, s / 2, Offset.Zero, alpha = fade)
            else drawRect(p.color, Offset(-s / 2, -s / 3), Size(s, s * 0.6f), alpha = fade)
          }
        }
      }
    }
    AnimatedVisibility(banner != null, Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(top = 8.dp),
      enter = slideInVertically(quick()) { -it } + fadeIn(quick()), exit = slideOutVertically(quick()) { -it } + fadeOut(quick())) {
      Row(Modifier.glass(RoundedCornerShape(26.dp)).padding(horizontal = 18.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(Sym.of("sparkles"), null, tint = C.accent, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(8.dp))
        Text(banner ?: "", style = T.headline, color = C.label)
      }
    }
  }
}

/**
 * When to celebrate: a savings goal reached, a month that ended under budget, and everyone settled up.
 * Each fires once; on the first run the current state is noted without celebrating old wins.
 */
object Celebrations {
  private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

  @OptIn(kotlinx.coroutines.FlowPreview::class)
  fun init(ctx: Context) {
    val prefs = ctx.getSharedPreferences("paisa-celebrate", Context.MODE_PRIVATE)
    scope.launch { Store.db.debounce(1500).collect { check(prefs, it) } }
  }

  private fun check(p: android.content.SharedPreferences, db: Db) {
    // Goals reached.
    val reached = db.goals.filter { it.archivedAt == null && it.target > 0 && it.saved >= it.target }.map { it.id }.toSet()
    val seen = p.getStringSet("goals", null)
    if (seen != null) {
      db.goals.firstOrNull { it.id in reached && it.id !in seen }?.let { Celebration.fire("You reached ${it.name}!") }
      p.edit().putStringSet("goals", seen + reached).apply()
    } else p.edit().putStringSet("goals", reached).apply()

    // Everyone settled up (after owing something).
    val open = Splits.balances(db.splitEntries).values.any { it != 0L }
    if (p.getBoolean("hadOpen", false) && !open && db.splitEntries.isNotEmpty()) Celebration.fire("All settled up!")
    p.edit().putBoolean("hadOpen", open).apply()

    // Last month under budget (checked once, in a new month).
    val month = Periods.month(0, Prefs.monthStartDay)
    val last = p.getLong("budgetMonth", 0)
    if (last == month.start) return
    p.edit().putLong("budgetMonth", month.start).apply()
    if (last == 0L) return
    val budgets = db.budgets.filter { it.period != "weekly" }
    if (budgets.isEmpty()) return
    val prev = Periods.month(-1, Prefs.monthStartDay)
    val progress = Budgets.progress(budgets, TripMath.budgetTxns(db.liveTxns, db.trips), db.categories.associateBy { it.id }, prev, prev)
    if (progress.isNotEmpty() && progress.none { it.over }) {
      val name = java.time.Instant.ofEpochMilli(prev.start).atZone(java.time.ZoneId.systemDefault()).month
        .getDisplayName(java.time.format.TextStyle.FULL, java.util.Locale.ENGLISH)
      Celebration.fire("You stayed under budget in $name!")
    }
  }
}
