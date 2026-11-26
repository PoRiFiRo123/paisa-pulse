import Contacts
import ContactsUI
import SwiftData
import SwiftUI

/// One place to add people, used by Splits, the split editor, groups and plans (Android: AddPeopleDialog).
/// Type once and it searches people on Paisa Pulse (@username, email or phone), your contacts (on this
/// phone), and offers to add exactly what you typed as a name. Tapping adds and ticks; Done closes.
struct AddPeopleSheet: View {
  var title = "Add People"
  /// Also list your existing people (for picking group or plan members).
  var showFriends = false
  /// Already chosen: shown ticked.
  var chosen: Set<String> = []
  /// Hands back the person; `isNew` when this sheet just made them.
  let onAdd: (_ friend: Friend, _ isNew: Bool) -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @Environment(Router.self) private var router
  @Query(sort: \Friend.name) private var friends: [Friend]
  @State private var cloud = Cloud.shared
  @State private var q = ""
  @State private var found: [CloudLogic.Person] = []
  @State private var hits: [ContactHit] = []
  @State private var access = CNContactStore.authorizationStatus(for: .contacts)
  @State private var added: Set<String> = []
  @State private var searching = false
  @State private var busy = false

  struct ContactHit: Identifiable, Hashable { let id: String; let name: String; let phone: String? }

  private var term: String { q.trimmingCharacters(in: .whitespaces) }
  private var contactsOn: Bool { access == .authorized || access == .limited }

  var body: some View {
    List {
      if !term.isEmpty && !term.hasPrefix("@") && !term.contains("@") {
        Section {
          Button { addName(term) } label: {
            Label { Text("Add “\(term)”").foregroundStyle(.primary) } icon: { Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor) }
          }
        } footer: { Text("Adds them just on this phone. You can link their Paisa Pulse account later.") }
      }

      if showFriends {
        let mine = friends.filter { term.isEmpty || $0.name.localizedCaseInsensitiveContains(term) }
        if !mine.isEmpty {
          Section("Your people") {
            ForEach(mine) { f in
              row(f.name, sub: f.userId != nil ? "On Paisa Pulse" : nil, on: chosen.contains(f.id) || added.contains(f.id), linked: f.userId != nil) {
                pick(f, isNew: false)
              }
            }
          }
        }
      }

      Section {
        if !cloud.signedIn {
          Button { dismiss(); router.tab = .settings; router.popToRoot.toggle() } label: {
            Label("Sign in to find people by username", systemImage: "person.crop.circle")
          }
        } else if term.count < 2 {
          let mine = cloud.state.people.filter(\.connected).sorted { $0.label.lowercased() < $1.label.lowercased() }
          if mine.isEmpty { Text("Type a @username, email or phone number.").font(.subheadline).foregroundStyle(.secondary) }
          ForEach(mine) { p in personRow(p) }
        } else {
          if searching && found.isEmpty { SkeletonRows(count: 2) }
          ForEach(found) { p in personRow(p) }
          if !searching && found.isEmpty { Text("No one on Paisa Pulse matches “\(term)”.").font(.subheadline).foregroundStyle(.secondary) }
        }
      } header: { Text("On Paisa Pulse") } footer: {
        if cloud.signedIn { Text("Splits with them show up on their phone too.") }
      }

      Section {
        if contactsOn {
          if term.isEmpty { Text("Type a name or number to search your contacts.").font(.subheadline).foregroundStyle(.secondary) }
          else if hits.isEmpty && !searching { Text("No contacts match “\(term)”.").font(.subheadline).foregroundStyle(.secondary) }
          ForEach(hits) { c in
            row(c.name, sub: c.phone, on: added.contains("c:\(c.id)"), linked: false) { addContact(c) }
          }
        } else if access == .notDetermined {
          Button { askContacts() } label: { Label("Search Your Contacts", systemImage: "magnifyingglass") }
        }
        Button { SystemContactPicker.present { addPicked($0) } } label: { Label("Choose from Contacts…", systemImage: "person.2.crop.square.stack") }
      } header: { Text("Contacts") } footer: {
        Text(access == .denied || access == .restricted
             ? "Contacts access is off, so search can't look through them. \"Choose from Contacts\" still works."
             : "Contacts are searched on this phone; nothing is uploaded.")
      }
    }
    .searchable(text: $q, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name, @username, email or phone")
    .autocorrectionDisabled()
    .textInputAutocapitalization(.never)
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.fontWeight(.semibold) } }
    .disabled(busy)
    .task(id: q) { await search() }
  }

  // MARK: Rows

  private func row(_ name: String, sub: String?, on: Bool, linked: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Avatar(name: name, size: 34)
        VStack(alignment: .leading, spacing: 1) {
          Text(name).foregroundStyle(.primary)
          if let sub { Text(sub).font(.caption).foregroundStyle(.secondary) }
        }
        Spacer()
        if linked { Image(systemName: "person.crop.circle.badge.checkmark").foregroundStyle(.secondary).accessibilityLabel("On Paisa Pulse") }
        Image(systemName: on ? "checkmark.circle.fill" : "plus.circle")
          .font(.title3).foregroundStyle(on ? Color.income : Color.accentColor)
          .contentTransition(.symbolEffect(.replace))
      }
    }
    .disabled(on)
    .accessibilityLabel(on ? "\(name), added" : "Add \(name)")
  }

  private func personRow(_ p: CloudLogic.Person) -> some View {
    let local = friends.first { $0.userId == p.id }
    let on = added.contains("u:\(p.id)") || (local.map { chosen.contains($0.id) } ?? false)
    return row(p.label, sub: p.username.map { "@\($0)" }, on: on, linked: true) { addPerson(p) }
  }

  // MARK: Search

  private func search() async {
    let t = term
    try? await Task.sleep(for: .milliseconds(300))
    guard !Task.isCancelled else { return }
    searching = !t.isEmpty
    var l: [ContactHit] = []
    if contactsOn && !t.isEmpty { l = await Self.contacts(matching: t) }
    guard !Task.isCancelled else { return }
    hits = l
    var c: [CloudLogic.Person] = []
    if cloud.signedIn && t.count >= 2 { c = (try? await cloud.find(t)) ?? [] }
    guard !Task.isCancelled else { return }
    found = c; searching = false
  }

  /// Contacts whose name (or number, for digits) matches, read on this phone.
  private static func contacts(matching t: String) async -> [ContactHit] {
    await Task.detached(priority: .userInitiated) {
      let store = CNContactStore()
      let keys: [CNKeyDescriptor] = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey, CNContactPhoneNumbersKey].map { $0 as CNKeyDescriptor }
      var out: [CNContact] = (try? store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: t), keysToFetch: keys)) ?? []
      let digits = t.filter(\.isNumber)
      if digits.count >= 4 {
        let byPhone = (try? store.unifiedContacts(matching: CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: digits)), keysToFetch: keys)) ?? []
        out += byPhone.filter { c in !out.contains { $0.identifier == c.identifier } }
      }
      return out.prefix(30).map { c in
        let name = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        return ContactHit(id: c.identifier, name: name.isEmpty ? (c.organizationName.isEmpty ? "Friend" : c.organizationName) : name,
                          phone: c.phoneNumbers.first?.value.stringValue)
      }
    }.value
  }

  private func askContacts() {
    Task {
      _ = try? await CNContactStore().requestAccess(for: .contacts)
      access = CNContactStore.authorizationStatus(for: .contacts)
      await search()
    }
  }

  // MARK: Adding

  private func pick(_ f: Friend, isNew: Bool) {
    added.insert(f.id)
    onAdd(f, isNew)
    Haptic.soft()
  }

  private func addName(_ name: String) {
    if let f = friends.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { pick(f, isNew: false) }
    else { let f = Friend(name: name); context.insert(f); try? context.save(); pick(f, isNew: true) }
    q = ""
  }

  private func addPerson(_ p: CloudLogic.Person) {
    busy = true
    Task {
      defer { busy = false }
      do {
        if !p.connected { try await cloud.connect(p.id) }
        let existing = friends.first { $0.userId == p.id }
        let f = existing ?? { let n = Friend(id: p.id, name: p.label, upiId: p.upiId, userId: p.id); context.insert(n); return n }()
        try? context.save()
        added.insert("u:\(p.id)")
        pick(f, isNew: existing == nil)
      } catch {
        router.showError("Couldn't add \(p.label). Check your connection.")
      }
    }
  }

  private func addContact(_ c: ContactHit) {
    added.insert("c:\(c.id)")
    addPicked([(c.name, c.phone)])
  }

  /// Contacts → people: reuse someone with the same name; link them if their number is on Paisa Pulse.
  private func addPicked(_ picked: [(name: String, phone: String?)]) {
    Task {
      for c in picked {
        if let f = friends.first(where: { $0.name.caseInsensitiveCompare(c.name) == .orderedSame }) {
          if f.phone == nil { f.phone = c.phone }
          try? context.save(); pick(f, isNew: false); continue
        }
        if cloud.signedIn, let phone = c.phone, let match = try? await cloud.matchContacts([phone]).first {
          let p = match.0
          if !p.connected { _ = try? await cloud.connect(p.id) }
          if let f = friends.first(where: { $0.userId == p.id }) { pick(f, isNew: false); continue }
          let f = Friend(id: p.id, name: c.name, upiId: p.upiId, phone: phone, userId: p.id)
          context.insert(f); try? context.save(); pick(f, isNew: true)
          router.show("\(c.name) is on Paisa Pulse")
          continue
        }
        let f = Friend(name: c.name, phone: c.phone)
        context.insert(f); try? context.save(); pick(f, isNew: true)
      }
    }
  }
}

/// The system contact chooser, presented on its own (not inside another sheet), so its search field and
/// layout are the standard ones. No Contacts permission needed: you only share the people you pick.
@MainActor enum SystemContactPicker {
  private static var delegate: Delegate?

  static func present(onPick: @escaping ([(name: String, phone: String?)]) -> Void) {
    guard let top = topController() else { return }
    let d = Delegate(onPick: onPick)
    delegate = d
    let picker = CNContactPickerViewController()
    picker.delegate = d
    picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
    top.present(picker, animated: true)
  }

  private static func topController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
      ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    var vc = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
    while let next = vc?.presentedViewController, !next.isBeingDismissed { vc = next }
    return vc
  }

  private final class Delegate: NSObject, CNContactPickerDelegate {
    let onPick: ([(name: String, phone: String?)]) -> Void
    init(onPick: @escaping ([(name: String, phone: String?)]) -> Void) { self.onPick = onPick }
    func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
      let people = contacts.map { c -> (name: String, phone: String?) in
        let name = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        return (name.isEmpty ? (c.organizationName.isEmpty ? "Friend" : c.organizationName) : name, c.phoneNumbers.first?.value.stringValue)
      }
      Task { @MainActor in onPick(people); SystemContactPicker.delegate = nil }
    }
    func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
      Task { @MainActor in SystemContactPicker.delegate = nil }
    }
  }
}
