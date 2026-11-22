package com.paisapulse.app.widget

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.*
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.layout.*
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.paisapulse.app.MainActivity
import com.paisapulse.app.data.Prefs
import com.paisapulse.app.data.Store
import com.paisapulse.app.logic.*
import java.time.LocalDate

/** "This Month" widget with an Add button (same content as the iPhone widget). */
class SpendingWidget : GlanceAppWidget() {
  override suspend fun provideGlance(context: Context, id: GlanceId) {
    val d = Store.value
    val m = Periods.month(LocalDate.now(), Prefs.monthStartDay)
    val spent = Ledger.summary(d.transactions, m).spent
    val today = Ledger.summary(d.transactions, Range(LocalDate.now().ms(), LocalDate.now().plusDays(1).ms())).spent
    val budget = d.budgets.firstOrNull { it.categoryId == null && it.period != "weekly" }?.amount
    val hidden = Prefs.hideAmounts
    val add = Intent(Intent.ACTION_VIEW, Uri.parse("paisapulse://add?type=expense"), context, MainActivity::class.java)
    provideContent {
      Column(GlanceModifier.fillMaxSize().background(Color(0xFFF2F2F7)).cornerRadius(22.dp).padding(14.dp).clickable(actionStartActivity(add))) {
        Text("This month", style = TextStyle(color = ColorProvider(Color(0xFF8A8A8E)), fontSize = 12.sp))
        Text(Money.compact(spent, hidden), style = TextStyle(color = ColorProvider(Color.Black), fontSize = 28.sp, fontWeight = FontWeight.Bold))
        Text("Today ${Money.compact(today, hidden)}", style = TextStyle(color = ColorProvider(Color(0xFFE5484D)), fontSize = 12.sp))
        Spacer(GlanceModifier.defaultWeight())
        if (budget != null && budget > 0) {
          val left = budget - spent
          Text(if (left < 0) "${Money.compact(left, hidden)} over" else "${Money.compact(left, hidden)} left",
            style = TextStyle(color = ColorProvider(if (left < 0) Color(0xFFE5484D) else Color(0xFF8A8A8E)), fontSize = 11.sp))
        }
        Row(GlanceModifier.fillMaxWidth(), horizontalAlignment = Alignment.End) {
          Box(GlanceModifier.background(Color(0xFF5E5CE6)).cornerRadius(16.dp).padding(horizontal = 12.dp, vertical = 6.dp)) {
            Text("+ Add", style = TextStyle(color = ColorProvider(Color.White), fontSize = 13.sp, fontWeight = FontWeight.Medium))
          }
        }
      }
    }
  }
}

class SpendingWidgetReceiver : GlanceAppWidgetReceiver() { override val glanceAppWidget: GlanceAppWidget = SpendingWidget() }
