package com.paisapulse.app.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import com.paisapulse.app.data.Prefs
import com.paisapulse.app.ui.screens.*
import dev.chrisbanes.haze.hazeSource

@Composable fun Root(locked: Boolean, unlock: () -> Unit) {
  val haze = remember { dev.chrisbanes.haze.HazeState() }
  CompositionLocalProvider(LocalHaze provides haze) {
    val focus = androidx.compose.ui.platform.LocalFocusManager.current
    // Tap anywhere outside a field to put the keyboard away (fields also get a Done key).
    Box(Modifier.fillMaxSize().background(C.background).pointerInput(Unit) {
      awaitEachGesture {
        awaitFirstDown(pass = androidx.compose.ui.input.pointer.PointerEventPass.Initial)
        val up = waitForUpOrCancellation(pass = androidx.compose.ui.input.pointer.PointerEventPass.Initial)
        if (up != null) focus.clearFocus()
      }
    }) {
      if (!Prefs.onboarded) OnboardingScreen() else {
        Box(Modifier.fillMaxSize().hazeSource(haze)) {
          val stack = Ui.stack
          BackHandler(stack.size > 1) { Ui.pop() }
          AnimatedContent(Ui.tab to stack.toList(), transitionSpec = {
            val push = targetState.first == initialState.first && targetState.second.size > initialState.second.size
            val pop = targetState.first == initialState.first && targetState.second.size < initialState.second.size
            when {
              push -> slideInHorizontally(tween(260)) { it } togetherWith slideOutHorizontally(tween(260)) { -it / 3 }
              pop -> slideInHorizontally(tween(260)) { -it / 3 } togetherWith slideOutHorizontally(tween(260)) { it }
              else -> androidx.compose.animation.fadeIn(quick()) togetherWith androidx.compose.animation.fadeOut(quick())
            }
          }, label = "nav") { (tab, s) -> Screen(tab, s.last()) }
        }
        if (!Ui.hideTabBar) Box(Modifier.align(Alignment.BottomCenter)) { TabBar() }
        ToastHost(Modifier.align(Alignment.BottomCenter))
        ConfettiOverlay()
        when (val sh = Ui.sheet) {
          is Sheet.Add -> QuickAddSheet(sh)
          is Sheet.AccountForm -> AccountForm(sh.id)
          is Sheet.CategoryForm -> CategoryForm(sh.id, sh.income)
          is Sheet.BudgetForm -> BudgetForm(sh.id)
          is Sheet.RecurringForm -> RecurringForm(sh.id, sh.fromTxn)
          is Sheet.GoalForm -> GoalForm(sh.id)
          is Sheet.CardForm -> CardFormSheet(sh.accountId, sh.id)
          is Sheet.AccountNew -> AccountForm(null, sh.type)
          is Sheet.Reorder -> ReorderSheet(sh.what)
          is Sheet.GroupForm -> GroupFormSheet(sh.id)
          is Sheet.LoanForm -> LoanFormSheet(sh.id)
          is Sheet.Request -> RequestSheet(sh.note, sh.amounts)
          Sheet.HomeLayout -> HomeLayoutSheet()
          is Sheet.TripForm -> TripFormSheet(sh.kind, sh.editId)
          is Sheet.Wallet -> WalletSheet(sh.tripId)
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
    is Route.Friend -> FriendScreen(r.id, r.groupId)
    Route.Backup -> BackupScreen()
    Route.Converter -> ConverterScreen()
    Route.Account -> AccountScreen()
    is Route.People -> PeopleScreen(r.invite, r.link)
    Route.Inbox -> InboxScreen()
    Route.MainCurrency -> MainCurrencyScreen()
    Route.Accent -> AccentScreen()
    Route.AppIcon -> AppIconScreen()
    Route.Planning -> PlanningScreen()
    Route.ArchivedTrips -> ArchivedTripsScreen()
    is Route.TripDetail -> TripDetailScreen(r.id)
    Route.Subscriptions -> SubscriptionsScreen()
    is Route.Import -> ImportScreen(r.accountId)
    is Route.Capture -> CaptureScreen(r.mode)
    is Route.Group -> GroupScreen(r.id)
    Route.Loans -> LoansScreen()
    is Route.LoanDetail -> LoanDetailScreen(r.id)
    Route.Cleanup -> CleanupScreen()
    Route.Templates -> TemplatesScreen()
    Route.Tags -> TagsScreen()
    is Route.TagDetail -> TagDetailScreen(r.tag)
    is Route.Recap -> RecapScreen(r.offset)
    is Route.AutoCapture -> AutoCaptureScreen()
    is Route.Bills -> BillsScreen()
  }
}

@Composable fun LockScreen(unlock: () -> Unit) {
  Box(Modifier.fillMaxSize().background(C.background), contentAlignment = Alignment.Center) {
    androidx.compose.foundation.layout.Column(horizontalAlignment = Alignment.CenterHorizontally) {
      androidx.compose.foundation.Image(androidx.compose.ui.res.painterResource(com.paisapulse.app.R.drawable.app_logo), null, modifier = Modifier.size(androidx.compose.ui.unit.Dp(72f)))
      androidx.compose.material3.Text("Paisa Pulse is locked", style = T.headline, color = C.label, modifier = Modifier.padding(androidx.compose.ui.unit.Dp(16f)))
      androidx.compose.material3.Button(unlock, colors = androidx.compose.material3.ButtonDefaults.buttonColors(containerColor = C.accent)) { androidx.compose.material3.Text("Unlock", style = T.headline) }
    }
  }
}
