package com.paisapulse.app.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.paisapulse.app.data.TxnType
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

enum class Tab { Home, Activity, Accounts, Settings, Search }

sealed interface Route {
  data object Root : Route
  data class TxnDetail(val id: String) : Route
  data class AccountDetail(val id: String) : Route
  data object Insights : Route
  data object Calendar : Route
  data object NetWorth : Route
  data object Categories : Route
  data object Budgets : Route
  data object Recurring : Route
  data object Goals : Route
  data object Splits : Route
  data class Friend(val id: String, val groupId: String? = null) : Route
  data object Backup : Route
  data object Converter : Route
  data object Subscriptions : Route
  data class Import(val accountId: String? = null) : Route
  data class Capture(val mode: String) : Route
  data class Group(val id: String) : Route
  data object Loans : Route
  data class LoanDetail(val id: String) : Route
  data object Cleanup : Route
  data object Templates : Route
  data object Tags : Route
  data class TagDetail(val tag: String) : Route
  data class Recap(val offset: Int) : Route
}

sealed interface Sheet {
  data class Add(val type: TxnType = TxnType.Expense, val editId: String? = null, val date: Long? = null, val accountId: String? = null) : Sheet
  data class AccountForm(val id: String?) : Sheet
  data class CategoryForm(val id: String?, val income: Boolean) : Sheet
  data class BudgetForm(val id: String?) : Sheet
  data class RecurringForm(val id: String?, val fromTxn: String? = null) : Sheet
  data class GoalForm(val id: String?) : Sheet
  data class CardForm(val accountId: String, val id: String?) : Sheet
  data class AccountNew(val type: String) : Sheet
  /** "accounts" or "categories:expense" / "categories:income" */
  data class Reorder(val what: String) : Sheet
  data class GroupForm(val id: String?) : Sheet
  data class LoanForm(val id: String?) : Sheet
  /** Ask people who owe you (Messages, QR, link). amounts: friend id → paise. */
  data class Request(val note: String?, val amounts: Map<String, Long>) : Sheet
  data object HomeLayout : Sheet
}

data class Toast(val text: String, val undo: (() -> Unit)? = null, val id: Long = System.nanoTime())

/** App-wide UI state: tab, per-tab back stacks, the open sheet, the toast. Mirrors the iOS Router. */
object Ui {
  var tab by mutableStateOf(Tab.Home)
  val stacks = Tab.entries.associateWith { mutableStateListOf<Route>(Route.Root) }
  var sheet by mutableStateOf<Sheet?>(null)
  var toast by mutableStateOf<Toast?>(null)
  /** Hidden while Activity is in select mode (its bulk bar takes the space), like iOS. */
  var hideTabBar by mutableStateOf(false)
  private var toastJob: Job? = null
  private val scope = CoroutineScope(Dispatchers.Main)

  val stack get() = stacks.getValue(tab)
  fun push(r: Route) { stack.add(r) }
  fun pop(): Boolean { if (stack.size > 1) { stack.removeAt(stack.lastIndex); return true }; return false }
  fun select(t: Tab) { if (tab == t) { val s = stacks.getValue(t); while (s.size > 1) s.removeAt(s.lastIndex) }; tab = t }

  fun show(text: String, undo: (() -> Unit)? = null) {
    val t = Toast(text, undo); toast = t
    toastJob?.cancel(); toastJob = scope.launch { delay(5000); if (toast?.id == t.id) toast = null }
  }

  /** paisapulse://add?type=…, paisapulse://tab/<name> */
  fun handle(uri: android.net.Uri?) {
    uri ?: return
    if (uri.scheme != "paisapulse") return
    when (uri.host) {
      "add" -> sheet = Sheet.Add(TxnType.of(uri.getQueryParameter("type")))
      "capture" -> { tab = Tab.Home; stacks.getValue(Tab.Home).add(Route.Capture(uri.getQueryParameter("mode") ?: "screenshot")) }
      "tab" -> tab = when (uri.lastPathSegment) { "activity" -> Tab.Activity; "accounts" -> Tab.Accounts; "settings" -> Tab.Settings; "search" -> Tab.Search; else -> Tab.Home }
    }
  }
}
