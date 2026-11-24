import BackgroundTasks
import Foundation
import Observation
import SwiftData
import UserNotifications

/// Paisa Pulse accounts (Supabase): email-code sign-in, then everything goes through the database
/// functions in supabase/migrations. Same behaviour as Android (cloud/Cloud.kt). The URL and public key
/// come from CI (Shared/CloudConfig.swift); when empty, accounts are off in that build.
@MainActor @Observable
final class Cloud {
  static let shared = Cloud()
  /// The app's store, for background refresh.
  nonisolated(unsafe) static var container: ModelContainer?
  static let refreshTask = "com.paisapulse.app.sync"

  struct Session: Codable { var access, refresh: String; var expiresAt: Date; var userId: String; var email: String? }
  struct Failure: LocalizedError { var message: String; var errorDescription: String? { message } }

  private(set) var session: Session?
  private(set) var state = CloudLogic.State()
  private(set) var syncing = false
  var error: String?

  var configured: Bool { !CloudConfig.url.isEmpty && !CloudConfig.key.isEmpty }
  var signedIn: Bool { session != nil }
  var me: String? { session?.userId }
  var badge: Int { guard let m = me else { return 0 }; return state.unread + state.pendingShares(m).count + state.pendingSettlements(m).count }

  private let defaults = UserDefaults.standard
  private var cacheURL: URL { URL.applicationSupportDirectory.appending(path: "cloud-cache.json") }
  private var running: Task<Void, Never>?

  private init() {
    session = Keychain.get("cloud-session").flatMap { try? JSONDecoder().decode(Session.self, from: Data($0.utf8)) }
    state = (try? JSONDecoder().decode(CloudLogic.State.self, from: Data(contentsOf: cacheURL))) ?? CloudLogic.State()
  }

  private func save(session s: Session?) {
    session = s
    Keychain.set("cloud-session", s.flatMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) })
  }

  // MARK: HTTP

  private struct Unauthorized: Error {}

  private func http(_ method: String, _ path: String, _ body: [String: Any]?, auth: Bool) async throws -> Any? {
    guard configured, let url = URL(string: CloudConfig.url + path) else { throw Failure(message: "Accounts aren't set up in this build yet.") }
    var r = URLRequest(url: url, timeoutInterval: 30)
    r.httpMethod = method
    r.setValue(CloudConfig.key, forHTTPHeaderField: "apikey")
    r.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if auth, let s = session { r.setValue("Bearer \(s.access)", forHTTPHeaderField: "Authorization") }
    if let body { r.httpBody = try JSONSerialization.data(withJSONObject: body) }
    let (data, resp) = try await URLSession.shared.data(for: r)
    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
    let json = data.isEmpty ? nil : try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    guard (200..<300).contains(code) else {
      if code == 401 && auth { throw Unauthorized() }
      let o = json as? [String: Any]
      let msg = (o?["message"] ?? o?["msg"] ?? o?["error_description"] ?? o?["error"]) as? String ?? "Error \(code)"
      throw Failure(message: Self.friendly(msg))
    }
    return json
  }

  private static func friendly(_ m: String) -> String {
    let l = m.lowercased()
    if l.contains("rate limit") || l.contains("security purposes") { return "Too many tries. Wait a minute and try again." }
    if l.contains("invalid login") { return "Wrong email or password." }
    if l.contains("token has expired") || l.contains("otp") || l.contains("invalid token") { return "That code is wrong or has expired." }
    if l.contains("sending recovery") || l.contains("error sending") { return "Couldn't send the email right now. Try again later." }
    if l.contains("same password") || l.contains("different from the old") { return "Pick a password you haven't used here." }
    if l.contains("already registered") || l.contains("already been registered") { return "That email already has an account. Sign in instead." }
    if l.contains("password") && l.contains("characters") { return "Use a longer password (at least 8 characters)." }
    if l.contains("not signed in") { return "Please sign in again." }
    return m
  }

  private func ensureFresh() async throws {
    guard let s = session else { throw Failure(message: "Please sign in.") }
    if Date.now < s.expiresAt.addingTimeInterval(-60) { return }
    let r = try await http("POST", "/auth/v1/token?grant_type=refresh_token", ["refresh_token": s.refresh], auth: false) as? [String: Any] ?? [:]
    save(session: try Self.session(from: r, email: s.email))
  }

  private static func session(from r: [String: Any], email: String?) throws -> Session {
    guard let a = r["access_token"] as? String, let f = r["refresh_token"] as? String, let u = r["user"] as? [String: Any], let id = u["id"] as? String
    else { throw Failure(message: "Sign-in failed. Try again.") }
    return Session(access: a, refresh: f, expiresAt: .now.addingTimeInterval((r["expires_in"] as? Double) ?? 3600), userId: id, email: (u["email"] as? String) ?? email)
  }

  /// Calls a database function as you.
  @discardableResult
  func rpc(_ name: String, _ args: [String: Any] = [:]) async throws -> Any? {
    try await ensureFresh()
    do { return try await http("POST", "/rest/v1/rpc/\(name)", args, auth: true) }
    catch is Unauthorized {
      session?.expiresAt = .distantPast
      try await ensureFresh()
      do { return try await http("POST", "/rest/v1/rpc/\(name)", args, auth: true) }
      catch is Unauthorized { save(session: nil); throw Failure(message: "Please sign in again.") }
    }
  }

  // MARK: Sign in

  // Email + password, no emails sent (the CI setup turns email confirmation off).

  func signUp(_ email: String, password: String) async throws { try await signIn(path: "/auth/v1/signup", email, password) }
  func signIn(_ email: String, password: String) async throws { try await signIn(path: "/auth/v1/token?grant_type=password", email, password) }

  private func signIn(path: String, _ email: String, _ password: String) async throws {
    let e = email.trimmingCharacters(in: .whitespaces).lowercased()
    let r = try await http("POST", path, ["email": e, "password": password], auth: false) as? [String: Any] ?? [:]
    guard r["access_token"] != nil else { throw Failure(message: "Account made, but sign-in needs email confirmation. Ask for the build to be run again, then sign in.") }
    let s = try Self.session(from: r, email: e)
    if s.userId != defaults.string(forKey: "cloud.user") { resetLocal() }
    defaults.set(s.userId, forKey: "cloud.user")
    save(session: s)
    await syncNow()
  }

  /// Emails a 6-digit reset code (through Resend, set up by CI).
  func sendResetCode(_ email: String) async throws {
    _ = try await http("POST", "/auth/v1/recover", ["email": email.trimmingCharacters(in: .whitespaces).lowercased()], auth: false)
  }

  /// Checks the emailed code, signs you in and sets the new password.
  func resetPassword(_ email: String, code: String, password: String) async throws {
    let e = email.trimmingCharacters(in: .whitespaces).lowercased()
    let r = try await http("POST", "/auth/v1/verify", ["type": "recovery", "email": e, "token": code.filter(\.isNumber)], auth: false) as? [String: Any] ?? [:]
    let s = try Self.session(from: r, email: e)
    if s.userId != defaults.string(forKey: "cloud.user") { resetLocal() }
    defaults.set(s.userId, forKey: "cloud.user")
    save(session: s)
    _ = try await http("PUT", "/auth/v1/user", ["password": password], auth: true)
    await syncNow()
  }

  func changePassword(_ password: String) async throws {
    try await ensureFresh()
    _ = try await http("PUT", "/auth/v1/user", ["password": password], auth: true)
  }

  /// Signs out on this phone. Shared items stay in your splits.
  func signOut() { save(session: nil) }

  func deleteAccount(_ context: ModelContext) async throws {
    try await rpc("delete_account")
    save(session: nil); resetLocal()
    for f in (try? context.fetch(FetchDescriptor<Friend>())) ?? [] where f.userId != nil { f.userId = nil }
    try? context.save()
  }

  private func resetLocal() {
    state = CloudLogic.State(); try? FileManager.default.removeItem(at: cacheURL)
    for k in ["cloud.pushed", "cloud.notified", "cloud.since"] { defaults.removeObject(forKey: k) }
  }

  // MARK: Profile and people

  func updateProfile(username: String?, name: String?, upi: String?, phone: String?) async throws {
    try await rpc("update_profile", ["p_username": Self.n(username), "p_display_name": Self.n(name), "p_upi_id": Self.n(upi),
                                     "p_phone": Self.n(phone), "p_color": NSNull()])
    await syncNow()
  }
  func usernameAvailable(_ u: String) async -> Bool { ((try? await rpc("username_available", ["p_username": u])) as? Bool) == true }
  func find(_ q: String) async throws -> [CloudLogic.Person] { ((try await rpc("find_people", ["q": q])) as? [[String: Any]] ?? []).map(Self.person) }
  func matchContacts(_ phones: [String]) async throws -> [(CloudLogic.Person, String)] {
    var hashes: [String: String] = [:]
    for p in phones { if let h = CloudLogic.phoneHash(p) { hashes[h] = p } }
    guard !hashes.isEmpty else { return [] }
    let r = (try await rpc("match_contacts", ["hashes": Array(hashes.keys)])) as? [[String: Any]] ?? []
    return r.map { (Self.person($0), hashes[($0["phone_hash"] as? String) ?? ""] ?? "") }
  }
  @discardableResult func connect(_ userId: String) async throws -> CloudLogic.Person {
    let p = Self.person((try await rpc("connect", ["p_friend": userId])) as? [String: Any] ?? [:]); await syncNow(); return p
  }
  func inviteCode() async throws -> String { (try await rpc("create_invite")) as? String ?? "" }
  func inviteLink(_ code: String) -> String {
    let n = (state.me?.label ?? "").addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
    return "https://porifiro123.github.io/paisa-pulse/invite/#c=\(code)&n=\(n)"
  }
  func acceptInvite(_ code: String) async throws -> CloudLogic.Person {
    let p = Self.person((try await rpc("accept_invite", ["p_code": code])) as? [String: Any] ?? [:]); await syncNow(); return p
  }
  func respondShare(_ id: String, accept: Bool) async throws { try await rpc("respond_share", ["p_expense": id, "p_accept": accept]); await syncNow() }
  func respondSettlement(_ id: String, confirm: Bool) async throws { try await rpc("respond_settlement", ["p_id": id, "p_confirm": confirm]); await syncNow() }
  func markRead() async { if state.unread > 0 { _ = try? await rpc("mark_read", ["p_ids": NSNull()]); await syncNow() } }
  func exportData() async throws -> Data {
    let r = try await rpc("export_my_data") ?? [String: Any]()
    return try JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted, .sortedKeys])
  }

  // MARK: Sync

  func syncSoon() { if signedIn { Task { await syncNow() } } }

  /// Pushes your shared changes, pulls everyone else's, and brings them into your splits.
  func syncNow(context: ModelContext? = nil) async {
    guard configured, signedIn else { return }
    if let r = running { await r.value; return }
    let task = Task { @MainActor in
      syncing = true
      defer { syncing = false; running = nil }
      guard let ctx = context ?? Self.container?.mainContext else { return }
      do {
        try await push(ctx)
        try await pull(ctx)
        error = nil
      } catch let e as Failure { error = e.message } catch { self.error = "No connection. Will try again." }
    }
    running = task
    await task.value
  }

  /// Only pushes (after you change something); cheap when nothing shared changed.
  func pushSoon() {
    guard signedIn, running == nil, let ctx = Self.container?.mainContext else { return }
    let d = diff(ctx)
    if !d.save.isEmpty || !d.remove.isEmpty { Task { await syncNow(context: ctx) } }
  }

  private func plan(_ ctx: ModelContext) -> CloudLogic.Plan {
    let me = me ?? ""
    return CloudLogic.plan(friends: (try? ctx.fetch(FetchDescriptor<Friend>())) ?? [], groups: (try? ctx.fetch(FetchDescriptor<SplitGroup>())) ?? [],
                           trips: (try? ctx.fetch(FetchDescriptor<Trip>())) ?? [], tripItems: (try? ctx.fetch(FetchDescriptor<TripItem>())) ?? [],
                           txns: (try? ctx.fetch(FetchDescriptor<Txn>())) ?? [], entries: (try? ctx.fetch(FetchDescriptor<SplitEntry>())) ?? [],
                           me: me, base: Money.base, foreign: Set(state.spaces.filter { $0.createdBy != me }.map(\.id)))
  }
  private func diff(_ ctx: ModelContext) -> (save: [String], remove: [String]) {
    CloudLogic.diff(plan(ctx), pushed: CloudLogic.decodePushed(defaults.string(forKey: "cloud.pushed")))
  }

  private func push(_ ctx: ModelContext) async throws {
    let p = plan(ctx)
    var pushed = CloudLogic.decodePushed(defaults.string(forKey: "cloud.pushed"))
    let d = CloudLogic.diff(p, pushed: pushed)
    let hashes = p.hashes()
    let iso = ISO8601DateFormatter()
    func keep() { defaults.set(CloudLogic.encodePushed(pushed), forKey: "cloud.pushed") }
    func opt(_ v: Any?) -> Any { v ?? NSNull() }
    for k in d.save.sorted(by: { ($0.hasPrefix("g:") ? 0 : 1, $0) < ($1.hasPrefix("g:") ? 0 : 1, $1) }) {
      let id = String(k.dropFirst(2))
      do {
        switch k.prefix(1) {
        case "g":
          guard let s = p.spaces.first(where: { $0.id == id }) else { continue }
          try await rpc("save_space", ["p_id": s.id, "p_kind": s.kind, "p_name": s.name, "p_data": s.trip.map(Self.tripJSON) ?? [:], "p_members": s.members])
        case "e":
          guard let e = p.expenses.first(where: { $0.id == id }) else { continue }
          var data: [String: Any] = [:]
          if !e.others.isEmpty { data["others"] = e.others.sorted { $0.key < $1.key }.map { ["name": $0.key, "amount": $0.value] as [String: Any] } }
          try await rpc("save_expense", [
            "p_id": e.id, "p_space": opt(e.spaceId), "p_paid_by": e.paidBy, "p_amount": e.amount, "p_currency": e.currency,
            "p_original_amount": opt(e.originalAmount), "p_original_currency": opt(e.originalCurrency), "p_payee": opt(e.payee), "p_note": opt(e.note),
            "p_occurred_at": iso.string(from: e.occurredAt), "p_data": data,
            "p_shares": e.shares.map { ["user": $0.userId, "amount": $0.amount] as [String: Any] },
          ])
        default:
          guard let s = p.settlements.first(where: { $0.id == id }) else { continue }
          try await rpc("save_settlement", ["p_id": s.id, "p_space": opt(s.spaceId), "p_from": s.from, "p_to": s.to, "p_amount": s.amount,
                                            "p_currency": s.currency, "p_note": opt(s.note)])
        }
        pushed[k] = hashes[k]; keep()
      } catch let e as Failure { error = e.message }
    }
    for k in d.remove {
      let id = String(k.dropFirst(2))
      do {
        switch k.prefix(1) {
        case "g": try await rpc("leave_space", ["p_id": id])
        case "e": try await rpc("delete_expense", ["p_id": id])
        default: try await rpc("delete_settlement", ["p_id": id])
        }
        pushed[k] = nil; keep()
      } catch is Failure {}
    }
  }

  private func pull(_ ctx: ModelContext) async throws {
    let r = try await rpc("sync", ["p_since": Self.n(defaults.string(forKey: "cloud.since"))]) as? [String: Any] ?? [:]
    let fresh = Self.parse(r)
    state = state.merge(fresh)
    if let t = r["server_time"] as? String { defaults.set(t, forKey: "cloud.since") }
    try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
    try? JSONEncoder().encode(state).write(to: cacheURL)
    guard let me else { return }
    let base = Money.base
    let rates = Currency.cached?.inrPer
    CloudLogic.mirror(state, me: me, base: base, context: ctx) { a, c in
      if c == base { return a }
      guard let r = rates, let x = Fx.rate(from: c, to: base, inrPer: r) else { return nil }
      return Int((Double(a) * x).rounded())
    }
    WidgetRefresh.now()
    notifyNew()
  }

  private func notifyNew() {
    let seen = defaults.object(forKey: "cloud.notified") as? Int64 ?? -1
    if seen >= 0 {
      for n in state.inbox.filter({ !$0.read && $0.id > seen }).prefix(5) {
        let c = UNMutableNotificationContent(); c.title = n.title; c.body = n.body ?? "Open Paisa Pulse to see it."; c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "cloud-\(n.id)", content: c, trigger: nil))
      }
    }
    defaults.set(max(state.inbox.map(\.id).max() ?? seen, seen, 0), forKey: "cloud.notified")
  }

  // MARK: Background refresh (about every 15 minutes when iOS allows)

  nonisolated static func registerBackground() {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTask, using: nil) { task in
      scheduleBackground()
      let work = Task { @MainActor in await Cloud.shared.syncNow() }
      task.expirationHandler = { work.cancel() }
      Task { await work.value; task.setTaskCompleted(success: true) }
    }
  }
  nonisolated static func scheduleBackground() {
    let r = BGAppRefreshTaskRequest(identifier: refreshTask)
    r.earliestBeginDate = .now.addingTimeInterval(15 * 60)
    try? BGTaskScheduler.shared.submit(r)
  }

  // MARK: JSON

  private static func time(_ s: Any?) -> Int64 {
    guard let s = s as? String else { return 0 }
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let g = ISO8601DateFormatter()
    return Int64(((f.date(from: s) ?? g.date(from: s))?.timeIntervalSince1970 ?? 0) * 1000)
  }
  /// JSON null for nil.
  static func n(_ v: Any?) -> Any { v ?? NSNull() }
  private static func int(_ v: Any?) -> Int { (v as? NSNumber)?.intValue ?? 0 }
  private static func str(_ v: Any?) -> String? { v as? String }

  static func person(_ o: [String: Any]) -> CloudLogic.Person {
    CloudLogic.Person(id: str(o["id"]) ?? "", username: str(o["username"]), name: str(o["display_name"]) ?? "", upiId: str(o["upi_id"]),
                      connected: (o["connected"] as? Bool) == true)
  }

  static func tripJSON(_ t: CloudLogic.TripShare) -> [String: Any] {
    ["kind": t.kind, "international": t.international,
     "places": t.places.map { ["name": $0.name, "country": n($0.country), "currency": n($0.currency)] as [String: Any] },
     "start_at": n(t.startAt), "end_at": n(t.endAt), "travellers": t.travellers, "notes": n(t.notes),
     "items": t.items.map { ["id": $0.id, "label": $0.label, "budget": n($0.budget)] as [String: Any] }]
  }
  static func trip(_ d: [String: Any]?) -> CloudLogic.TripShare? {
    guard let d, let kind = d["kind"] as? String else { return nil }
    return .init(kind: kind, international: (d["international"] as? Bool) == true,
                 places: (d["places"] as? [[String: Any]] ?? []).map { TripPlace(name: str($0["name"]) ?? "", country: str($0["country"]), currency: str($0["currency"])) },
                 startAt: (d["start_at"] as? NSNumber)?.int64Value, endAt: (d["end_at"] as? NSNumber)?.int64Value,
                 travellers: max(1, int(d["travellers"])), notes: str(d["notes"]),
                 items: (d["items"] as? [[String: Any]] ?? []).map { .init(id: str($0["id"]) ?? UUID().uuidString.lowercased(), label: str($0["label"]) ?? "",
                                                                          budget: ($0["budget"] as? NSNumber)?.intValue) })
  }

  static func parse(_ r: [String: Any]) -> CloudLogic.State {
    var s = CloudLogic.State()
    if let m = r["me"] as? [String: Any] { s.me = person(m); s.email = str(m["email"]); s.hasPhone = (m["has_phone"] as? Bool) == true }
    s.people = (r["people"] as? [[String: Any]] ?? []).map(person)
    s.spaces = (r["spaces"] as? [[String: Any]] ?? []).map { o in
      .init(id: str(o["id"]) ?? "", kind: str(o["kind"]) ?? "group", name: str(o["name"]) ?? "", createdBy: str(o["created_by"]) ?? "",
            deleted: o["deleted_at"] is String,
            members: (o["members"] as? [[String: Any]] ?? []).map { .init(userId: str($0["user_id"]) ?? "", left: ($0["left"] as? Bool) == true) },
            trip: trip(o["data"] as? [String: Any]))
    }
    s.expenses = (r["expenses"] as? [[String: Any]] ?? []).map { o in
      .init(id: str(o["id"]) ?? "", spaceId: str(o["space_id"]), createdBy: str(o["created_by"]) ?? "", paidBy: str(o["paid_by"]) ?? "",
            amount: int(o["amount"]), currency: str(o["currency"]) ?? "INR", payee: str(o["payee"]), note: str(o["note"]),
            occurredAt: time(o["occurred_at"]), deleted: o["deleted_at"] is String,
            shares: (o["shares"] as? [[String: Any]] ?? []).map { .init(userId: str($0["user_id"]) ?? "", amount: int($0["amount"]), status: str($0["status"]) ?? "pending") })
    }
    s.settlements = (r["settlements"] as? [[String: Any]] ?? []).map { o in
      .init(id: str(o["id"]) ?? "", spaceId: str(o["space_id"]), createdBy: str(o["created_by"]) ?? "", from: str(o["from_user"]) ?? "",
            to: str(o["to_user"]) ?? "", amount: int(o["amount"]), currency: str(o["currency"]) ?? "INR", note: str(o["note"]),
            status: str(o["status"]) ?? "pending", deleted: o["deleted_at"] is String, at: time(o["created_at"]))
    }
    s.inbox = (r["inbox"] as? [[String: Any]] ?? []).map { o in
      .init(id: (o["id"] as? NSNumber)?.int64Value ?? 0, kind: str(o["kind"]) ?? "", actor: str(o["actor"]), refId: str(o["ref_id"]),
            title: str(o["title"]) ?? "", body: str(o["body"]), at: time(o["created_at"]), read: o["read_at"] is String)
    }
    s.since = str(r["server_time"])
    return s
  }
}

/// Small secrets in the Keychain (this device only).
enum Keychain {
  static func get(_ account: String) -> String? {
    var out: AnyObject?
    let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account, kSecReturnData as String: true]
    guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
    return String(data: d, encoding: .utf8)
  }
  static func set(_ account: String, _ value: String?) {
    let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account]
    SecItemDelete(q as CFDictionary)
    guard let v = value, !v.isEmpty else { return }
    var add = q
    add[kSecValueData as String] = Data(v.utf8)
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    SecItemAdd(add as CFDictionary, nil)
  }
}
