package com.paisapulse.app.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.paisapulse.app.data.Prefs
import com.paisapulse.app.ui.screens.*
import dev.chrisbanes.haze.hazeSource

@Composable fun Root(locked: Boolean, unlock: () -> Unit) {
  val haze = remember { dev.chrisbanes.haze.HazeState() }
  CompositionLocalProvider(LocalHaze provides haze) {
    Box(Modifier.fillMaxSize().background(C.background)) {
      if (!Prefs.onboarded) OnboardingScreen() else {
        Box(Modifier.fillMaxSize().hazeSource(haze)) {
          val stack = Ui.stack
          BackHandler(stack.size > 1) { Ui.pop() }
          AnimatedContent(Ui.tab to stack.toList(), transitionSpec = {
            val push = targetState.first == initialState.first && targetState.second.size > initialState.second.size
            val pop = targetState.first == initialState.first && targetState.second.size < initialState.second.size
            when {
              push -> slideInHorizontally { it } togetherWith slideOutHorizontally { -it / 3 }
              pop -> slideInHorizontally { -it / 3 } togetherWith slideOutHorizontally { it }
              else -> androidx.compose.animation.fadeIn() togetherWith androidx.compose.animation.fadeOut()
            }
          }, label = "nav") { (tab, s) -> Screen(tab, s.last()) }
        }
        Box(Modifier.align(Alignment.BottomCenter)) { TabBar() }
        ToastHost(Modifier.align(Alignment.BottomCenter))
        when (val sh = Ui.sheet) {
          is Sheet.Add -> QuickAddSheet(sh)
          is Sheet.AccountForm -> AccountForm(sh.id)
          is Sheet.CategoryForm -> CategoryForm(sh.id, sh.income)
          is Sheet.BudgetForm -> BudgetForm(sh.id)
          is Sheet.RecurringForm -> RecurringForm(sh.id, sh.fromTxn)
          is Sheet.GoalForm -> GoalForm(sh.id)
          is Sheet.CardForm -> CardFormSheet(sh.accountId, sh.id)
          is Sheet.AccountNew -> AccountForm(null, sh.type)
          null -> {}
        }
      }
      if (locked) LockScreen(unlock)
    }
  }
}

@Composable private fun Screen(tab: Tab, r: Route) {
  when (r) {
    Route.Root -> when (tab) { Tab.Home -> HomeScreen(); Tab.Activity -> ActivityScreen(); Tab.Accounts -> AccountsScreen(); Tab.Settings -> SettingsScreen(); Tab.Search -> SearchScreen() }
    is Route.TxnDetail -> TxnDetailScreen(r.id)
    is Route.AccountDetail -> AccountDetailScreen(r.id)
    Route.Insights -> InsightsScreen()
    Route.Calendar -> CalendarScreen()
    Route.NetWorth -> NetWorthScreen()
    Route.Categories -> CategoriesScreen()
    Route.Budgets -> BudgetsScreen()
    Route.Recurring -> RecurringScreen()
    Route.Goals -> GoalsScreen()
    Route.Splits -> SplitsScreen()
    is Route.Friend -> FriendScreen(r.id)
    Route.Backup -> BackupScreen()
    Route.Converter -> ConverterScreen()
  }
}

@Composable fun LockScreen(unlock: () -> Unit) {
  Box(Modifier.fillMaxSize().background(C.background), contentAlignment = Alignment.Center) {
    androidx.compose.foundation.layout.Column(horizontalAlignment = Alignment.CenterHorizontally) {
      androidx.compose.material3.Icon(Sym.of("lock.fill"), null, tint = C.secondary, modifier = Modifier.size(androidx.compose.ui.unit.Dp(44f)))
      androidx.compose.material3.Text("Paisa Pulse is locked", style = T.headline, color = C.label, modifier = Modifier.padding(androidx.compose.ui.unit.Dp(16f)))
      androidx.compose.material3.Button(unlock, colors = androidx.compose.material3.ButtonDefaults.buttonColors(containerColor = C.accent)) { androidx.compose.material3.Text("Unlock", style = T.headline) }
    }
  }
}
