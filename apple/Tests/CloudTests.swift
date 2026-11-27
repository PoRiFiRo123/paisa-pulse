import SwiftData
import XCTest
@testable import PaisaPulse

/// Accounts and sharing: push plan and mirror (same cases as Android CloudTest).
@MainActor
final class CloudTests: XCTestCase {
  let me = "00000000-0000-0000-0000-00000000000a"
  let rit = "00000000-0000-0000-0000-00000000000b"
  let chai = "00000000-0000-0000-0000-00000000000c"

  func testHashesAndUsernames() {
    XCTAssertEqual(CloudLogic.phoneHash("+91 98450 11111"), CloudLogic.phoneHash("09845011111"))
    XCTAssertEqual(CloudLogic.phoneHash("9845011111"), "c34c5fa7890f3a32952f6a2d9745f56e3988343bb2a9b994e77cb9c7fd484226")
    XCTAssertNil(CloudLogic.phoneHash("12345"))
    XCTAssertEqual(CloudLogic.emailHash("Nishit@X.com "), CloudLogic.emailHash("nishit@x.com"))
    XCTAssertTrue(CloudLogic.validUsername("chai_lover"))
    XCTAssertFalse(CloudLogic.validUsername("ab") || CloudLogic.validUsername("Nishit"))
    XCTAssertEqual(CloudLogic.cleanUsername("@Nishit_K!"), "nishit_k")
  }

  struct Fixture { var friends: [Friend]; var txns: [Txn]; var entries: [SplitEntry] }
  func fixture() -> Fixture {
    let dinner = Txn(id: "11111111-0000-0000-0000-000000000001", type: .expense, amount: 300_000, accountId: "acc", payee: "Toit",
                     occurredAt: Date(timeIntervalSince1970: 1), splitShare: 100_000)
    return Fixture(
      friends: [Friend(id: "f-rit", name: "Ritwik", userId: rit), Friend(id: "f-amma", name: "Amma")],
      txns: [dinner],
      entries: [
        SplitEntry(id: "e1", friendId: "f-rit", txnId: dinner.id, amount: 100_000),
        SplitEntry(id: "e2", friendId: "f-amma", txnId: dinner.id, amount: 100_000),
        SplitEntry(id: "22222222-0000-0000-0000-000000000002", friendId: "f-rit", amount: -50_000, note: "Auto"),
        SplitEntry(id: "33333333-0000-0000-0000-000000000003", friendId: "f-rit", amount: 20_000, note: "Paid by UPI"),
        SplitEntry(id: "e5", friendId: "f-amma", amount: 900, note: "Chai"),
      ])
  }

  func testPlanPushesOnlyLinkedSplits() {
    let f = fixture()
    let p = CloudLogic.plan(friends: f.friends, groups: [], trips: [], tripItems: [], txns: f.txns, entries: f.entries, me: me, base: "INR", foreign: [])
    XCTAssertEqual(p.expenses.count, 2)
    let dinner = p.expenses.first { $0.payee == "Toit" }!
    XCTAssertEqual(dinner.paidBy, me)
    XCTAssertEqual(dinner.shares, [.init(userId: me, amount: 100_000), .init(userId: rit, amount: 100_000)])
    XCTAssertEqual(dinner.others, ["Amma": 100_000])
    let auto = p.expenses.first { $0.payee == "Auto" }!
    XCTAssertEqual(auto.paidBy, rit)
    XCTAssertEqual(auto.shares, [.init(userId: rit, amount: 0), .init(userId: me, amount: 50_000)])
    XCTAssertEqual(p.settlements.count, 1)
    XCTAssertEqual(p.settlements[0].from, me); XCTAssertEqual(p.settlements[0].to, rit); XCTAssertEqual(p.settlements[0].amount, 20_000)
    XCTAssertTrue(p.spaces.isEmpty)
    // Hashes are stable, and changes and removals are found.
    let h = p.hashes()
    XCTAssertEqual(h, CloudLogic.plan(friends: f.friends, groups: [], trips: [], tripItems: [], txns: f.txns, entries: f.entries, me: me, base: "INR", foreign: []).hashes())
    var old = h; old["e:gone"] = "1"; old["s:33333333-0000-0000-0000-000000000003"] = nil
    let d = CloudLogic.diff(p, pushed: old)
    XCTAssertEqual(d.save, ["s:33333333-0000-0000-0000-000000000003"]); XCTAssertEqual(d.remove, ["e:gone"])
    XCTAssertEqual(CloudLogic.decodePushed(CloudLogic.encodePushed(h)), h)
  }

  func testTripsAndGroupsBecomeSpaces() {
    var f = fixture()
    let g = SplitGroup(id: "g1", name: "Goa gang", memberIds: ["f-rit", "f-amma"])
    let t = Trip(id: "t1", name: "Goa", startAt: .now, endAt: .now, groupId: "g1")
    let groups = [g, SplitGroup(id: "g2", name: "Flat", memberIds: ["f-rit"]), SplitGroup(id: "g3", name: "Family", memberIds: ["f-amma"])]
    f.txns[0].tripId = "t1"
    let items = [TripItem(id: "i1", tripId: "t1", label: "Stay", budget: 1_000_000)]
    let p = CloudLogic.plan(friends: f.friends, groups: groups, trips: [t], tripItems: items, txns: f.txns, entries: f.entries, me: me, base: "INR", foreign: [])
    XCTAssertEqual(p.spaces.map { "\($0.id):\($0.kind)" }, ["t1:trip", "g2:group"])
    XCTAssertEqual(p.spaces[0].members, [rit])
    XCTAssertEqual(p.spaces[0].trip?.items.first?.label, "Stay")
    XCTAssertEqual(p.expenses.first { $0.payee == "Toit" }?.spaceId, "t1")
    XCTAssertEqual(CloudLogic.plan(friends: f.friends, groups: groups, trips: [t], tripItems: items, txns: f.txns, entries: f.entries,
                                   me: me, base: "INR", foreign: ["t1"]).spaces.map(\.id), ["g2"])
  }

  func testMirrorBringsInOthersSplits() throws {
    let container = Store.makeContainer(inMemory: true)
    let context = container.mainContext
    let f = fixture()
    for x in f.friends { context.insert(x) }
    for x in f.entries { context.insert(x) }
    try context.save()
    var s = CloudLogic.State()
    s.people = [.init(id: rit, username: "ritwik", name: "Ritwik", upiId: "rit@upi", connected: true),
                .init(id: chai, username: "chai_lover", name: "Chai", upiId: nil, connected: false)]
    s.spaces = [.init(id: "s1", kind: "trip", name: "Coorg", createdBy: chai, deleted: false,
                      members: [.init(userId: chai, left: false), .init(userId: me, left: false), .init(userId: rit, left: false)],
                      trip: .init(kind: "weekend", international: false, places: [TripPlace(name: "Coorg")], startAt: 5, endAt: 6, travellers: 3,
                                  notes: nil, items: [.init(id: "i9", label: "Stay", budget: 500_000)]))]
    s.expenses = [
      .init(id: "x1", spaceId: "s1", createdBy: chai, paidBy: chai, amount: 90_000, currency: "INR", payee: "Homestay", note: nil, occurredAt: 10, deleted: false,
            shares: [.init(userId: chai, amount: 30_000, status: "accepted"), .init(userId: me, amount: 30_000, status: "accepted"), .init(userId: rit, amount: 30_000, status: "pending")]),
      .init(id: "x2", spaceId: nil, createdBy: rit, paidBy: me, amount: 40_000, currency: "INR", payee: "Lunch", note: nil, occurredAt: 11, deleted: false,
            shares: [.init(userId: me, amount: 0, status: "accepted"), .init(userId: rit, amount: 40_000, status: "accepted")]),
      .init(id: "x3", spaceId: nil, createdBy: rit, paidBy: rit, amount: 10_000, currency: "INR", payee: "Pending", note: nil, occurredAt: 12, deleted: false,
            shares: [.init(userId: rit, amount: 0, status: "accepted"), .init(userId: me, amount: 10_000, status: "pending")]),
      .init(id: "x4", spaceId: nil, createdBy: rit, paidBy: rit, amount: 10_000, currency: "USD", payee: "Abroad", note: nil, occurredAt: 13, deleted: false,
            shares: [.init(userId: me, amount: 1_000, status: "accepted")]),
    ]
    s.settlements = [.init(id: "st1", spaceId: nil, createdBy: rit, from: rit, to: me, amount: 25_000, currency: "INR", note: nil, status: "confirmed", deleted: false, at: 20),
                     .init(id: "st2", spaceId: nil, createdBy: rit, from: rit, to: me, amount: 5_000, currency: "INR", note: nil, status: "pending", deleted: false, at: 21)]
    let convert: (Int, String) -> Int? = { a, c in c == "INR" ? a : c == "USD" ? a * 85 : nil }
    CloudLogic.mirror(s, me: me, base: "INR", context: context, toBase: convert)

    let friends = try context.fetch(FetchDescriptor<Friend>())
    XCTAssertEqual(friends.count, 3)
    XCTAssertEqual(friends.first { $0.id == "f-rit" }?.upiId, "rit@upi")
    XCTAssertEqual(friends.first { $0.userId == chai }?.id, chai)
    let trip = try XCTUnwrap(try context.fetch(FetchDescriptor<Trip>()).first)
    XCTAssertEqual(trip.name, "Coorg"); XCTAssertEqual(trip.groupId, "s1")
    XCTAssertEqual(Set(try context.fetch(FetchDescriptor<SplitGroup>()).first { $0.id == "s1" }?.memberIds ?? []), ["f-rit", chai])
    XCTAssertEqual(try context.fetch(FetchDescriptor<TripItem>()).map(\.label), ["Stay"])
    let mirrored = Dictionary(try context.fetch(FetchDescriptor<SplitEntry>()).filter { $0.id.hasPrefix("c:") }.map { ($0.id, $0.amount) }, uniquingKeysWith: { a, _ in a })
    XCTAssertEqual(mirrored, ["c:x1:\(me)": -30_000, "c:x2:\(rit)": 40_000, "c:x4:\(me)": -85_000, "c:settle:st1": -25_000])
    // Mirrored entries are never pushed back.
    let all = try context.fetch(FetchDescriptor<SplitEntry>())
    XCTAssertEqual(CloudLogic.plan(friends: try context.fetch(FetchDescriptor<Friend>()), groups: [], trips: [], tripItems: [], txns: f.txns,
                                   entries: all, me: me, base: "INR", foreign: ["s1"]).expenses.count, 2)
    // A deleted expense disappears on the next mirror.
    s.expenses[0].deleted = true
    CloudLogic.mirror(s, me: me, base: "INR", context: context, toBase: convert)
    XCTAssertFalse(try context.fetch(FetchDescriptor<SplitEntry>()).contains { $0.id == "c:x1:\(me)" })
    XCTAssertEqual(s.pendingShares(me).count, 1)
    XCTAssertEqual(s.pendingSettlements(me).count, 1)
  }

  func testDuplicatesFoldIntoTheLinkedFriend() throws {
    // Keep the container alive: a context whose container is gone crashes.
    let container = Store.makeContainer(inMemory: true)
    let context = container.mainContext
    context.insert(Friend(id: rit, name: "Ritwik", userId: rit))
    context.insert(Friend(id: "f-local", name: "ritwik", phone: "9845011111"))
    context.insert(Friend(id: "f-chai", name: "Chai"))
    context.insert(SplitEntry(id: "e1", friendId: "f-local", amount: 500))
    context.insert(SplitGroup(id: "g", name: "Goa", memberIds: ["f-local", rit]))
    try context.save()
    CloudLogic.mergeDuplicates([CloudLogic.Person(id: rit, username: "ritwik", name: "Ritwik", upiId: nil, connected: true)], context: context)
    try context.save()
    let friends = try context.fetch(FetchDescriptor<Friend>()).map(\.id).sorted()
    XCTAssertEqual(friends, [rit, "f-chai"].sorted())
    XCTAssertEqual(try context.fetch(FetchDescriptor<Friend>()).first { $0.id == rit }?.phone, "9845011111")
    XCTAssertEqual(try context.fetch(FetchDescriptor<SplitEntry>()).first?.friendId, rit)
    XCTAssertEqual(try context.fetch(FetchDescriptor<SplitGroup>()).first?.memberIds, [rit])
    withExtendedLifetime(container) {}
  }
}
