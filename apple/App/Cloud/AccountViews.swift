import Contacts
import SwiftData
import SwiftUI

// Paisa Pulse accounts: sign in with an email code, your profile, people, invites and the inbox.
// Same screens on Android (ui/screens/Account.kt).

private struct ExportFile: Identifiable { let id = UUID(); let url: URL }

/// Runs a cloud call, showing its error as a toast.
@MainActor private func run(_ router: Router, _ busy: Binding<Bool>, _ work: @escaping () async throws -> Void) {
  Task {
    busy.wrappedValue = true
    defer { busy.wrappedValue = false }
    do { try await work() }
    catch let e as Cloud.Failure { router.show(e.message) }
    catch { router.show("No connection. Try again.") }
  }
}

struct AccountView: View {
  @Environment(Router.self) private var router
  @Environment(\.modelContext) private var context
  @AppStorage(PrefKey.myName, store: AppGroup.defaults) private var myName = ""
  @AppStorage(PrefKey.myUpiId, store: AppGroup.defaults) private var myUpi = ""
  @State private var cloud = Cloud.shared
  @State private var busy = false
  @State private var name = ""
  @State private var upi = ""
  @State private var phone = ""
  @State private var confirmDelete = false
  @State private var export: ExportFile?

  var body: some View {
    Group {
      if !cloud.configured {
        ContentUnavailableView("Accounts are coming", systemImage: "person.crop.circle",
                               description: Text("This build doesn't have accounts switched on yet. Everything else works without one."))
      } else if !cloud.signedIn {
        SignInView()
      } else if let me = cloud.state.me, me.username == nil {
        PickUsernameView(current: me.name)
      } else {
        profile
      }
    }
    .navigationTitle("Account")
    .navigationBarTitleDisplayMode(.inline)
  }

  private var profile: some View {
    let s = cloud.state
    return Form {
      Section {
        VStack(spacing: 4) {
          Avatar(name: s.me?.label ?? "?", size: 72)
          Text(s.me?.label ?? "…").font(.title2.bold()).padding(.top, 8)
          Text([s.me?.username.map { "@\($0)" }, s.email].compactMap { $0 }.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
          Text(cloud.syncing ? "Syncing…" : cloud.error ?? "Up to date").font(.caption)
            .foregroundStyle(cloud.error == nil ? Color.secondary : Color.expense).padding(.top, 4)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
      }
      Section {
        NavigationLink { PeopleView() } label: { Label("People", systemImage: "person.2.fill").badge(s.people.filter(\.connected).count) }
        NavigationLink { InboxView() } label: { Label("Inbox", systemImage: "bell.fill").badge(cloud.badge) }
      }
      Section {
        TextField("Your name", text: $name)
        TextField("UPI ID, e.g. you@okaxis", text: $upi).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress)
        TextField(s.hasPhone ? "Phone saved · type to change" : "Phone (optional)", text: $phone).keyboardType(.phonePad)
        Button(busy ? "Saving…" : "Save") {
          run(router, $busy) {
            try await cloud.updateProfile(username: nil, name: name.trimmingCharacters(in: .whitespaces), upi: upi.trimmingCharacters(in: .whitespaces),
                                          phone: phone.isEmpty ? nil : phone)
            myName = name.trimmingCharacters(in: .whitespaces); myUpi = upi.trimmingCharacters(in: .whitespaces); phone = ""
            router.show("Saved")
          }
        }
        if s.hasPhone {
          Button("Remove Phone Number", role: .destructive) { run(router, $busy) { try await cloud.updateProfile(username: nil, name: nil, upi: nil, phone: "") } }
        }
      } header: { Text("Profile") } footer: {
        Text("Friends see your name and UPI ID. Your phone number is kept only as a fingerprint (a hash), so friends who have it can find you; nobody can read it.")
      }
      Section {
        Button { run(router, $busy) {
          let url = FileManager.default.temporaryDirectory.appending(path: "paisa-pulse-account.json")
          try await cloud.exportData().write(to: url)
          export = ExportFile(url: url)
        } } label: { Label("Download My Data", systemImage: "square.and.arrow.down") }
        Button { cloud.signOut() } label: { Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right") }
        Button(role: .destructive) { confirmDelete = true } label: { Label("Delete Account", systemImage: "trash") }
      } footer: {
        Text("Only things you share go to the server: your profile, people you add, shared splits, groups and trips. Your accounts, balances and other transactions never leave this phone.")
      }
    }
    .onAppear { name = s.me?.name ?? ""; upi = s.me?.upiId ?? "" }
    .task { await cloud.syncNow() }
    .refreshable { await cloud.syncNow() }
    .sheet(item: $export) { ActivitySheet(items: [$0.url]) }
    .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
      Button("Delete Account", role: .destructive) { run(router, $busy) { try await cloud.deleteAccount(context); router.show("Account deleted") } }
    } message: { Text("Your profile, invites and everything you shared are removed from the server for good. Your splits stay on this phone.") }
  }
}

private struct SignInView: View {
  @Environment(Router.self) private var router
  @State private var email = ""
  @State private var code = ""
  @State private var sent = false
  @State private var busy = false
  private var valid: Bool { email.range(of: "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", options: .regularExpression) != nil }

  var body: some View {
    Form {
      Section {
        VStack(spacing: 10) {
          Image(systemName: "person.2.fill").font(.system(size: 38)).foregroundStyle(.white)
            .frame(width: 84, height: 84).background(Color.accentColor, in: .rect(cornerRadius: 24))
          Text("Split with friends on Paisa Pulse").font(.title2.bold()).multilineTextAlignment(.center)
          Text("Add friends, split bills and trips, and they see their share on their phone. No password: we email you a code.")
            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8).listRowBackground(Color.clear)
      }
      Section {
        TextField("Email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
          .textInputAutocapitalization(.never).autocorrectionDisabled().onChange(of: email) { sent = false }
        if sent {
          TextField("Code", text: $code).textContentType(.oneTimeCode).keyboardType(.numberPad)
            .onChange(of: code) { _, v in code = String(v.filter(\.isNumber).prefix(10)) }
        }
        Button(busy ? "Please wait…" : sent ? "Sign In" : "Email Me a Code") {
          if !sent { run(router, $busy) { try await Cloud.shared.sendCode(email); sent = true } }
          else { run(router, $busy) { try await Cloud.shared.verify(email, code: code) } }
        }
        .disabled(busy || (!sent && !valid) || (sent && code.count < 6))
        if sent { Button("Send Again") { run(router, $busy) { try await Cloud.shared.sendCode(email); router.show("Sent") } } }
      } footer: {
        Text(sent ? "Check your email (and spam) for a 6-digit code from Paisa Pulse." : "Only what you share goes to the server. Your own money stays on this phone.")
      }
    }
  }
}

private struct PickUsernameView: View {
  let current: String
  @Environment(Router.self) private var router
  @AppStorage(PrefKey.myName, store: AppGroup.defaults) private var myName = ""
  @AppStorage(PrefKey.myUpiId, store: AppGroup.defaults) private var myUpi = ""
  @State private var name = ""
  @State private var user = ""
  @State private var free: Bool?
  @State private var busy = false

  var body: some View {
    Form {
      Section {
        TextField("Your name", text: $name)
        TextField("username", text: $user).textInputAutocapitalization(.never).autocorrectionDisabled()
          .onChange(of: user) { _, v in let c = CloudLogic.cleanUsername(v); if c != v { user = c } }
      } header: { Text("Pick how friends find you. You can change it later.") } footer: {
        Text(!CloudLogic.validUsername(user) ? "3 to 20 letters, numbers or _" : free == true ? "@\(user) is free" : free == false ? "@\(user) is taken" : "Checking…")
      }
      Section {
        Button(busy ? "Saving…" : "Continue") {
          run(router, $busy) { try await Cloud.shared.updateProfile(username: user, name: name.trimmingCharacters(in: .whitespaces), upi: myUpi.isEmpty ? nil : myUpi, phone: nil) }
        }
        .disabled(free != true || name.trimmingCharacters(in: .whitespaces).isEmpty || busy)
      }
    }
    .onAppear {
      name = current.isEmpty ? myName : current
      if user.isEmpty { user = CloudLogic.cleanUsername(myName.replacingOccurrences(of: " ", with: "_")) }
    }
    .task(id: user) {
      free = nil
      guard CloudLogic.validUsername(user) else { return }
      try? await Task.sleep(for: .milliseconds(400))
      if !Task.isCancelled { free = await Cloud.shared.usernameAvailable(user) }
    }
  }
}

/// Find people, add them, share your invite, and link friends in your splits to their accounts.
struct PeopleView: View {
  var invite: String? = nil
  var linking: Friend? = nil
  @Environment(Router.self) private var router
  @Environment(\.modelContext) private var context
  @Environment(\.dismiss) private var dismiss
  @Query(sort: \Friend.name) private var friends: [Friend]
  @State private var cloud = Cloud.shared
  @State private var q = ""
  @State private var results: [CloudLogic.Person] = []
  @State private var contacts: [Match]?
  @State private var code: String?
  @State private var typed = ""
  @State private var busy = false
  @State private var pendingInvite: String?

  struct Match: Identifiable { var person: CloudLogic.Person; var phone: String; var id: String { person.id } }

  var body: some View {
    if !cloud.signedIn {
      AccountView()
    } else {
      list
    }
  }

  private var list: some View {
    Form {
      if let f = linking {
        Section { Text("Pick \(f.name)'s Paisa Pulse account. Splits with them then show up on their phone too.").font(.subheadline).foregroundStyle(.secondary) }
      }
      Section {
        TextField("Username, email or phone", text: $q).textInputAutocapitalization(.never).autocorrectionDisabled()
        ForEach(results) { personRow($0) }
        if q.trimmingCharacters(in: .whitespaces).count >= 2 && results.isEmpty {
          Text("No one found. Send them your invite below.").font(.subheadline).foregroundStyle(.secondary)
        }
      } footer: { Text("Search by @username, email or phone number.") }
      Section {
        if let c = contacts {
          if c.isEmpty { Text("None of your contacts are on Paisa Pulse yet.").font(.subheadline).foregroundStyle(.secondary) }
          ForEach(c) { personRow($0.person, extra: $0.phone) }
        } else {
          Button { readContacts() } label: { Label("Find Friends from Contacts", systemImage: "person.crop.circle.badge.plus") }
        }
      } header: { Text("From your contacts") } footer: {
        Text("Phone numbers are turned into fingerprints on this phone before matching; the numbers themselves aren't sent.")
      }
      if linking == nil {
        let mine = cloud.state.people.filter(\.connected).sorted { $0.label.lowercased() < $1.label.lowercased() }
        if !mine.isEmpty { Section("Your people") { ForEach(mine) { personRow($0) } } }
        Section {
          if let c = code {
            let link = cloud.inviteLink(c)
            VStack(spacing: 10) {
              if let img = QRCode.image(link, size: 560) {
                Image(uiImage: img).interpolation(.none).resizable().frame(width: 200, height: 200).padding(8)
                  .background(.white, in: .rect(cornerRadius: 16))
              }
              Text("Your code: \(c)").font(.headline)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 6)
            ShareLink(item: "Add me on Paisa Pulse to split bills and trips: \(link)") { Label("Share Invite Link", systemImage: "square.and.arrow.up") }
          } else {
            Text("Getting your invite…").font(.subheadline).foregroundStyle(.secondary)
          }
          HStack {
            TextField("Friend's code", text: $typed).textInputAutocapitalization(.characters).autocorrectionDisabled()
              .onChange(of: typed) { _, v in let c = String(v.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(12)); if c != v { typed = c } }
            Button("Add") { run(router, $busy) { let p = try await cloud.acceptInvite(typed); typed = ""; router.show("Added \(p.label)") } }
              .disabled(typed.count < 6)
          }
        } header: { Text("Invite") } footer: { Text("Friends scan this with their camera, or open the link, to add you. Or type their code here.") }
      }
    }
    .navigationTitle(linking.map { "Link \($0.name)" } ?? "People")
    .navigationBarTitleDisplayMode(.inline)
    .task(id: q) {
      let t = q.trimmingCharacters(in: .whitespaces)
      try? await Task.sleep(for: .milliseconds(350))
      guard !Task.isCancelled else { return }
      results = t.count >= 2 ? ((try? await cloud.find(t)) ?? []) : []
    }
    .task { code = try? await cloud.inviteCode(); if pendingInvite == nil { pendingInvite = invite } }
    .alert("Add this person?", isPresented: Binding(get: { pendingInvite != nil }, set: { if !$0 { pendingInvite = nil } })) {
      Button("Add") { let c = pendingInvite ?? ""; pendingInvite = nil; run(router, $busy) { let p = try await cloud.acceptInvite(c); router.show("Added \(p.label)") } }
      Button("Not Now", role: .cancel) { pendingInvite = nil }
    } message: { Text("Accept the invite with code \(pendingInvite ?? "") to split bills and trips with them.") }
  }

  @ViewBuilder private func personRow(_ p: CloudLogic.Person, extra: String? = nil) -> some View {
    let local = friends.first { $0.userId == p.id }
    let sub = [p.username.map { "@\($0)" }, extra].compactMap { $0 }.joined(separator: " · ")
    let label = HStack {
      Avatar(name: p.label)
      VStack(alignment: .leading) { Text(p.label); if !sub.isEmpty { Text(sub).font(.caption).foregroundStyle(.secondary) } }
      Spacer()
      if linking != nil { Text("Link").foregroundStyle(Color.accentColor) }
      else if !p.connected { Text("Add").font(.subheadline.weight(.semibold)).foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 6)
        .background(Color.accentColor, in: .capsule) }
    }
    if linking == nil, p.connected, let local {
      NavigationLink { FriendDetailView(friend: local) } label: { label }
    } else {
      Button { choose(p) } label: { label }.foregroundStyle(.primary)
    }
  }

  private func choose(_ p: CloudLogic.Person) {
    run(router, $busy) {
      if !p.connected { try await cloud.connect(p.id) }
      guard let f = linking else { router.show("Added \(p.label)"); return }
      // The sync may already have made a friend for them: fold it into the one you picked.
      if let dup = friends.first(where: { $0.userId == p.id && $0.id != f.id }) {
        for e in (try? context.fetch(FetchDescriptor<SplitEntry>())) ?? [] where e.friendId == dup.id { e.friendId = f.id }
        for g in (try? context.fetch(FetchDescriptor<SplitGroup>())) ?? [] where g.memberIds.contains(dup.id) {
          var seen = Set<String>(); g.memberIds = g.memberIds.map { $0 == dup.id ? f.id : $0 }.filter { seen.insert($0).inserted }
        }
        context.delete(dup)
      }
      f.userId = p.id
      if f.upiId == nil { f.upiId = p.upiId }
      try? context.save()
      router.show("\(f.name) is linked to @\(p.username ?? "")")
      cloud.syncSoon()
      dismiss()
    }
  }

  private func readContacts() {
    run(router, $busy) {
      let store = CNContactStore()
      guard try await store.requestAccess(for: .contacts) else { router.show("Contacts access is off"); return }
      let phones: [String] = try await Task.detached {
        var out: [String] = []
        let req = CNContactFetchRequest(keysToFetch: [CNContactPhoneNumbersKey as CNKeyDescriptor])
        try store.enumerateContacts(with: req) { c, _ in out += c.phoneNumbers.map { $0.value.stringValue } }
        return out
      }.value
      contacts = try await cloud.matchContacts(Array(Set(phones))).map { Match(person: $0.0, phone: $0.1) }
    }
  }
}

/// Splits and settle-ups waiting for you, and what happened lately.
struct InboxView: View {
  @Environment(Router.self) private var router
  @State private var cloud = Cloud.shared
  @State private var busy = false

  var body: some View {
    let s = cloud.state
    let me = cloud.me ?? ""
    let shares = s.pendingShares(me)
    let settles = s.pendingSettlements(me)
    func who(_ id: String?) -> String { s.person(id)?.label ?? "Someone" }
    return List {
      if !shares.isEmpty {
        Section {
          ForEach(shares) { e in
            let my = e.shares.first { $0.userId == me }?.amount ?? 0
            VStack(alignment: .leading, spacing: 6) {
              Text(e.title).font(.headline)
              Text((e.paidBy == me ? "\(who(e.createdBy)) says you paid \(Money.format(e.amount, code: e.currency))" : "\(who(e.paidBy)) paid \(Money.format(e.amount, code: e.currency))")
                   + " · " + Date(timeIntervalSince1970: Double(e.occurredAt) / 1000).formatted(date: .abbreviated, time: .omitted))
                .font(.subheadline).foregroundStyle(.secondary)
              if e.paidBy == me {
                Text("They owe you \(Money.format(e.shares.filter { $0.userId != me }.reduce(0) { $0 + $1.amount }, code: e.currency))").fontDesign(.rounded).foregroundStyle(Color.income)
              } else {
                Text("Your share: \(Money.format(my, code: e.currency))").fontDesign(.rounded).foregroundStyle(Color.expense)
              }
              HStack {
                Button("Accept") { run(router, $busy) { try await cloud.respondShare(e.id, accept: true) } }.buttonStyle(.borderedProminent)
                Button("Decline", role: .destructive) { run(router, $busy) { try await cloud.respondShare(e.id, accept: false) } }.buttonStyle(.bordered)
              }
            }
            .padding(.vertical, 4)
          }
        } header: { Text("To accept") } footer: { Text("Accepted shares go into your balance with that person.") }
      }
      if !settles.isEmpty {
        Section("To confirm") {
          ForEach(settles) { st in
            VStack(alignment: .leading, spacing: 6) {
              Text(st.to == me ? "\(who(st.from)) paid you \(Money.format(st.amount, code: st.currency))" : "\(who(st.to)) says you paid them \(Money.format(st.amount, code: st.currency))")
                .font(.headline)
              if let n = st.note { Text(n).font(.subheadline).foregroundStyle(.secondary) }
              HStack {
                Button("Confirm") { run(router, $busy) { try await cloud.respondSettlement(st.id, confirm: true) } }.buttonStyle(.borderedProminent)
                Button(st.to == me ? "Didn't Get It" : "Not Me", role: .destructive) { run(router, $busy) { try await cloud.respondSettlement(st.id, confirm: false) } }
                  .buttonStyle(.bordered)
              }
            }
            .padding(.vertical, 4)
          }
        }
      }
      if s.inbox.isEmpty && shares.isEmpty && settles.isEmpty {
        ContentUnavailableView("Nothing new", systemImage: "bell", description: Text("When friends split something with you or add you to a trip, it shows up here."))
      }
      if !s.inbox.isEmpty {
        Section("Recent") {
          ForEach(s.inbox.prefix(60)) { n in
            HStack(alignment: .top, spacing: 12) {
              Avatar(name: who(n.actor))
              VStack(alignment: .leading, spacing: 2) {
                Text(n.title).foregroundStyle(n.read ? Color.primary : Color.accentColor)
                Text([n.body, Date(timeIntervalSince1970: Double(n.at) / 1000).formatted(date: .abbreviated, time: .omitted)].compactMap { $0 }.joined(separator: " · "))
                  .font(.caption).foregroundStyle(.secondary)
              }
            }
          }
        }
      }
    }
    .navigationTitle("Inbox")
    .navigationBarTitleDisplayMode(.inline)
    .refreshable { await cloud.syncNow() }
    .task {
      while !Task.isCancelled {
        await cloud.syncNow(); await cloud.markRead()
        try? await Task.sleep(for: .seconds(20))
      }
    }
  }
}

/// Settings row: your account, or an invitation to make one.
struct AccountRowLabel: View {
  @State private var cloud = Cloud.shared
  var body: some View {
    HStack(spacing: 12) {
      if cloud.signedIn, let me = cloud.state.me { Avatar(name: me.label, size: 40) }
      else { CategoryBadge(icon: "person.crop.circle.fill", color: "#5E5CE6", size: 40) }
      VStack(alignment: .leading, spacing: 2) {
        Text(cloud.signedIn ? cloud.state.me?.label ?? "Your account" : "Sign In to Split with Friends").foregroundStyle(.primary)
        Text(cloud.signedIn ? cloud.state.me?.username.map { "@\($0)" } ?? "" : "Friends see shared splits and trips on their phone")
          .font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      if cloud.badge > 0 {
        Text("\(cloud.badge)").font(.caption.bold()).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 2).background(Color.expense, in: .capsule)
      }
    }
  }
}

/// On a friend's page: their Paisa Pulse account, or a way to link one.
struct FriendAccountSection: View {
  @Bindable var friend: Friend
  @State private var cloud = Cloud.shared
  var body: some View {
    Section {
      if let u = friend.userId {
        Label { VStack(alignment: .leading) { Text("On Paisa Pulse"); Text(cloud.state.person(u)?.username.map { "@\($0)" } ?? "Linked").font(.caption).foregroundStyle(.secondary) } }
          icon: { Image(systemName: "checkmark.seal.fill") }
        Button("Unlink", role: .destructive) { friend.userId = nil }
      } else {
        NavigationLink { if cloud.signedIn { PeopleView(linking: friend) } else { AccountView() } } label: {
          Label("Link to Their Paisa Pulse Account", systemImage: "link")
        }
      }
    } header: { Text("Paisa Pulse") } footer: {
      Text(friend.userId != nil ? "Splits with \(friend.name) show up on their phone, and theirs on yours." : "Linked friends see shared splits on their phone and confirm their share.")
    }
  }
}

/// On a trip page: everything split in the trip by everyone, from Paisa Pulse.
struct TripGroupSpendingSection: View {
  let tripId: String
  @State private var cloud = Cloud.shared
  @AppStorage(PrefKey.hideAmounts, store: AppGroup.defaults) private var hidden = false
  struct Payer: Identifiable { var id: String; var name: String; var total: Int }
  private func payers(_ e: [CloudLogic.Expense]) -> [Payer] {
    Dictionary(grouping: e, by: \.paidBy).map { u, v in
      Payer(id: u, name: u == cloud.me ? "You" : cloud.state.person(u)?.label ?? "Someone", total: v.reduce(0) { $0 + $1.amount })
    }.sorted { $0.total > $1.total }
  }
  var body: some View {
    let shared = cloud.state.expenses.filter { $0.spaceId == tripId && !$0.deleted }
    if !shared.isEmpty {
      Section {
        LabeledContent("Total", value: Money.format(shared.reduce(0) { $0 + $1.amount }, hidden: hidden))
        ForEach(payers(shared)) { p in
          HStack { Avatar(name: p.name, size: 28); Text("\(p.name) paid"); Spacer(); Text(Money.format(p.total, hidden: hidden)).fontDesign(.rounded) }
        }
      } header: { Text("Group spending") } footer: { Text("Everything split in this trip by everyone, from Paisa Pulse.") }
    }
  }
}
