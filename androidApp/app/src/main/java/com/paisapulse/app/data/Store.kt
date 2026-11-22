package com.paisapulse.app.data

import android.content.Context
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import java.io.File

val PaisaJson = Json { ignoreUnknownKeys = true; explicitNulls = false; encodeDefaults = true }

/** One JSON file in the app's private storage, kept in memory as a StateFlow. Saves are debounced and atomic. */
object Store {
  private lateinit var file: File
  private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
  private var pending: Job? = null
  private val state = MutableStateFlow(Db())
  val db: StateFlow<Db> get() = state
  val value: Db get() = state.value

  fun init(ctx: Context) {
    file = File(ctx.filesDir, "paisa-pulse.json")
    state.value = if (file.exists()) runCatching { decode(file.readText()) }.getOrElse { Db() } else Db()
  }

  fun update(change: (Db) -> Db) {
    state.value = change(state.value)
    pending?.cancel()
    pending = scope.launch { delay(250); write() }
  }

  /** Replace everything (restore, delete all). */
  fun replace(db: Db) = update { db }

  @Synchronized fun write() {
    val tmp = File(file.parentFile, file.name + ".tmp")
    tmp.writeText(encode(state.value))
    tmp.renameTo(file)
  }

  fun encode(db: Db): String = PaisaJson.encodeToString(Db.serializer(), db.copy(
    exportedAt = now(),
    txnSplitShares = db.transactions.mapNotNull { t -> t.splitShare?.let { Share(t.id, it) } },
  ))

  fun decode(text: String): Db {
    val raw = PaisaJson.decodeFromString(Db.serializer(), text)
    val shares = raw.txnSplitShares.associate { it.id to it.share }
    return raw.copy(transactions = raw.transactions.map { if (shares.containsKey(it.id)) it.copy(splitShare = shares[it.id]) else it })
  }
}
