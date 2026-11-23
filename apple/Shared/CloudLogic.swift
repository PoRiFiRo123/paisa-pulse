import CryptoKit
import Foundation
import SwiftData

// Accounts and sharing: the pure part, the same on Android (logic/CloudLogic.kt).
//
// Only shared things go to the server (supabase/migrations). Two rules keep both sides right:
//  - What you record is pushed from your phone: `plan` turns your splits with linked friends
//    (Friend.userId) into shared expenses, settle-ups, groups and trips. The phone stays the truth
//    for them; `pushed` hashes stop repeats and notice deletions.
//  - What others record comes back through `mirror`, as split entries with ids starting "c:"
//    (never pushed back), friends for the people involved, and their shared groups and trips.

enum CloudLogic {
  static let mirrorPrefix = "c:"
  static let settleNotes: Set<String> = ["Settled up", "Paid by UPI"]

  static func sha256(_ s: String) -> String { SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined() }
  /// Last 10 digits, hashed: the same as the server's _phone_hash.
  static func phoneHash(_ phone: String?) -> String? {
    let d = (phone ?? "").filter(\.isNumber)
    return d.count >= 10 ? sha256(String(d.suffix(10))) : nil
  }
  static func emailHash(_ email: String) -> String { sha256(email.trimmingCharacters(in: .whitespaces).lowercased()) }
  static func validUsername(_ u: String) -> Bool { u.range(of: "^[a-z0-9_]{3,20}$", options: .regularExpression) != nil }
  static func cleanUsername(_ u: String) -> String {
    var s = u.trimmingCharacters(in: .whitespaces)
    if s.hasPrefix("@") { s.removeFirst() }
    return String(s.lowercased().filter { ($0.isLetter && $0.isASCII) || $0.isNumber || $0 == "_" }.prefix(20))
  }

  // ------------------------------------------------------------ server state (parsed by the client)

  struct Person: Codable, Hashable, Identifiable {
    var id: String; var username: String?; var name: String; var upiId: String?; var connected: Bool
    var label: String { name.isEmpty ? (username.map { "@\($0)" } ?? "Someone") : name }
  }
  struct Member: Codable, Hashable { var userId: String; var left: Bool }
  struct TripItemShare: Codable, Hashable { var id: String; var label: String; var budget: Int? }
  struct TripShare: Codable, Hashable {
    var kind: String; var international: Bool; var places: [TripPlace]; var startAt: Int64?; var endAt: Int64?
    var travellers: Int; var notes: String?; var items: [TripItemShare]
  }
  struct Space: Codable, Hashable, Identifiable {
    var id, kind, name, createdBy: String; var deleted: Bool; var members: [Member]; var trip: TripShare?
  }
  struct ShareRow: Codable, Hashable { var userId: String; var amount: Int; var status: String }
  struct Expense: Codable, Hashable, Identifiable {
    var id: String; var spaceId: String?; var createdBy, paidBy: String; var amount: Int; var currency: String
    var payee, note: String?; var occurredAt: Int64; var deleted: Bool; var shares: [ShareRow]
    var title: String { [payee, note].compactMap { $0 }.first { !$0.isEmpty } ?? "Expense" }
  }
  struct Settlement: Codable, Hashable, Identifiable {
    var id: String; var spaceId: String?; var createdBy, from, to: String; var amount: Int; var currency: String
    var note: String?; var status: String; var deleted: Bool; var at: Int64
  }
  struct InboxItem: Codable, Hashable, Identifiable {
    var id: Int64; var kind: String; var actor, refId: String?; var title: String; var body: String?; var at: Int64; var read: Bool
  }
  struct State: Codable, Hashable {
    var me: Person?; var email: String?; var hasPhone = false
    var people: [Person] = []; var spaces: [Space] = []; var expenses: [Expense] = []
    var settlements: [Settlement] = []; var inbox: [InboxItem] = []; var since: String?

    func person(_ id: String?) -> Person? { people.first { $0.id == id } ?? (me?.id == id ? me : nil) }
    private static func union<T: Identifiable>(_ a: [T], _ b: [T]) -> [T] where T.ID: Hashable {
      var seen = Set<T.ID>(); var out: [T] = []
      for x in b + a where seen.insert(x.id).inserted { out.append(x) }
      return out
    }
    /// Merge a sync response (changed rows only) into what we had.
    func merge(_ n: State) -> State {
      var s = State(me: n.me ?? me, email: n.email ?? email, hasPhone: n.me != nil ? n.hasPhone : hasPhone)
      s.people = Self.union(people, n.people); s.spaces = Self.union(spaces, n.spaces)
      s.expenses = Self.union(expenses, n.expenses); s.settlements = Self.union(settlements, n.settlements)
      s.inbox = Array(Self.union(inbox, n.inbox).sorted { $0.at > $1.at }.prefix(200)); s.since = n.since ?? since
      return s
    }
    /// Expenses others added that wait for your yes.
    func pendingShares(_ me: String) -> [Expense] {
      expenses.filter { e in !e.deleted && e.createdBy != me && e.shares.contains { $0.userId == me && $0.status == "pending" } }
    }
    /// Settle-ups others recorded that wait for your confirmation.
    func pendingSettlements(_ me: String) -> [Settlement] {
      settlements.filter { !$0.deleted && $0.createdBy != me && $0.status == "pending" && ($0.from == me || $0.to == me) }
    }
    var unread: Int { inbox.filter { !$0.read }.count }
  }

  // ------------------------------------------------------------ push

  struct ShareOut: Hashable { var userId: String; var amount: Int }
  struct ExpenseOut: Hashable {
    var id: String; var spaceId: String?; var paidBy: String; var amount: Int; var currency: String
    var originalAmount: Int?; var originalCurrency: String?; var payee, note: String?; var occurredAt: Date
    var shares: [ShareOut]; var others: [String: Int]
  }
  struct SettlementOut: Hashable { var id: String; var spaceId: String?; var from, to: String; var amount: Int; var currency: String; var note: String? }
  struct SpaceOut: Hashable { var id, kind, name: String; var members: [String]; var trip: TripShare? }
  struct Plan {
    var spaces: [SpaceOut] = []; var expenses: [ExpenseOut] = []; var settlements: [SettlementOut] = []
    /// Keys and content hashes for change detection ("g:", "e:", "s:" + id).
    func hashes() -> [String: String] {
      var m: [String: String] = [:]
      for s in spaces { m["g:\(s.id)"] = String(sha256(String(describing: s)).prefix(16)) }
      for e in expenses { m["e:\(e.id)"] = String(sha256(String(describing: e)).prefix(16)) }
      for s in settlements { m["s:\(s.id)"] = String(sha256(String(describing: s)).prefix(16)) }
      return m
    }
  }

  static func tripShare(_ t: Trip, items: [TripItem]) -> TripShare {
    TripShare(kind: t.kind, international: t.international, places: t.places,
              startAt: t.startAt.map { Int64($0.timeIntervalSince1970 * 1000) }, endAt: t.endAt.map { Int64($0.timeIntervalSince1970 * 1000) },
              travellers: t.travellers, notes: t.notes,
              items: items.filter { $0.tripId == t.id }.sorted { $0.sortOrder < $1.sortOrder }.map { TripItemShare(id: $0.id, label: $0.label, budget: $0.budget) })
  }

  /// What your phone should have on the server. `foreign` = ids of groups and trips other people made.
  static func plan(friends: [Friend], groups: [SplitGroup], trips: [Trip], tripItems: [TripItem], txns: [Txn], entries: [SplitEntry],
                   me: String, base: String, foreign: Set<String>) -> Plan {
    var userOf: [String: String] = [:]
    for f in friends { if let u = f.userId { userOf[f.id] = u } }
    let friendName = Dictionary(friends.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
    let groupById = Dictionary(groups.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    var tripOfGroup: [String: Trip] = [:]
    for t in trips { if let g = t.groupId, tripOfGroup[g] == nil { tripOfGroup[g] = t } }
    func linked(_ g: SplitGroup?) -> [String] {
      var seen = Set<String>()
      return (g?.memberIds ?? []).compactMap { userOf[$0] }.filter { seen.insert($0).inserted }
    }
    var p = Plan()
    for t in trips where !foreign.contains(t.id) && t.archivedAt == nil {
      let m = linked(t.groupId.flatMap { groupById[$0] })
      if !m.isEmpty { p.spaces.append(SpaceOut(id: t.id, kind: "trip", name: t.name, members: m, trip: tripShare(t, items: tripItems))) }
    }
    for g in groups where !foreign.contains(g.id) && tripOfGroup[g.id] == nil {
      let m = linked(g)
      if !m.isEmpty { p.spaces.append(SpaceOut(id: g.id, kind: "group", name: g.name, members: m, trip: nil)) }
    }
    let shared = Set(p.spaces.map(\.id)).union(foreign)
    func spaceFor(_ tripId: String?, _ groupId: String?) -> String? {
      if let t = tripId, shared.contains(t) { return t }
      guard let g = groupId else { return nil }
      if let t = tripOfGroup[g]?.id, shared.contains(t) { return t }
      return shared.contains(g) ? g : nil
    }
    let own = entries.filter { !$0.id.hasPrefix(mirrorPrefix) }
    let byTxn = Dictionary(grouping: own.filter { $0.txnId != nil }, by: { $0.txnId! })
    for t in txns where t.deletedAt == nil && t.type == .expense {
      guard let es = byTxn[t.id], es.contains(where: { userOf[$0.friendId] != nil }) else { continue }
      let mine = t.splitShare ?? max(0, t.amount - es.reduce(0) { $0 + max(0, $1.amount) })
      var byUser: [String: Int] = [:]; var order: [String] = []
      for e in es where e.amount > 0 { if let u = userOf[e.friendId] { if byUser[u] == nil { order.append(u) }; byUser[u, default: 0] += e.amount } }
      var others: [String: Int] = [:]
      for e in es where e.amount > 0 && userOf[e.friendId] == nil { others[friendName[e.friendId] ?? "Friend", default: 0] += e.amount }
      p.expenses.append(ExpenseOut(id: t.id, spaceId: spaceFor(t.tripId, es.compactMap(\.groupId).first), paidBy: me, amount: t.amount,
        currency: base, originalAmount: t.originalAmount, originalCurrency: t.currency, payee: t.payee, note: t.note, occurredAt: t.occurredAt,
        shares: [ShareOut(userId: me, amount: mine)] + order.map { ShareOut(userId: $0, amount: byUser[$0]!) }, others: others))
    }
    for e in own where e.txnId == nil && e.amount != 0 {
      guard let u = userOf[e.friendId] else { continue }
      let v = abs(e.amount); let space = spaceFor(nil, e.groupId)
      if let n = e.note, settleNotes.contains(n) {
        p.settlements.append(e.amount > 0 ? SettlementOut(id: e.id, spaceId: space, from: me, to: u, amount: v, currency: base, note: n)
                                          : SettlementOut(id: e.id, spaceId: space, from: u, to: me, amount: v, currency: base, note: n))
      } else {
        // amount > 0: you paid and they owe you; < 0: they paid and you owe them.
        let shares = e.amount > 0 ? [ShareOut(userId: me, amount: 0), ShareOut(userId: u, amount: v)] : [ShareOut(userId: u, amount: 0), ShareOut(userId: me, amount: v)]
        p.expenses.append(ExpenseOut(id: e.id, spaceId: space, paidBy: e.amount > 0 ? me : u, amount: v, currency: base, originalAmount: nil,
          originalCurrency: nil, payee: e.note, note: nil, occurredAt: e.occurredAt, shares: shares, others: [:]))
      }
    }
    return p
  }

  static func diff(_ plan: Plan, pushed: [String: String]) -> (save: [String], remove: [String]) {
    let now = plan.hashes()
    return (now.filter { pushed[$0.key] != $0.value }.map(\.key).sorted(), pushed.keys.filter { now[$0] == nil }.sorted())
  }

  // ------------------------------------------------------------ mirror

  /// Brings what others shared into your data. `toBase` converts another currency to your main one (nil: wait).
  @MainActor
  static func mirror(_ s: State, me: String, base: String, context: ModelContext,
                     toBase: (Int, String) -> Int? = { a, c in c == Money.base ? a : nil }) {
    let friends = (try? context.fetch(FetchDescriptor<Friend>())) ?? []
    var friendOf: [String: String] = [:]
    for f in friends { if let u = f.userId, friendOf[u] == nil { friendOf[u] = f.id } }
    for p in s.people {
      if let f = friends.first(where: { $0.userId == p.id }) {
        if f.id == p.id { if f.name != p.label { f.name = p.label }; if f.upiId != p.upiId { f.upiId = p.upiId } }
        else if f.upiId == nil, let u = p.upiId { f.upiId = u }
      } else {
        context.insert(Friend(id: p.id, name: p.label, upiId: p.upiId, userId: p.id)); friendOf[p.id] = p.id
      }
    }

    var groups = Dictionary(((try? context.fetch(FetchDescriptor<SplitGroup>())) ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    let trips = (try? context.fetch(FetchDescriptor<Trip>())) ?? []
    let items = (try? context.fetch(FetchDescriptor<TripItem>())) ?? []
    for sp in s.spaces where sp.createdBy != me {
      let gone = sp.deleted || !sp.members.contains { $0.userId == me && !$0.left }
      let members = sp.members.filter { !$0.left && $0.userId != me }.compactMap { friendOf[$0.userId] }
      if !gone {
        if let g = groups[sp.id] { g.name = sp.name; g.memberIds = members }
        else { let g = SplitGroup(id: sp.id, name: sp.name, memberIds: members); context.insert(g); groups[sp.id] = g }
      }
      guard sp.kind == "trip", let d = sp.trip else { continue }
      let old = trips.first { $0.id == sp.id }
      if gone { if let o = old, o.archivedAt == nil { o.archivedAt = .now }; continue }
      let t = old ?? { let n = Trip(id: sp.id, name: sp.name); context.insert(n); return n }()
      t.name = sp.name; t.kind = d.kind; t.international = d.international; t.places = d.places
      t.startAt = d.startAt.map { Date(timeIntervalSince1970: Double($0) / 1000) }; t.endAt = d.endAt.map { Date(timeIntervalSince1970: Double($0) / 1000) }
      t.travellers = d.travellers; t.notes = d.notes; t.groupId = sp.id; t.updatedAt = .now
      for i in items where i.tripId == sp.id { context.delete(i) }
      for (n, i) in d.items.enumerated() { context.insert(TripItem(id: i.id, tripId: sp.id, label: i.label, budget: i.budget, sortOrder: n)) }
    }

    let entries = (try? context.fetch(FetchDescriptor<SplitEntry>())) ?? []
    var existing = Dictionary(entries.filter { $0.id.hasPrefix(mirrorPrefix) }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    var wanted: [String: (friend: String, amount: Int, note: String, at: Date, group: String?)] = [:]
    func when(_ ms: Int64) -> Date { Date(timeIntervalSince1970: Double(ms) / 1000) }
    var touched = Set<String>()
    for e in s.expenses where e.createdBy != me {
      touched.insert("\(mirrorPrefix)\(e.id):")
      guard !e.deleted, let my = e.shares.first(where: { $0.userId == me }), my.status == "accepted" else { continue }
      let group = e.spaceId.flatMap { groups[$0] != nil ? $0 : nil }
      if e.paidBy == me {
        for sh in e.shares where sh.userId != me && sh.status != "rejected" && sh.amount > 0 {
          guard let f = friendOf[sh.userId], let a = toBase(sh.amount, e.currency) else { continue }
          wanted["\(mirrorPrefix)\(e.id):\(sh.userId)"] = (f, a, e.title, when(e.occurredAt), group)
        }
      } else if my.amount > 0, let f = friendOf[e.paidBy], let a = toBase(my.amount, e.currency) {
        wanted["\(mirrorPrefix)\(e.id):\(me)"] = (f, -a, e.title, when(e.occurredAt), group)
      }
    }
    for st in s.settlements where st.createdBy != me {
      let id = "\(mirrorPrefix)settle:\(st.id)"; touched.insert(id)
      guard !st.deleted, st.status == "confirmed" else { continue }
      let other = st.to == me ? st.from : st.to
      guard let f = friendOf[other], let a = toBase(st.amount, st.currency) else { continue }
      wanted[id] = (f, st.to == me ? -a : a, st.note ?? "Settled up", when(st.at), st.spaceId.flatMap { groups[$0] != nil ? $0 : nil })
    }
    for (id, e) in existing where touched.contains(where: { id.hasPrefix($0) }) && wanted[id] == nil { context.delete(e); existing[id] = nil }
    for (id, w) in wanted {
      if let e = existing[id] { e.friendId = w.friend; e.amount = w.amount; e.note = w.note; e.occurredAt = w.at; e.groupId = w.group }
      else { context.insert(SplitEntry(id: id, friendId: w.friend, amount: w.amount, note: w.note, groupId: w.group, occurredAt: w.at)) }
    }
    try? context.save()
  }

  static func encodePushed(_ m: [String: String]) -> String { m.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ";") }
  static func decodePushed(_ s: String?) -> [String: String] {
    var m: [String: String] = [:]
    for p in (s ?? "").split(separator: ";") { let kv = p.split(separator: "=", maxSplits: 1); if kv.count == 2 { m[String(kv[0])] = String(kv[1]) } }
    return m
  }
}
