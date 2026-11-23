package com.paisapulse.app.cloud

import android.annotation.SuppressLint
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.paisapulse.app.BuildConfig
import com.paisapulse.app.data.*
import com.paisapulse.app.logic.*
import com.paisapulse.app.logic.CloudLogic.Expense
import com.paisapulse.app.logic.CloudLogic.InboxItem
import com.paisapulse.app.logic.CloudLogic.Member
import com.paisapulse.app.logic.CloudLogic.Person
import com.paisapulse.app.logic.CloudLogic.Settlement
import com.paisapulse.app.logic.CloudLogic.ShareRow
import com.paisapulse.app.logic.CloudLogic.Space
import com.paisapulse.app.logic.CloudLogic.State
import com.paisapulse.app.logic.CloudLogic.TripItemShare
import com.paisapulse.app.logic.CloudLogic.TripShare
import com.paisapulse.app.work.Services
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.*
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.time.OffsetDateTime
import java.util.concurrent.TimeUnit

/**
 * Paisa Pulse accounts (Supabase): email-code sign-in, then everything goes through the database
 * functions in supabase/migrations. Same behaviour as the iPhone app (apple/App/Cloud/Cloud.swift).
 * The URL and public key come from CI (BuildConfig); when empty, accounts are off in that build.
 */
@SuppressLint("StaticFieldLeak")
object Cloud {
  private lateinit var ctx: Context
  private val url = BuildConfig.SUPABASE_URL.trimEnd('/')
  private val key = BuildConfig.SUPABASE_KEY
  val configured get() = url.isNotEmpty() && key.isNotEmpty()
  private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
  private val lock = Mutex()
  private val json = Json { ignoreUnknownKeys = true }

  data class Session(val access: String, val refresh: String, val expiresAt: Long, val userId: String, val email: String?)
  var session by mutableStateOf<Session?>(null); private set
  var state by mutableStateOf(State()); private set
  var syncing by mutableStateOf(false); private set
  var error by mutableStateOf<String?>(null)
  val signedIn get() = session != null
  val me get() = session?.userId

  class CloudError(message: String) : Exception(message)

  // ------------------------------------------------------------ storage

  private fun prefs() = ctx.getSharedPreferences("paisa-cloud", Context.MODE_PRIVATE)
  private val cacheFile get() = File(ctx.filesDir, "cloud-cache.json")
  private var raw: JsonObject = JsonObject(emptyMap())

  fun init(c: Context) {
    ctx = c.applicationContext
    session = runCatching { SecureText.get(ctx, "cloud.session")?.let { s ->
      val o = json.parseToJsonElement(s).jsonObject
      Session(o.str("access")!!, o.str("refresh")!!, o.long("expiresAt") ?: 0L, o.str("userId")!!, o.str("email"))
    } }.getOrNull()
    raw = runCatching { json.parseToJsonElement(cacheFile.readText()).jsonObject }.getOrDefault(JsonObject(emptyMap()))
    state = parseState(raw)
    if (configured) WorkManager.getInstance(ctx).enqueueUniquePeriodicWork("cloud-sync", ExistingPeriodicWorkPolicy.KEEP,
      PeriodicWorkRequestBuilder<CloudWorker>(15, TimeUnit.MINUTES)
        .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()).build())
    // Push what you change (debounced) while signed in.
    scope.launch {
      var last: Db? = null
      Store.db.collect { d ->
        if (last != null && d !== last && signedIn) { delay(4000); if (Store.value === d) syncSoon() }
        last = d
      }
    }
  }

  private fun saveSession(s: Session?) {
    session = s
    SecureText.set(ctx, "cloud.session", s?.let {
      buildJsonObject { put("access", it.access); put("refresh", it.refresh); put("expiresAt", it.expiresAt); put("userId", it.userId); put("email", it.email) }.toString()
    })
  }

  // ------------------------------------------------------------ HTTP

  private fun http(method: String, path: String, body: JsonElement?, auth: Boolean): JsonElement? {
    if (!configured) throw CloudError("Accounts aren't set up in this build yet.")
    val c = URL(url + path).openConnection() as HttpURLConnection
    c.requestMethod = method; c.connectTimeout = 15000; c.readTimeout = 30000
    c.setRequestProperty("apikey", key)
    c.setRequestProperty("Content-Type", "application/json")
    if (auth) session?.let { c.setRequestProperty("Authorization", "Bearer ${it.access}") }
    if (body != null) { c.doOutput = true; c.outputStream.use { it.write(body.toString().toByteArray()) } }
    val code = c.responseCode
    val text = (if (code in 200..299) c.inputStream else c.errorStream)?.bufferedReader()?.use { it.readText() }.orEmpty()
    if (code !in 200..299) {
      val o = runCatching { json.parseToJsonElement(text).jsonObject }.getOrNull()
      val msg = o?.let { it.str("message") ?: it.str("msg") ?: it.str("error_description") ?: it.str("error") }
      if (code == 401 && auth) throw Unauthorized()
      throw CloudError(friendly(msg ?: "Error $code"))
    }
    return if (text.isBlank()) null else json.parseToJsonElement(text)
  }
  private class Unauthorized : Exception()

  private fun friendly(m: String) = when {
    m.contains("rate limit", true) || m.contains("security purposes", true) -> "Too many tries. Wait a minute and try again."
    m.contains("invalid login", true) -> "Wrong email or password."
    m.contains("already registered", true) || m.contains("already been registered", true) -> "That email already has an account. Sign in instead."
    m.contains("password", true) && m.contains("characters", true) -> "Use a longer password (at least 8 characters)."
    m.contains("Not signed in") -> "Please sign in again."
    else -> m
  }

  private suspend fun ensureFresh() {
    val s = session ?: throw CloudError("Please sign in.")
    if (System.currentTimeMillis() < s.expiresAt - 60_000) return
    val r = http("POST", "/auth/v1/token?grant_type=refresh_token", buildJsonObject { put("refresh_token", s.refresh) }, false)!!.jsonObject
    saveSession(sessionFrom(r, s.email))
  }

  private fun sessionFrom(r: JsonObject, email: String?) = Session(
    r.str("access_token")!!, r.str("refresh_token")!!, System.currentTimeMillis() + (r.long("expires_in") ?: 3600L) * 1000,
    r["user"]!!.jsonObject.str("id")!!, r["user"]!!.jsonObject.str("email") ?: email)

  /** Calls a database function as you. */
  suspend fun rpc(name: String, args: JsonObject = JsonObject(emptyMap())): JsonElement? = withContext(Dispatchers.IO) {
    ensureFresh()
    try { http("POST", "/rest/v1/rpc/$name", args, true) }
    catch (_: Unauthorized) {
      session = session?.copy(expiresAt = 0); ensureFresh()
      try { http("POST", "/rest/v1/rpc/$name", args, true) } catch (_: Unauthorized) { saveSession(null); throw CloudError("Please sign in again.") }
    }
  }

  // ------------------------------------------------------------ sign in

  // Email + password, no emails sent (the CI setup turns email confirmation off).

  suspend fun signUp(email: String, password: String) = signInWith("/auth/v1/signup", email, password)
  suspend fun signIn(email: String, password: String) = signInWith("/auth/v1/token?grant_type=password", email, password)

  private suspend fun signInWith(path: String, email: String, password: String) = withContext(Dispatchers.IO) {
    val e = email.trim().lowercase()
    val r = http("POST", path, buildJsonObject { put("email", e); put("password", password) }, false)!!.jsonObject
    if (r["access_token"] == null) throw CloudError("Account made, but sign-in needs email confirmation. Ask for the build to be run again, then sign in.")
    val s = sessionFrom(r, e)
    if (s.userId != prefs().getString("cloud.user", null)) resetLocal()
    prefs().edit().putString("cloud.user", s.userId).apply()
    saveSession(s)
    syncNow()
  }

  suspend fun changePassword(password: String) = withContext(Dispatchers.IO) {
    ensureFresh(); http("PUT", "/auth/v1/user", buildJsonObject { put("password", password) }, true); Unit
  }

  /** Signs out on this phone. Shared items stay in your splits. */
  fun signOut() { saveSession(null) }

  suspend fun deleteAccount() {
    rpc("delete_account"); saveSession(null); resetLocal()
    Store.update { d -> d.copy(friends = d.friends.map { if (it.userId != null) it.copy(userId = null) else it }) }
  }

  private fun resetLocal() {
    raw = JsonObject(emptyMap()); state = State(); cacheFile.delete()
    prefs().edit().remove("cloud.pushed").remove("cloud.notified").apply()
  }

  // ------------------------------------------------------------ profile and people

  suspend fun updateProfile(username: String?, name: String?, upi: String?, phone: String?) {
    rpc("update_profile", buildJsonObject {
      put("p_username", username); put("p_display_name", name); put("p_upi_id", upi); put("p_phone", phone); put("p_color", null as String?)
    }); syncNow()
  }
  suspend fun usernameAvailable(u: String) = rpc("username_available", buildJsonObject { put("p_username", u) })?.jsonPrimitive?.booleanOrNull == true
  suspend fun find(q: String): List<Person> = (rpc("find_people", buildJsonObject { put("q", q) }) as? JsonArray).orEmpty().map { person(it.jsonObject) }
  suspend fun matchContacts(phones: List<String>): List<Pair<Person, String>> {
    val hashes = phones.mapNotNull { p -> CloudLogic.phoneHash(p)?.let { it to p } }.toMap()
    if (hashes.isEmpty()) return emptyList()
    return (rpc("match_contacts", buildJsonObject { put("hashes", JsonArray(hashes.keys.map { JsonPrimitive(it) })) }) as? JsonArray).orEmpty()
      .map { it.jsonObject }.map { person(it) to (hashes[it.str("phone_hash")] ?: "") }
  }
  suspend fun connect(userId: String): Person { val p = person(rpc("connect", buildJsonObject { put("p_friend", userId) })!!.jsonObject); syncNow(); return p }
  suspend fun disconnect(userId: String) { rpc("disconnect", buildJsonObject { put("p_friend", userId) }); syncNow() }
  suspend fun inviteCode(): String = rpc("create_invite")!!.jsonPrimitive.content
  fun inviteLink(code: String) = "https://porifiro123.github.io/paisa-pulse/invite/#c=$code&n=" +
    java.net.URLEncoder.encode(state.me?.label ?: "", "UTF-8").replace("+", "%20")
  suspend fun acceptInvite(code: String): Person { val p = person(rpc("accept_invite", buildJsonObject { put("p_code", code) })!!.jsonObject); syncNow(); return p }

  /** Links a friend in your splits to a Paisa Pulse account (or unlinks with null). */
  fun link(friendId: String, userId: String?) {
    Store.update { d -> d.copy(friends = d.friends.map { if (it.id == friendId) it.copy(userId = userId) else it }) }
  }

  suspend fun respondShare(expenseId: String, accept: Boolean) { rpc("respond_share", buildJsonObject { put("p_expense", expenseId); put("p_accept", accept) }); syncNow() }
  suspend fun respondSettlement(id: String, confirm: Boolean) { rpc("respond_settlement", buildJsonObject { put("p_id", id); put("p_confirm", confirm) }); syncNow() }
  suspend fun markRead() { if (state.unread > 0) { rpc("mark_read", buildJsonObject { put("p_ids", JsonNull) }); syncNow() } }
  suspend fun leaveSpace(id: String) { rpc("leave_space", buildJsonObject { put("p_id", id) }); syncNow() }
  suspend fun exportData(): String = rpc("export_my_data")?.toString() ?: "{}"

  // ------------------------------------------------------------ sync

  fun syncSoon() { if (signedIn) scope.launch { runCatching { syncNow() } } }

  /** Pushes your shared changes, pulls everyone else's, and brings them into your splits. */
  suspend fun syncNow() = withContext(Dispatchers.IO) {
    if (!configured || !signedIn) return@withContext
    lock.withLock {
      syncing = true
      try {
        push()
        pull(prefs().getString("cloud.since", null))
        error = null
      } catch (e: CloudError) { error = e.message } catch (e: java.io.IOException) { error = "No connection. Will try again." }
      finally { syncing = false }
    }
  }

  private suspend fun pull(since: String?) {
    val r = rpc("sync", buildJsonObject { put("p_since", since) })!!.jsonObject
    raw = mergeRaw(raw, r)
    cacheFile.writeText(raw.toString())
    prefs().edit().putString("cloud.since", r.str("server_time")).apply()
    val s = parseState(raw)
    state = s
    val me = me ?: return
    val base = Money.base
    val rates = Currency.cached(ctx)?.inrPer
    val toBase = { a: Long, c: String -> if (c == base) a else rates?.let { Fx.rate(c, base, it) }?.let { Math.round(a * it) } }
    withContext(Dispatchers.Main) {
      // Only write when something changed, so a sync doesn't set off another one.
      val cur = Store.value
      if (CloudLogic.mirror(cur, s, me, base, toBase) != cur) Store.update { d -> CloudLogic.mirror(d, s, me, base, toBase) }
    }
    notifyNew(s)
  }

  private suspend fun push() {
    val me = me ?: return
    val db = Store.value
    val foreign = state.spaces.filter { it.createdBy != me }.map { it.id }.toSet()
    val plan = CloudLogic.plan(db, me, Money.base, foreign)
    val pushed = CloudLogic.decodePushed(prefs().getString("cloud.pushed", null)).toMutableMap()
    val (save, remove) = CloudLogic.diff(plan, pushed)
    val hashes = plan.hashes()
    fun keep() = prefs().edit().putString("cloud.pushed", CloudLogic.encodePushed(pushed)).apply()
    for (k in save.sortedBy { if (it.startsWith("g:")) 0 else 1 }) {
      val id = k.substring(2)
      runCatching {
        when (k[0]) {
          'g' -> plan.spaces.first { it.id == id }.let { s -> rpc("save_space", buildJsonObject {
            put("p_id", s.id); put("p_kind", s.kind); put("p_name", s.name); put("p_data", s.trip?.let { tripJson(it) } ?: JsonObject(emptyMap()))
            put("p_members", JsonArray(s.members.map { JsonPrimitive(it) }))
          }) }
          'e' -> plan.expenses.first { it.id == id }.let { e -> rpc("save_expense", buildJsonObject {
            put("p_id", e.id); put("p_space", e.spaceId); put("p_paid_by", e.paidBy); put("p_amount", e.amount); put("p_currency", e.currency)
            put("p_original_amount", e.originalAmount); put("p_original_currency", e.originalCurrency); put("p_payee", e.payee); put("p_note", e.note)
            put("p_occurred_at", iso(e.occurredAt))
            put("p_data", buildJsonObject { if (e.others.isNotEmpty()) put("others", JsonArray(e.others.map { (n, a) -> buildJsonObject { put("name", n); put("amount", a) } })) })
            put("p_shares", JsonArray(e.shares.map { buildJsonObject { put("user", it.userId); put("amount", it.amount) } }))
          }) }
          else -> plan.settlements.first { it.id == id }.let { s -> rpc("save_settlement", buildJsonObject {
            put("p_id", s.id); put("p_space", s.spaceId); put("p_from", s.from); put("p_to", s.to); put("p_amount", s.amount)
            put("p_currency", s.currency); put("p_note", s.note)
          }) }
        }
        pushed[k] = hashes.getValue(k); keep()
      }.onFailure { if (it is CloudError) error = it.message else if (it is java.io.IOException) throw it }
    }
    for (k in remove) {
      val id = k.substring(2)
      runCatching {
        when (k[0]) {
          'g' -> rpc("leave_space", buildJsonObject { put("p_id", id) })
          'e' -> rpc("delete_expense", buildJsonObject { put("p_id", id) })
          else -> rpc("delete_settlement", buildJsonObject { put("p_id", id) })
        }
        pushed.remove(k); keep()
      }.onFailure { if (it is java.io.IOException) throw it }
    }
  }

  private fun notifyNew(s: State) {
    val seen = prefs().getLong("cloud.notified", -1)
    val fresh = s.inbox.filter { !it.read && it.id > seen }
    if (seen >= 0) fresh.take(5).forEach { Services.notify((7000 + it.id % 1000).toInt(), it.title, it.body ?: "Open Paisa Pulse to see it.") }
    (s.inbox.maxOfOrNull { it.id } ?: seen).let { prefs().edit().putLong("cloud.notified", maxOf(it, seen, 0L)).apply() }
  }

  // ------------------------------------------------------------ JSON

  private fun mergeRaw(old: JsonObject, new: JsonObject): JsonObject {
    fun merge(k: String, idKey: String = "id"): JsonArray {
      val m = LinkedHashMap<String, JsonElement>()
      (old[k] as? JsonArray).orEmpty().forEach { m[it.jsonObject[idKey].toString()] = it }
      (new[k] as? JsonArray).orEmpty().forEach { m[it.jsonObject[idKey].toString()] = it }
      return JsonArray(m.values.toList())
    }
    return buildJsonObject {
      put("me", new["me"] ?: old["me"] ?: JsonNull)
      put("people", merge("people")); put("spaces", merge("spaces")); put("expenses", merge("expenses"))
      put("settlements", merge("settlements")); put("inbox", JsonArray(merge("inbox").sortedByDescending { it.jsonObject.long("id") ?: 0L }.take(200)))
      put("server_time", new["server_time"] ?: old["server_time"] ?: JsonNull)
    }
  }

  private fun JsonObject.str(k: String) = (this[k] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.contentOrNull
  private fun JsonObject.long(k: String) = (this[k] as? JsonPrimitive)?.longOrNull
  private fun JsonObject.bool(k: String) = (this[k] as? JsonPrimitive)?.booleanOrNull
  private fun time(s: String?) = s?.let { runCatching { OffsetDateTime.parse(it).toInstant().toEpochMilli() }.getOrNull() } ?: 0L
  private fun iso(ms: Long) = java.time.Instant.ofEpochMilli(ms).toString()

  private fun person(o: JsonObject) = Person(o.str("id")!!, o.str("username"), o.str("display_name").orEmpty(), o.str("upi_id"), o.bool("connected") == true)

  private fun tripJson(t: TripShare) = buildJsonObject {
    put("kind", t.kind); put("international", t.international)
    put("places", JsonArray(t.places.map { p -> buildJsonObject { put("name", p.name); put("country", p.country); put("currency", p.currency) } }))
    put("start_at", t.startAt); put("end_at", t.endAt); put("travellers", t.travellers); put("notes", t.notes)
    put("items", JsonArray(t.items.map { i -> buildJsonObject { put("id", i.id); put("label", i.label); put("budget", i.budget) } }))
  }
  private fun trip(o: JsonObject?): TripShare? = o?.takeIf { it.containsKey("kind") }?.let { d ->
    TripShare(d.str("kind") ?: "trip", d.bool("international") == true,
      (d["places"] as? JsonArray).orEmpty().map { it.jsonObject }.map { TripPlace(it.str("name") ?: "", it.str("country"), it.str("currency")) },
      d.long("start_at"), d.long("end_at"), (d.long("travellers") ?: 1L).toInt(), d.str("notes"),
      (d["items"] as? JsonArray).orEmpty().map { it.jsonObject }.map { TripItemShare(it.str("id") ?: newId(), it.str("label") ?: "", it.long("budget")) })
  }

  private fun parseState(r: JsonObject): State {
    val me = (r["me"] as? JsonObject)
    return State(
      me = me?.let { person(it) }, email = me?.str("email"), hasPhone = me?.bool("has_phone") == true,
      people = (r["people"] as? JsonArray).orEmpty().map { person(it.jsonObject) },
      spaces = (r["spaces"] as? JsonArray).orEmpty().map { it.jsonObject }.map { o ->
        Space(o.str("id")!!, o.str("kind") ?: "group", o.str("name") ?: "", o.str("created_by") ?: "", o.str("deleted_at") != null,
          (o["members"] as? JsonArray).orEmpty().map { it.jsonObject }.map { Member(it.str("user_id")!!, it.bool("left") == true) },
          trip(o["data"] as? JsonObject))
      },
      expenses = (r["expenses"] as? JsonArray).orEmpty().map { it.jsonObject }.map { o ->
        Expense(o.str("id")!!, o.str("space_id"), o.str("created_by")!!, o.str("paid_by")!!, o.long("amount") ?: 0, o.str("currency") ?: "INR",
          o.str("payee"), o.str("note"), time(o.str("occurred_at")), o.str("deleted_at") != null,
          (o["shares"] as? JsonArray).orEmpty().map { it.jsonObject }.map { ShareRow(it.str("user_id")!!, it.long("amount") ?: 0, it.str("status") ?: "pending") })
      },
      settlements = (r["settlements"] as? JsonArray).orEmpty().map { it.jsonObject }.map { o ->
        Settlement(o.str("id")!!, o.str("space_id"), o.str("created_by")!!, o.str("from_user")!!, o.str("to_user")!!, o.long("amount") ?: 0,
          o.str("currency") ?: "INR", o.str("note"), o.str("status") ?: "pending", o.str("deleted_at") != null, time(o.str("created_at")))
      },
      inbox = (r["inbox"] as? JsonArray).orEmpty().map { it.jsonObject }.map { o ->
        InboxItem(o.long("id") ?: 0, o.str("kind") ?: "", o.str("actor"), o.str("ref_id"), o.str("title") ?: "", o.str("body"),
          time(o.str("created_at")), o.str("read_at") != null)
      },
      since = r.str("server_time"),
    )
  }
}

class CloudWorker(c: Context, p: WorkerParameters) : CoroutineWorker(c, p) {
  override suspend fun doWork(): Result { runCatching { Cloud.syncNow() }; return Result.success() }
}

/** Small secrets (the sign-in session) encrypted with a key in the Android Keystore. */
object SecureText {
  private const val ALIAS = "paisa_cloud_session"
  private fun prefs(c: Context) = c.getSharedPreferences("paisa_secure", Context.MODE_PRIVATE)
  private fun key(): javax.crypto.SecretKey {
    val ks = java.security.KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    (ks.getEntry(ALIAS, null) as? java.security.KeyStore.SecretKeyEntry)?.let { return it.secretKey }
    val g = javax.crypto.KeyGenerator.getInstance(android.security.keystore.KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
    g.init(android.security.keystore.KeyGenParameterSpec.Builder(ALIAS, android.security.keystore.KeyProperties.PURPOSE_ENCRYPT or android.security.keystore.KeyProperties.PURPOSE_DECRYPT)
      .setBlockModes(android.security.keystore.KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(android.security.keystore.KeyProperties.ENCRYPTION_PADDING_NONE).build())
    return g.generateKey()
  }
  fun get(c: Context, name: String): String? = runCatching {
    val v = prefs(c).getString(name, null) ?: return null
    val (iv, data) = v.split(':').map { java.util.Base64.getDecoder().decode(it) }
    val cipher = javax.crypto.Cipher.getInstance("AES/GCM/NoPadding").apply { init(javax.crypto.Cipher.DECRYPT_MODE, key(), javax.crypto.spec.GCMParameterSpec(128, iv)) }
    String(cipher.doFinal(data), Charsets.UTF_8)
  }.getOrNull()
  fun set(c: Context, name: String, value: String?) {
    if (value == null) { prefs(c).edit().remove(name).apply(); return }
    val cipher = javax.crypto.Cipher.getInstance("AES/GCM/NoPadding").apply { init(javax.crypto.Cipher.ENCRYPT_MODE, key()) }
    val b = java.util.Base64.getEncoder()
    prefs(c).edit().putString(name, b.encodeToString(cipher.iv) + ":" + b.encodeToString(cipher.doFinal(value.toByteArray()))).apply()
  }
}
