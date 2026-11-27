package com.paisapulse.app

import com.paisapulse.app.data.*
import com.paisapulse.app.logic.CloudLogic
import com.paisapulse.app.logic.CloudLogic.Expense
import com.paisapulse.app.logic.CloudLogic.Member
import com.paisapulse.app.logic.CloudLogic.Person
import com.paisapulse.app.logic.CloudLogic.Settlement
import com.paisapulse.app.logic.CloudLogic.ShareRow
import com.paisapulse.app.logic.CloudLogic.Space
import com.paisapulse.app.logic.CloudLogic.State
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Accounts and sharing: push plan and mirror (same cases as iOS CloudTests). */
class CloudTest {
  private val me = "00000000-0000-0000-0000-00000000000a"
  private val rit = "00000000-0000-0000-0000-00000000000b"
  private val chai = "00000000-0000-0000-0000-00000000000c"

  @Test fun hashesAndUsernames() {
    // Same as the server's _phone_hash: last 10 digits.
    assertEquals(CloudLogic.phoneHash("+91 98450 11111"), CloudLogic.phoneHash("09845011111"))
    assertEquals("c34c5fa7890f3a32952f6a2d9745f56e3988343bb2a9b994e77cb9c7fd484226", CloudLogic.phoneHash("9845011111"))
    assertNull(CloudLogic.phoneHash("12345"))
    assertEquals(CloudLogic.emailHash("Nishit@X.com "), CloudLogic.emailHash("nishit@x.com"))
    assertTrue(CloudLogic.validUsername("chai_lover"))
    assertTrue(!CloudLogic.validUsername("ab") && !CloudLogic.validUsername("Nishit"))
    assertEquals("nishit_k", CloudLogic.cleanUsername("@Nishit_K!"))
  }

  private fun base(): Db {
    val acc = Account(id = "acc", name = "Axis", type = "bank")
    val r = Friend(id = "f-rit", name = "Ritwik", userId = rit)
    val local = Friend(id = "f-amma", name = "Amma")
    val dinner = Txn(id = "11111111-0000-0000-0000-000000000001", amount = 300_000, accountId = "acc", payee = "Toit", occurredAt = 1000)
    return Db(accounts = listOf(acc), friends = listOf(r, local), transactions = listOf(dinner),
      txnSplitShares = listOf(Share(dinner.id, 100_000)),
      splitEntries = listOf(
        SplitEntry(id = "e1", friendId = "f-rit", txnId = dinner.id, amount = 100_000),
        SplitEntry(id = "e2", friendId = "f-amma", txnId = dinner.id, amount = 100_000),
        SplitEntry(id = "22222222-0000-0000-0000-000000000002", friendId = "f-rit", amount = -50_000, note = "Auto", occurredAt = 2000),
        SplitEntry(id = "33333333-0000-0000-0000-000000000003", friendId = "f-rit", amount = 20_000, note = "Paid by UPI", occurredAt = 3000),
        SplitEntry(id = "e5", friendId = "f-amma", amount = 900, note = "Chai"),
      ))
  }

  @Test fun planPushesOnlyLinkedSplits() {
    val p = CloudLogic.plan(base(), me, "INR", emptySet())
    assertEquals(2, p.expenses.size)
    val dinner = p.expenses.first { it.payee == "Toit" }
    assertEquals(me, dinner.paidBy)
    assertEquals(listOf(CloudLogic.ShareOut(me, 100_000), CloudLogic.ShareOut(rit, 100_000)), dinner.shares)
    assertEquals(listOf("Amma" to 100_000L), dinner.others)
    val auto = p.expenses.first { it.payee == "Auto" }
    assertEquals(rit, auto.paidBy)
    assertEquals(listOf(CloudLogic.ShareOut(rit, 0), CloudLogic.ShareOut(me, 50_000)), auto.shares)
    assertEquals(1, p.settlements.size)
    assertEquals(me, p.settlements[0].from); assertEquals(rit, p.settlements[0].to); assertEquals(20_000L, p.settlements[0].amount)
    assertTrue(p.spaces.isEmpty())
  }

  @Test fun tripsAndGroupsBecomeSpaces() {
    val db = base().let { d ->
      val g = SplitGroup(id = "g1", name = "Goa gang", memberIds = listOf("f-rit", "f-amma"))
      val t = Trip(id = "t1", name = "Goa", groupId = "g1", startAt = 1, endAt = 2)
      val flat = SplitGroup(id = "g2", name = "Flat", memberIds = listOf("f-rit"))
      d.copy(splitGroups = listOf(g, flat, SplitGroup(id = "g3", name = "Family", memberIds = listOf("f-amma"))), trips = listOf(t),
        tripItems = listOf(TripItem(id = "i1", tripId = "t1", label = "Stay", budget = 1_000_000)),
        transactions = d.transactions.map { it.copy(tripId = "t1") })
    }
    val p = CloudLogic.plan(db, me, "INR", emptySet())
    assertEquals(listOf("t1" to "trip", "g2" to "group"), p.spaces.map { it.id to it.kind })
    assertEquals(listOf(rit), p.spaces[0].members)
    assertEquals("Stay", p.spaces[0].trip!!.items.single().label)
    assertEquals("t1", p.expenses.first { it.payee == "Toit" }.spaceId)
    // Spaces other people made are theirs to push.
    assertEquals(listOf("g2"), CloudLogic.plan(db, me, "INR", setOf("t1")).spaces.map { it.id })
  }

  @Test fun diffFindsChangesAndRemovals() {
    val p = CloudLogic.plan(base(), me, "INR", emptySet())
    val h = p.hashes()
    assertEquals(0, CloudLogic.diff(p, h).first.size)
    val (save, remove) = CloudLogic.diff(p, h + ("e:gone" to "1") - "s:33333333-0000-0000-0000-000000000003")
    assertEquals(listOf("s:33333333-0000-0000-0000-000000000003"), save)
    assertEquals(listOf("e:gone"), remove)
    assertEquals(h, CloudLogic.decodePushed(CloudLogic.encodePushed(h)))
  }

  @Test fun mirrorBringsInOthersSplits() {
    val s = State(
      people = listOf(Person(rit, "ritwik", "Ritwik", "rit@upi", true), Person(chai, "chai_lover", "Chai", null, false)),
      spaces = listOf(Space("s1", "trip", "Coorg", chai, false, listOf(Member(chai, false), Member(me, false), Member(rit, false)),
        CloudLogic.TripShare("weekend", false, listOf(TripPlace("Coorg")), 5, 6, 3, null, listOf(CloudLogic.TripItemShare("i9", "Stay", 500_000))))),
      expenses = listOf(
        Expense("x1", "s1", chai, chai, 90_000, "INR", "Homestay", null, 10, false,
          listOf(ShareRow(chai, 30_000, "accepted"), ShareRow(me, 30_000, "accepted"), ShareRow(rit, 30_000, "pending"))),
        Expense("x2", null, rit, me, 40_000, "INR", "Lunch", null, 11, false, listOf(ShareRow(me, 0, "accepted"), ShareRow(rit, 40_000, "accepted"))),
        Expense("x3", null, rit, rit, 10_000, "INR", "Pending", null, 12, false, listOf(ShareRow(rit, 0, "accepted"), ShareRow(me, 10_000, "pending"))),
        Expense("x4", null, rit, rit, 10_000, "USD", "Abroad", null, 13, false, listOf(ShareRow(me, 1_000, "accepted"))),
      ),
      settlements = listOf(Settlement("st1", null, rit, rit, me, 25_000, "INR", null, "confirmed", false, 20),
        Settlement("st2", null, rit, rit, me, 5_000, "INR", null, "pending", false, 21)),
    )
    val out = CloudLogic.mirror(base(), s, me, "INR") { a, c -> if (c == "INR") a else if (c == "USD") a * 85 else null }
    // Ritwik was already a friend (f-rit); Chai is new, with her account id as the friend id.
    assertEquals(3, out.friends.size)
    assertEquals("rit@upi", out.friends.first { it.id == "f-rit" }.upiId)
    val chaiFriend = out.friends.first { it.userId == chai }
    assertEquals(chai, chaiFriend.id)
    // Her trip arrives with its group (you + Ritwik) and budget items.
    val trip = out.trips.single()
    assertEquals("Coorg", trip.name); assertEquals("s1", trip.groupId)
    assertEquals(setOf("f-rit", chai), out.splitGroups.first { it.id == "s1" }.memberIds.toSet())
    assertEquals("Stay", out.tripItems.single().label)
    val mirrored = out.splitEntries.filter { it.id.startsWith("c:") }.associate { it.id to it.amount }
    assertEquals(mapOf(
      "c:x1:$me" to -30_000L,            // Chai paid the homestay: you owe her
      "c:x2:$rit" to 40_000L,            // Ritwik says you paid lunch: he owes you
      "c:x4:$me" to -85_000L,            // in USD, converted
      "c:settle:st1" to -25_000L,        // he paid you back (confirmed)
    ), mirrored)
    assertEquals("s1", out.splitEntries.first { it.id == "c:x1:$me" }.groupId)
    // Mirrored entries are never pushed back.
    assertEquals(2, CloudLogic.plan(out, me, "INR", setOf("s1")).expenses.size)
    // A deleted expense disappears on the next mirror.
    val again = CloudLogic.mirror(out, s.copy(expenses = s.expenses.map { if (it.id == "x1") it.copy(deleted = true) else it }), me, "INR")
    assertTrue(again.splitEntries.none { it.id == "c:x1:$me" })
    assertEquals(1, s.pendingShares(me).size)
    assertEquals(1, s.pendingSettlements(me).size)
  }

  @Test fun mergeKeepsOldRows() {
    val a = State(people = listOf(Person(rit, "ritwik", "R", null, true)), since = "t1")
    val b = a.merge(State(people = listOf(Person(rit, "ritwik", "Ritwik", null, true), Person(chai, null, "", null, false)), since = "t2"))
    assertEquals(listOf("Ritwik", "Someone"), b.people.map { it.label })
    assertEquals("t2", b.since)
  }

  @Test fun duplicatesFoldIntoTheLinkedFriend() {
    val linked = Friend(id = rit, name = "Ritwik", userId = rit)
    val loose = Friend(id = "f-local", name = "ritwik", phone = "9845011111")
    val other = Friend(id = "f-chai", name = "Chai")
    val db = Db(friends = listOf(linked, loose, other),
      splitEntries = listOf(SplitEntry(id = "e1", friendId = "f-local", amount = 500)),
      splitGroups = listOf(SplitGroup(id = "g", name = "Goa", memberIds = listOf("f-local", rit))),
      loans = listOf(Loan(id = "l", person = "ritwik", friendId = "f-local", amount = 100)))
    val out = CloudLogic.mergeDuplicates(db, listOf(Person(rit, "ritwik", "Ritwik", null, true)))
    assertEquals(listOf(rit, "f-chai"), out.friends.map { it.id })
    assertEquals("9845011111", out.friends.first().phone)
    assertEquals(rit, out.splitEntries.single().friendId)
    assertEquals(listOf(rit), out.splitGroups.single().memberIds)
    assertEquals(rit, out.loans.single().friendId)
    // No linked row yet: the name-only friend becomes the linked one, keeping its id.
    val linkedOnly = CloudLogic.mergeDuplicates(Db(friends = listOf(loose)), listOf(Person(rit, "ritwik", "Ritwik", null, true)))
    assertEquals(rit, linkedOnly.friends.single().userId)
    // Two name-only matches: don't guess.
    val two = Db(friends = listOf(linked, loose, loose.copy(id = "f-2")))
    assertEquals(3, CloudLogic.mergeDuplicates(two, listOf(Person(rit, "ritwik", "Ritwik", null, true))).friends.size)
  }
}
