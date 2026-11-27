package com.paisapulse.app.logic

import com.paisapulse.app.data.*

// Accounts and sharing: the pure part, the same on iPhone (apple/Shared/CloudLogic.swift).
//
// Only shared things go to the server (supabase/migrations). Two rules keep both sides right:
//  - What you record is pushed from your phone: `plan` turns your splits with linked friends
//    (Friend.userId) into shared expenses, settle-ups, groups and trips. The phone stays the truth
//    for them; `pushed` hashes stop repeats and notice deletions.
//  - What others record comes back through `mirror`, as split entries with ids starting "c:"
//    (never pushed back), friends for the people involved, and their shared groups and trips.

object CloudLogic {
  const val MIRROR = "c:"
  val SETTLE_NOTES = setOf("Settled up", "Paid by UPI")

  private fun sha256(s: String) = java.security.MessageDigest.getInstance("SHA-256").digest(s.toByteArray())
    .joinToString("") { "%02x".format(it) }

  /** Last 10 digits, hashed: the same as the server's _phone_hash. */
  fun phoneHash(phone: String?): String? = phone?.filter { it.isDigit() }?.takeIf { it.length >= 10 }?.let { sha256(it.takeLast(10)) }
  fun emailHash(email: String) = sha256(email.trim().lowercase())
  fun validUsername(u: String) = Regex("^[a-z0-9_]{3,20}$").matches(u)
  fun cleanUsername(u: String) = u.trim().removePrefix("@").lowercase().filter { it.isLetterOrDigit() || it == '_' }.take(20)

  // ------------------------------------------------------------ server state (parsed by the client)

  data class Person(val id: String, val username: String?, val name: String, val upiId: String?, val connected: Boolean) {
    val label get() = name.ifBlank { username?.let { "@$it" } ?: "Someone" }
  }
  data class Member(val userId: String, val left: Boolean)
  data class TripItemShare(val id: String, val label: String, val budget: Long?)
  data class TripShare(
    val kind: String, val international: Boolean, val places: List<TripPlace>, val startAt: Long?, val endAt: Long?,
    val travellers: Int, val notes: String?, val items: List<TripItemShare>,
  )
  data class Space(val id: String, val kind: String, val name: String, val createdBy: String, val deleted: Boolean,
                   val members: List<Member>, val trip: TripShare?)
  data class ShareRow(val userId: String, val amount: Long, val status: String)
  data class Expense(
    val id: String, val spaceId: String?, val createdBy: String, val paidBy: String, val amount: Long, val currency: String,
    val payee: String?, val note: String?, val occurredAt: Long, val deleted: Boolean, val shares: List<ShareRow>,
  ) { val title get() = payee?.takeIf { it.isNotBlank() } ?: note?.takeIf { it.isNotBlank() } ?: "Expense" }
  data class Settlement(val id: String, val spaceId: String?, val createdBy: String, val from: String, val to: String,
                        val amount: Long, val currency: String, val note: String?, val status: String, val deleted: Boolean, val at: Long)
  data class InboxItem(val id: Long, val kind: String, val actor: String?, val refId: String?, val title: String, val body: String?,
                       val at: Long, val read: Boolean)
  data class State(
    val me: Person? = null, val email: String? = null, val hasPhone: Boolean = false,
    val people: List<Person> = emptyList(), val spaces: List<Space> = emptyList(), val expenses: List<Expense> = emptyList(),
    val settlements: List<Settlement> = emptyList(), val inbox: List<InboxItem> = emptyList(), val since: String? = null,
  ) {
    fun person(id: String?) = people.firstOrNull { it.id == id } ?: me?.takeIf { it.id == id }
    /** Merge a sync response (changed rows only) into what we had. */
    fun merge(n: State) = State(
      me = n.me ?: me, email = n.email ?: email, hasPhone = if (n.me != null) n.hasPhone else hasPhone,
      people = (people.associateBy { it.id } + n.people.associateBy { it.id }).values.toList(),
      spaces = (spaces.associateBy { it.id } + n.spaces.associateBy { it.id }).values.toList(),
      expenses = (expenses.associateBy { it.id } + n.expenses.associateBy { it.id }).values.toList(),
      settlements = (settlements.associateBy { it.id } + n.settlements.associateBy { it.id }).values.toList(),
      inbox = (inbox.associateBy { it.id } + n.inbox.associateBy { it.id }).values.sortedByDescending { it.at }.take(200),
      since = n.since ?: since,
    )
    /** Expenses others added that wait for your yes. */
    fun pendingShares(me: String) = expenses.filter { e -> !e.deleted && e.createdBy != me && e.shares.any { it.userId == me && it.status == "pending" } }
    /** Settle-ups others recorded that wait for your confirmation. */
    fun pendingSettlements(me: String) = settlements.filter { !it.deleted && it.createdBy != me && it.status == "pending" && (it.from == me || it.to == me) }
    val unread get() = inbox.count { !it.read }
  }

  // ------------------------------------------------------------ push

  data class ShareOut(val userId: String, val amount: Long)
  data class ExpenseOut(
    val id: String, val spaceId: String?, val paidBy: String, val amount: Long, val currency: String,
    val originalAmount: Long?, val originalCurrency: String?, val payee: String?, val note: String?, val occurredAt: Long,
    val shares: List<ShareOut>, val others: List<Pair<String, Long>>,
  )
  data class SettlementOut(val id: String, val spaceId: String?, val from: String, val to: String, val amount: Long, val currency: String, val note: String?)
  data class SpaceOut(val id: String, val kind: String, val name: String, val members: List<String>, val trip: TripShare?)
  data class Plan(val spaces: List<SpaceOut>, val expenses: List<ExpenseOut>, val settlements: List<SettlementOut>) {
    /** Keys and content hashes for change detection ("g:", "e:", "s:" + id). */
    fun hashes(): Map<String, String> =
      spaces.associate { "g:${it.id}" to it.hashCode().toString() } + expenses.associate { "e:${it.id}" to it.hashCode().toString() } +
        settlements.associate { "s:${it.id}" to it.hashCode().toString() }
  }

  fun tripShare(t: Trip, items: List<TripItem>) = TripShare(t.kind, t.international, t.places, t.startAt, t.endAt, t.travellers, t.notes,
    items.filter { it.tripId == t.id }.sortedBy { it.sortOrder }.map { TripItemShare(it.id, it.label, it.budget) })

  /**
   * What your phone should have on the server. [foreign] = ids of groups and trips other people made
   * (mirrored here; they push those, not you).
   */
  fun plan(db: Db, me: String, base: String, foreign: Set<String>): Plan {
    val userOf = db.friends.filter { it.userId != null }.associate { it.id to it.userId!! }
    val friendName = db.friends.associate { it.id to it.name }
    val groups = db.splitGroups.associateBy { it.id }
    val tripOfGroup = db.trips.filter { it.groupId != null }.associateBy { it.groupId!! }
    fun linked(g: SplitGroup?) = g?.memberIds?.mapNotNull { userOf[it] }?.distinct() ?: emptyList()

    val spaces = mutableListOf<SpaceOut>()
    db.trips.filter { it.id !in foreign && it.archivedAt == null }.forEach { t ->
      val members = linked(t.groupId?.let { groups[it] })
      if (members.isNotEmpty()) spaces += SpaceOut(t.id, "trip", t.name, members, tripShare(t, db.tripItems))
    }
    db.splitGroups.filter { it.id !in foreign && it.id !in tripOfGroup }.forEach { g ->
      val members = linked(g)
      if (members.isNotEmpty()) spaces += SpaceOut(g.id, "group", g.name, members, null)
    }
    val shared = spaces.map { it.id }.toSet() + foreign
    fun spaceFor(tripId: String?, groupId: String?): String? =
      tripId?.takeIf { it in shared } ?: groupId?.let { g -> tripOfGroup[g]?.id?.takeIf { it in shared } ?: g.takeIf { it in shared } }

    val expenses = mutableListOf<ExpenseOut>()
    val settlements = mutableListOf<SettlementOut>()
    val shareOf = db.txnSplitShares.associate { it.id to it.share }
    val own = db.splitEntries.filter { !it.id.startsWith(MIRROR) }
    val byTxn = own.filter { it.txnId != null }.groupBy { it.txnId!! }
    db.liveTxns.filter { it.kind == TxnType.Expense }.forEach { t ->
      val entries = byTxn[t.id] ?: return@forEach
      if (entries.none { userOf[it.friendId] != null }) return@forEach
      val mine = shareOf[t.id] ?: t.splitShare ?: maxOf(0, t.amount - entries.sumOf { maxOf(0, it.amount) })
      val shares = listOf(ShareOut(me, mine)) + entries.filter { userOf[it.friendId] != null && it.amount > 0 }
        .groupBy { userOf[it.friendId]!! }.map { (u, v) -> ShareOut(u, v.sumOf { it.amount }) }
      val others = entries.filter { userOf[it.friendId] == null && it.amount > 0 }.map { (friendName[it.friendId] ?: "Friend") to it.amount }
      expenses += ExpenseOut(t.id, spaceFor(t.tripId, entries.firstNotNullOfOrNull { it.groupId }), me, t.amount, base,
        t.originalAmount, t.currency, t.payee, t.note, t.occurredAt, shares, others)
    }
    own.filter { it.txnId == null && it.amount != 0L }.forEach { e ->
      val u = userOf[e.friendId] ?: return@forEach
      val v = kotlin.math.abs(e.amount)
      val space = spaceFor(null, e.groupId)
      if (e.note in SETTLE_NOTES) {
        settlements += if (e.amount > 0) SettlementOut(e.id, space, me, u, v, base, e.note) else SettlementOut(e.id, space, u, me, v, base, e.note)
      } else {
        // amount > 0: you paid and they owe you; < 0: they paid and you owe them.
        val shares = if (e.amount > 0) listOf(ShareOut(me, 0), ShareOut(u, v)) else listOf(ShareOut(u, 0), ShareOut(me, v))
        expenses += ExpenseOut(e.id, space, if (e.amount > 0) me else u, v, base, null, null, e.note, null, e.occurredAt, shares, emptyList())
      }
    }
    return Plan(spaces, expenses, settlements)
  }

  // ------------------------------------------------------------ mirror

  /**
   * Brings what others shared into your data. [toBase] converts an amount in another currency to your
   * main currency (null when no rate: such rows wait).
   */
  /** A name as people type it: lowercase, no leading @, single spaces. */
  private fun key(n: String) = n.trim().removePrefix("@").lowercase().replace(Regex("\\s+"), " ")

  /**
   * One person, one row. A friend you added just by name (no account) who has the same name or @username as
   * someone you're connected to is that person: link them (no linked row yet) or fold them into the linked row,
   * moving their splits, group places and loans. Only when exactly one unlinked friend matches, so two
   * different people called the same aren't joined by a guess.
   */
  fun mergeDuplicates(db: Db, people: List<Person>): Db {
    var d = db
    people.forEach { p ->
      val names = listOfNotNull(p.name.takeIf { it.isNotBlank() }, p.username).map(::key).toSet()
      if (names.isEmpty()) return@forEach
      val loose = d.friends.filter { it.userId == null && key(it.name) in names }
      if (loose.size != 1) return@forEach
      val c = loose.single()
      val linked = d.friends.firstOrNull { it.userId == p.id }
      d = if (linked == null) d.copy(friends = d.friends.map { if (it.id == c.id) it.copy(userId = p.id, upiId = it.upiId ?: p.upiId) else it })
      else {
        val keep = linked.copy(phone = linked.phone ?: c.phone, upiId = linked.upiId ?: c.upiId)
        d.copy(
          friends = d.friends.filter { it.id != c.id }.map { if (it.id == linked.id) keep else it },
          splitEntries = d.splitEntries.map { if (it.friendId == c.id) it.copy(friendId = linked.id) else it },
          splitGroups = d.splitGroups.map { g -> if (c.id in g.memberIds) g.copy(memberIds = g.memberIds.map { if (it == c.id) linked.id else it }.distinct()) else g },
          loans = d.loans.map { if (it.friendId == c.id) it.copy(friendId = linked.id) else it },
        )
      }
    }
    return d
  }

  fun mirror(db0: Db, s: State, me: String, base: String, toBase: (Long, String) -> Long? = { a, c -> if (c == base) a else null }): Db {
    val db = mergeDuplicates(db0, s.people)
    var friends = db.friends
    val friendOf = mutableMapOf<String, String>()
    friends.forEach { f -> f.userId?.let { friendOf.putIfAbsent(it, f.id) } }
    s.people.forEach { p ->
      val existing = friends.firstOrNull { it.userId == p.id }
      if (existing == null) {
        friends = friends + Friend(id = p.id, name = p.label, upiId = p.upiId, userId = p.id); friendOf[p.id] = p.id
      } else if (existing.id == p.id && (existing.name != p.label || existing.upiId != p.upiId)) {
        friends = friends.map { if (it.id == p.id) it.copy(name = p.label, upiId = p.upiId) else it }
      } else if (existing.upiId == null && p.upiId != null) {
        friends = friends.map { if (it.id == existing.id) it.copy(upiId = p.upiId) else it }
      }
    }
    fun friend(u: String) = friendOf[u]

    var groups = db.splitGroups
    var trips = db.trips
    var items = db.tripItems
    s.spaces.filter { it.createdBy != me }.forEach { sp ->
      val gone = sp.deleted || sp.members.none { it.userId == me && !it.left }
      val members = sp.members.filter { !it.left && it.userId != me }.mapNotNull { friend(it.userId) }
      val g = groups.firstOrNull { it.id == sp.id }
      if (!gone) groups = if (g == null) groups + SplitGroup(id = sp.id, name = sp.name, memberIds = members)
        else groups.map { if (it.id == sp.id) it.copy(name = sp.name, memberIds = members) else it }
      if (sp.kind == "trip" && sp.trip != null) {
        val d = sp.trip
        val old = trips.firstOrNull { it.id == sp.id }
        if (gone) { if (old != null && old.archivedAt == null) trips = trips.map { if (it.id == sp.id) it.copy(archivedAt = now()) else it } }
        else {
          val t = (old ?: Trip(id = sp.id, name = sp.name)).copy(name = sp.name, kind = d.kind, international = d.international, places = d.places,
            startAt = d.startAt, endAt = d.endAt, travellers = d.travellers, notes = d.notes, groupId = sp.id, updatedAt = now())
          trips = if (old == null) trips + t else trips.map { if (it.id == sp.id) t else it }
          items = items.filterNot { it.tripId == sp.id } + d.items.mapIndexed { i, it -> TripItem(it.id, sp.id, it.label, it.budget, i) }
        }
      }
    }
    val groupIds = groups.map { it.id }.toSet()

    var entries = db.splitEntries
    fun drop(prefix: String) { entries = entries.filterNot { it.id.startsWith(prefix) } }
    s.expenses.filter { it.createdBy != me }.forEach { e ->
      drop("$MIRROR${e.id}:")
      if (e.deleted) return@forEach
      val my = e.shares.firstOrNull { it.userId == me }
      if (my == null || my.status != "accepted") return@forEach
      val group = e.spaceId?.takeIf { it in groupIds }
      if (e.paidBy == me) {
        e.shares.filter { it.userId != me && it.status != "rejected" && it.amount > 0 }.forEach { sh ->
          val f = friend(sh.userId) ?: return@forEach
          val a = toBase(sh.amount, e.currency) ?: return@forEach
          entries = entries + SplitEntry("$MIRROR${e.id}:${sh.userId}", f, null, a, e.title, e.occurredAt, e.occurredAt, group)
        }
      } else if (my.amount > 0) {
        val f = friend(e.paidBy) ?: return@forEach
        val a = toBase(my.amount, e.currency) ?: return@forEach
        entries = entries + SplitEntry("$MIRROR${e.id}:$me", f, null, -a, e.title, e.occurredAt, e.occurredAt, group)
      }
    }
    s.settlements.filter { it.createdBy != me }.forEach { st ->
      val id = "${MIRROR}settle:${st.id}"
      drop(id)
      if (st.deleted || st.status != "confirmed") return@forEach
      val other = if (st.to == me) st.from else st.to
      val f = friend(other) ?: return@forEach
      val a = toBase(st.amount, st.currency) ?: return@forEach
      entries = entries + SplitEntry(id, f, null, if (st.to == me) -a else a, st.note ?: "Settled up", st.at, st.at, st.spaceId?.takeIf { it in groupIds })
    }
    return db.copy(friends = friends, splitGroups = groups, trips = trips, tripItems = items, splitEntries = entries)
  }

  /** Changes to send: (kind+id, what) to save, and kind+ids to remove. */
  fun diff(plan: Plan, pushed: Map<String, String>): Pair<List<String>, List<String>> {
    val now = plan.hashes()
    return now.filter { (k, h) -> pushed[k] != h }.keys.toList() to pushed.keys.filter { it !in now }
  }

  fun encodePushed(m: Map<String, String>) = m.entries.joinToString(";") { "${it.key}=${it.value}" }
  fun decodePushed(s: String?): Map<String, String> = s.orEmpty().split(';').mapNotNull { p ->
    p.split('=', limit = 2).takeIf { it.size == 2 }?.let { it[0] to it[1] }
  }.toMap()
}
