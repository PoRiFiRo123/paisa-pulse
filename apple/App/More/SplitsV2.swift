import ContactsUI
import CoreImage.CIFilterBuiltins
import MessageUI
import SwiftData
import SwiftUI

// Split v2: contacts, who paid, equal / amounts / shares, groups, requests by Messages + QR + pay link,
// "Pay with…" a UPI app and "Did it go through?". Same screens on Android (ui/screens/Splits2.kt).

struct SplitRequest: Identifiable {
  let id = UUID()
  var note: String?
  /// Friend id → what they owe you (paise).
  var amounts: [String: Int]
}

// MARK: - Helpers

/// UPI QR code (any UPI app can scan it).
enum QRCode {
  static func image(_ text: String, size: CGFloat = 600) -> UIImage? {
    let f = CIFilter.qrCodeGenerator()
    f.message = Data(text.utf8)
    f.correctionLevel = "M"
    guard let out = f.outputImage else { return nil }
    let scale = size / out.extent.width
    let ctx = CIContext()
    guard let cg = ctx.createCGImage(out.transformed(by: CGAffineTransform(scaleX: scale, y: scale)), from: CGRect(x: 0, y: 0, width: size, height: size)) else { return nil }
    return UIImage(cgImage: cg)
  }
}

/// The system contact picker (no Contacts permission needed: you only share the people you pick).
struct ContactPicker: UIViewControllerRepresentable {
  var onPick: ([(name: String, phone: String?)]) -> Void

  func makeUIViewController(context: Context) -> Host { Host(onPick: onPick) }
  func updateUIViewController(_ vc: Host, context: Context) {}

  final class Host: UIViewController, CNContactPickerDelegate {
    let onPick: ([(name: String, phone: String?)]) -> Void
    private var shown = false
    init(onPick: @escaping ([(name: String, phone: String?)]) -> Void) { self.onPick = onPick; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidAppear(_ animated: Bool) {
      super.viewDidAppear(animated)
      guard !shown else { return }
      shown = true
      let picker = CNContactPickerViewController()
      picker.delegate = self
      picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
      present(picker, animated: true)
    }
    func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
      onPick(contacts.map { c in
        let name = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        return (name.isEmpty ? (c.organizationName.isEmpty ? "Friend" : c.organizationName) : name, c.phoneNumbers.first?.value.stringValue)
      })
      dismiss(animated: false)
    }
    func contactPickerDidCancel(_ picker: CNContactPickerViewController) { onPick([]); dismiss(animated: false) }
  }
}

/// Messages composer with recipients and text filled in.
struct MessageComposer: UIViewControllerRepresentable {
  var recipients: [String]
  var body: String
  var onDone: () -> Void

  static var available: Bool { MFMessageComposeViewController.canSendText() }

  func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }
  func makeUIViewController(context: Context) -> MFMessageComposeViewController {
    let vc = MFMessageComposeViewController()
    vc.recipients = recipients
    vc.body = body
    vc.messageComposeDelegate = context.coordinator
    return vc
  }
  func updateUIViewController(_ vc: MFMessageComposeViewController, context: Context) {}
  final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
    let onDone: () -> Void
    init(onDone: @escaping () -> Void) { self.onDone = onDone }
    func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) { onDone() }
  }
}

/// UPI apps that can be asked to pay directly; "Any UPI app" always works when one is installed.
enum UpiApps {
  static let all: [(name: String, scheme: String, prefix: String)] = [
    ("Google Pay", "gpay", "gpay://upi/pay?"), ("PhonePe", "phonepe", "phonepe://pay?"), ("Paytm", "paytmmp", "paytmmp://pay?"),
    ("CRED", "credpay", "credpay://upi/pay?"), ("BHIM", "bhim", "bhim://upi/pay?"),
  ]
  @MainActor static var installed: [(name: String, scheme: String, prefix: String)] {
    all.filter { URL(string: "\($0.scheme)://").map(UIApplication.shared.canOpenURL) ?? false }
  }
  static func url(_ prefix: String, from upi: URL) -> URL? { URL(string: prefix + (upi.query ?? "")) }
}

extension Friend {
  var initial: String { String(name.prefix(1)).uppercased() }
}

struct Avatar: View {
  let name: String
  var size: CGFloat = 34
  var body: some View {
    Text(String(name.prefix(1)).uppercased())
      .font(.system(size: size * 0.45, weight: .semibold)).foregroundStyle(.white)
      .frame(width: size, height: size)
      .background(Color(hex: Palette.avatar(name)).gradient, in: Circle())
  }
}

extension Palette {
  static func avatar(_ name: String) -> String {
    let colors = ["#5E5CE6", "#FF9500", "#34C759", "#FF2D55", "#007AFF", "#AF52DE", "#30B0C7", "#E5484D"]
    return colors[abs(name.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }) % colors.count]
  }
}

// MARK: - Split editor (Quick Add › Split)

struct SplitEditorView: View {
  @Binding var setup: SplitSetup
  let total: Int
  @Query(sort: \Friend.name) private var friends: [Friend]
  @Query private var entries: [SplitEntry]
  @Query(sort: \SplitGroup.createdAt) private var groups: [SplitGroup]
  @Environment(\.modelContext) private var context
  @State private var pickingContacts = false
  @State private var newName = ""
  @State private var addingName = false
  @State private var savingGroup = false
  @State private var groupName = ""

  var body: some View {
    // People you split with most often come first.
    let used = Dictionary(grouping: entries, by: \.friendId).mapValues(\.count)
    let ordered = friends.sorted { (used[$0.id] ?? 0, $1.name) > (used[$1.id] ?? 0, $0.name) }
    let result = SplitMath.compute(total: total, setup)
    List {
      if !groups.isEmpty {
        Section("Groups") {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
              ForEach(groups) { g in
                let on = setup.groupId == g.id
                Button {
                  if on { setup.groupId = nil } else { setup.groupId = g.id; setup.people = g.memberIds.filter { id in friends.contains { $0.id == id } } }
                } label: {
                  Label(g.name, systemImage: "person.3.fill").font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .foregroundStyle(on ? Color.white : Color.primary)
                    .background(on ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
              }
            }
            .padding(.horizontal, 16)
          }
          .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
        }
      }
      Section {
        ForEach(ordered) { f in
          let on = setup.people.contains(f.id)
          Button {
            if on { setup.people.removeAll { $0 == f.id }; if setup.payer == f.id { setup.payer = nil } } else { setup.people.append(f.id) }
          } label: {
            HStack(spacing: 12) {
              Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.title3)
                .foregroundStyle(on ? Color.accentColor : Color.secondary)
              Avatar(name: f.name, size: 30)
              Text(f.name).foregroundStyle(.primary)
              Spacer()
              if on, total > 0 { Text(Money.format(result.shares[f.id] ?? 0)).font(.subheadline).foregroundStyle(.secondary) }
            }
          }
        }
        Button { pickingContacts = true } label: { Label("Add from Contacts", systemImage: "person.crop.circle.badge.plus") }
        Button { addingName = true } label: { Label("Add by Name", systemImage: "character.cursor.ibeam") }
      } header: { Text("With") }

      if !setup.people.isEmpty {
        Section {
          Picker("Paid by", selection: $setup.payer) {
            Text("You").tag(String?.none)
            ForEach(friends.filter { setup.people.contains($0.id) }) { Text($0.name).tag(String?.some($0.id)) }
          }
          Toggle("Include me", isOn: $setup.includeMe)
          Picker("Split", selection: $setup.mode) { ForEach(SplitMode.allCases) { Text($0.label).tag($0) } }
            .pickerStyle(.segmented)
        }
        if setup.mode != .equal {
          Section {
            let keys = (setup.includeMe ? ["me"] : []) + setup.people
            ForEach(keys, id: \.self) { k in
              HStack {
                Text(k == "me" ? "You" : friends.first { $0.id == k }?.name ?? "Friend")
                Spacer()
                TextField(setup.mode == .amount ? "₹0" : "1", text: Binding(
                  get: {
                    guard let v = setup.values[k] else { return "" }
                    return setup.mode == .amount ? (v % 100 == 0 ? String(v / 100) : String(format: "%.2f", Double(v) / 100)) : String(v)
                  },
                  set: { t in
                    if setup.mode == .amount { setup.values[k] = Money.parse(t) ?? 0 } else { setup.values[k] = Int(t) ?? 0 }
                  }))
                .keyboardType(setup.mode == .amount ? .decimalPad : .numberPad)
                .multilineTextAlignment(.trailing).frame(width: 110)
                if setup.mode == .shares, total > 0 { Text(Money.format(result.shares[k] ?? 0)).font(.caption).foregroundStyle(.secondary).frame(width: 70, alignment: .trailing) }
              }
            }
          } footer: {
            if setup.mode == .amount && result.unassigned != 0 {
              Text(result.unassigned > 0 ? "\(Money.format(result.unassigned)) left to assign" : "\(Money.format(-result.unassigned)) more than the total")
                .foregroundStyle(Color.expense)
            } else if setup.mode == .shares {
              Text("Shares like 2 : 1 for someone who had twice as much.")
            }
          }
        }
        Section {
          LabeledContent("Your share", value: Money.format(result.myShare))
          if let payer = setup.payer {
            LabeledContent("You'll owe \(friends.first { $0.id == payer }?.name ?? "them")", value: Money.format(result.myShare))
          } else {
            LabeledContent("They'll owe you", value: Money.format(result.entries.values.reduce(0, +)))
          }
          if setup.groupId == nil {
            Button { savingGroup = true } label: { Label("Save These People as a Group", systemImage: "person.3") }
          }
        } footer: {
          Text(setup.payer == nil ? "Only your share counts in your spending. After saving you can send everyone a request."
               : "Nothing leaves your account now. Settle up from Splits when you pay them back.")
        }
      }
    }
    .navigationTitle("Split")
    .toolbar { if !setup.people.isEmpty { ToolbarItem(placement: .destructiveAction) { Button("Clear") { setup = SplitSetup() } } } }
    .sheet(isPresented: $pickingContacts) {
      ContactPicker { picked in
        pickingContacts = false
        for c in picked {
          if let f = friends.first(where: { $0.name.caseInsensitiveCompare(c.name) == .orderedSame }) {
            if f.phone == nil { f.phone = c.phone }
            if !setup.people.contains(f.id) { setup.people.append(f.id) }
          } else {
            let f = Friend(name: c.name, phone: c.phone)
            context.insert(f)
            setup.people.append(f.id)
          }
        }
        try? context.save()
      }
      .ignoresSafeArea()
    }
    .alert("Add person", isPresented: $addingName) {
      TextField("Name", text: $newName)
      Button("Add") {
        if let n = newName.nilIfEmpty { let f = Friend(name: n); context.insert(f); try? context.save(); setup.people.append(f.id) }
        newName = ""
      }
      Button("Cancel", role: .cancel) { newName = "" }
    }
    .alert("Name this group", isPresented: $savingGroup) {
      TextField("Flatmates, Goa trip…", text: $groupName)
      Button("Save") {
        if let n = groupName.nilIfEmpty { let g = SplitGroup(name: n, memberIds: setup.people); context.insert(g); try? context.save(); setup.groupId = g.id }
        groupName = ""
      }
      Button("Cancel", role: .cancel) { groupName = "" }
    }
  }
}

// MARK: - Request (after saving a split, or from a person)

struct RequestView: View {
  let request: SplitRequest
  @Query(sort: \Friend.name) private var friends: [Friend]
  @AppStorage(PrefKey.myUpiId, store: AppGroup.defaults) private var myUpi = ""
  @AppStorage(PrefKey.myName, store: AppGroup.defaults) private var myName = ""
  @Environment(\.dismiss) private var dismiss
  @State private var composing: (recipients: [String], body: String)?
  @State private var qrFor: String?
  @State private var upiDraft = ""

  var body: some View {
    let people = friends.filter { (request.amounts[$0.id] ?? 0) > 0 }
    let name = myName.nilIfEmpty ?? "me"
    List {
      if myUpi.isEmpty {
        Section {
          TextField("Your UPI ID, e.g. you@okaxis", text: $upiDraft)
            .textInputAutocapitalization(.never).keyboardType(.emailAddress).autocorrectionDisabled()
          Button("Save") { myUpi = upiDraft.trimmingCharacters(in: .whitespaces) }.disabled(!upiDraft.contains("@"))
        } footer: { Text("Your UPI ID goes into the request so friends can pay you from any UPI app. It stays on this phone.") }
      }
      Section {
        ForEach(people) { f in
          let amount = request.amounts[f.id] ?? 0
          HStack(spacing: 12) {
            Avatar(name: f.name)
            VStack(alignment: .leading, spacing: 2) {
              Text(f.name)
              Text("owes \(Money.format(amount))").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            if !myUpi.isEmpty {
              Button { qrFor = f.id } label: { Image(systemName: "qrcode") }.buttonStyle(.bordered).accessibilityLabel("Show QR code")
              Button {
                composing = ([f.phone].compactMap { $0 }, SplitMath.requestMessage(friend: f.name, amount: amount, note: request.note, upiId: myUpi, myName: name))
              } label: { Image(systemName: "message.fill") }
              .buttonStyle(.borderedProminent).accessibilityLabel("Send in Messages")
            }
          }
        }
      } header: { Text(request.note.map { "Split: \($0)" } ?? "Split") } footer: {
        Text("The message has a link to a simple pay page (details only in the link) with a QR code and a Pay button.")
      }
      if people.count > 1, !myUpi.isEmpty, MessageComposer.available {
        Section {
          Button {
            let lines = people.map { "\($0.name): \(Money.format(request.amounts[$0.id] ?? 0))" }.joined(separator: "\n")
            let total = people.reduce(0) { $0 + (request.amounts[$1.id] ?? 0) }
            let each = people.first.map { request.amounts[$0.id] ?? 0 } ?? 0
            let link = SplitMath.payPageURL(to: myUpi, name: name, amount: each, note: request.note)?.absoluteString ?? ""
            composing = (people.compactMap(\.phone), "Split\(request.note.map { " for \($0)" } ?? ""):\n\(lines)\nTotal \(Money.format(total)). Pay me on UPI: \(link)")
          } label: { Label("Message Everyone", systemImage: "person.3.fill") }
        }
      }
    }
    .navigationTitle("Ask to Pay")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    .sheet(isPresented: Binding(get: { composing != nil }, set: { if !$0 { composing = nil } })) {
      if let c = composing {
        if MessageComposer.available {
          MessageComposer(recipients: c.recipients, body: c.body) { composing = nil }.ignoresSafeArea()
        } else {
          ShareSheetFallback(text: c.body)
        }
      }
    }
    .sheet(isPresented: Binding(get: { qrFor != nil }, set: { if !$0 { qrFor = nil } })) {
      if let id = qrFor, let f = friends.first(where: { $0.id == id }) {
        QRSheet(title: "\(f.name) pays you", amount: request.amounts[id] ?? 0,
                upi: SplitMath.upiURL(to: myUpi, name: name, amount: request.amounts[id] ?? 0, note: request.note))
      }
    }
  }
}

struct ShareSheetFallback: View {
  let text: String
  var body: some View {
    VStack(spacing: 16) {
      Text("Messages isn't set up on this phone. Share the request another way.").multilineTextAlignment(.center).foregroundStyle(.secondary)
      ShareLink(item: text) { Label("Share Request", systemImage: "square.and.arrow.up") }.buttonStyle(.borderedProminent)
    }
    .padding().presentationDetents([.medium])
  }
}

struct QRSheet: View {
  let title: String
  let amount: Int
  let upi: URL?
  var body: some View {
    VStack(spacing: 14) {
      Text(title).font(.headline)
      Text(Money.format(amount)).font(.system(size: 40, weight: .bold, design: .rounded))
      if let upi, let img = QRCode.image(upi.absoluteString) {
        Image(uiImage: img).interpolation(.none).resizable().scaledToFit().frame(width: 240, height: 240)
          .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 20))
        Text("Scan with any UPI app").font(.footnote).foregroundStyle(.secondary)
        ShareLink(item: Image(uiImage: img), preview: SharePreview("UPI QR", image: Image(uiImage: img))) {
          Label("Share QR", systemImage: "square.and.arrow.up")
        }
      }
    }
    .padding(24)
    .presentationDetents([.medium, .large])
  }
}

// MARK: - Splits home

struct SplitsView: View {
  @Query(sort: \Friend.name) private var friends: [Friend]
  @Query(sort: \SplitEntry.occurredAt, order: .reverse) private var entries: [SplitEntry]
  @Query(sort: \SplitGroup.createdAt) private var groups: [SplitGroup]
  @AppStorage(PrefKey.myUpiId, store: AppGroup.defaults) private var myUpi = ""
  @AppStorage(PrefKey.myName, store: AppGroup.defaults) private var myName = ""
  @Environment(\.modelContext) private var context
  @State private var newName = ""
  @State private var addingFriend = false
  @State private var pickingContacts = false
  @State private var addingGroup = false

  var body: some View {
    let balances = Splits.balances(entries)
    let owedToYou = balances.values.filter { $0 > 0 }.reduce(0, +)
    let youOwe = -balances.values.filter { $0 < 0 }.reduce(0, +)
    List {
      Section {
        HStack(spacing: 0) {
          SummaryCell(label: "You're owed", value: owedToYou, color: .income)
          SummaryCell(label: "You owe", value: youOwe, color: .expense)
        }
        .frame(height: 52)
      } footer: {
        Text("Split an expense from Quick Add › Split. Your share is what counts in your spending.")
      }
      Section("Groups") {
        ForEach(groups) { g in
          NavigationLink { GroupDetailView(group: g) } label: {
            HStack(spacing: 12) {
              CategoryBadge(icon: "person.3.fill", color: "#5E5CE6", size: 34)
              VStack(alignment: .leading, spacing: 2) {
                Text(g.name)
                Text(g.memberIds.compactMap { id in friends.first { $0.id == id }?.name }.joined(separator: ", ")).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
              }
            }
          }
        }
        Button { addingGroup = true } label: { Label("New Group", systemImage: "plus") }
      }
      Section("People") {
        if friends.isEmpty { Text("Add the people you split with").foregroundStyle(.secondary) }
        ForEach(friends) { f in
          NavigationLink { FriendDetailView(friend: f) } label: {
            HStack {
              Avatar(name: f.name)
              Text(f.name)
              Spacer()
              BalanceLabel(balance: balances[f.id] ?? 0)
            }
          }
        }
        Button { pickingContacts = true } label: { Label("Add from Contacts", systemImage: "person.crop.circle.badge.plus") }
      }
      Section {
        TextField("Your name", text: $myName)
        TextField("Your UPI ID, e.g. you@okaxis", text: $myUpi)
          .textInputAutocapitalization(.never).keyboardType(.emailAddress).autocorrectionDisabled()
      } header: { Text("For requests") } footer: {
        Text("Requests include a link to a pay page and a QR code for this UPI ID. It stays on this phone.")
      }
    }
    .navigationTitle("Splits")
    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { addingFriend = true } label: { Image(systemName: "person.badge.plus") } } }
    .alert("Add person", isPresented: $addingFriend) {
      TextField("Name", text: $newName)
      Button("Add") { if let n = newName.nilIfEmpty { context.insert(Friend(name: n)); try? context.save() }; newName = "" }
      Button("Cancel", role: .cancel) { newName = "" }
    }
    .sheet(isPresented: $pickingContacts) {
      ContactPicker { picked in
        pickingContacts = false
        for c in picked where !friends.contains(where: { $0.name.caseInsensitiveCompare(c.name) == .orderedSame }) {
          context.insert(Friend(name: c.name, phone: c.phone))
        }
        try? context.save()
      }
      .ignoresSafeArea()
    }
    .sheet(isPresented: $addingGroup) { NavigationStack { GroupFormView(group: nil) } }
  }
}

struct BalanceLabel: View {
  let balance: Int
  var body: some View {
    if balance == 0 { Text("settled").foregroundStyle(.secondary).font(.subheadline) }
    else {
      VStack(alignment: .trailing, spacing: 0) {
        Text(Money.format(balance)).fontDesign(.rounded).foregroundStyle(balance > 0 ? Color.income : Color.expense)
        Text(balance > 0 ? "owes you" : "you owe").font(.caption2).foregroundStyle(.secondary)
      }
    }
  }
}

// MARK: - A person

struct FriendDetailView: View {
  @Bindable var friend: Friend
  var groupId: String? = nil
  @Query(sort: \SplitEntry.occurredAt, order: .reverse) private var entries: [SplitEntry]
  @Query(filter: #Predicate<Account> { $0.archivedAt == nil }, sort: \Account.sortOrder) private var accounts: [Account]
  @AppStorage(PrefKey.myUpiId, store: AppGroup.defaults) private var myUpi = ""
  @AppStorage(PrefKey.lastAccountId, store: AppGroup.defaults) private var lastAccountId = ""
  @Environment(\.modelContext) private var context
  @Environment(\.openURL) private var openURL
  @Environment(\.scenePhase) private var scenePhase
  @Environment(Router.self) private var router
  @State private var manual: Int? // +1 they owe me, -1 I owe them
  @State private var manualAmount = ""
  @State private var manualNote = ""
  @State private var paying: Int?
  @State private var askPaid = false

  var body: some View {
    let mine = entries.filter { $0.friendId == friend.id && (groupId == nil || $0.groupId == groupId) }
    let balance = mine.reduce(0) { $0 + $1.amount }
    List {
      Section {
        VStack(spacing: 4) {
          Avatar(name: friend.name, size: 56)
          Text(balance == 0 ? "All settled" : balance > 0 ? "\(friend.name) owes you" : "You owe \(friend.name)")
            .font(.subheadline).foregroundStyle(.secondary).padding(.top, 6)
          Text(Money.format(balance)).font(.system(size: 40, weight: .bold, design: .rounded))
            .foregroundStyle(balance > 0 ? Color.income : balance < 0 ? Color.expense : .primary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        if balance > 0 {
          Button { router.request = SplitRequest(note: nil, amounts: [friend.id: balance]) } label: {
            Label("Ask \(friend.name) to Pay", systemImage: "paperplane.fill")
          }
        }
        if balance < 0 {
          if let id = friend.upiId?.nilIfEmpty, let upi = SplitMath.upiURL(to: id, name: friend.name, amount: -balance, note: "Settle up") {
            Menu {
              ForEach(UpiApps.installed, id: \.scheme) { app in
                Button(app.name) { pay(UpiApps.url(app.prefix, from: upi) ?? upi, amount: -balance) }
              }
              Button("Any UPI App") { pay(upi, amount: -balance) }
            } label: { Label("Pay \(Money.format(-balance)) with…", systemImage: "indianrupeesign.circle.fill") }
          }
        }
        if balance != 0 {
          Button {
            settle(balance)
          } label: { Label("Mark as Settled", systemImage: "checkmark.circle") }
        }
      }
      Section {
        Button { manual = 1 } label: { Label("They Owe Me…", systemImage: "arrow.down.left.circle") }
        Button { manual = -1 } label: { Label("I Owe Them…", systemImage: "arrow.up.right.circle") }
      } footer: { Text("For money that isn't a split expense, like cash they handed you.") }
      Section {
        TextField("UPI ID, e.g. name@okaxis", text: Binding(get: { friend.upiId ?? "" }, set: { friend.upiId = $0.nilIfEmpty }))
          .textInputAutocapitalization(.never).keyboardType(.emailAddress).autocorrectionDisabled()
        TextField("Phone (for Messages)", text: Binding(get: { friend.phone ?? "" }, set: { friend.phone = $0.nilIfEmpty }))
          .keyboardType(.phonePad)
      } footer: { Text("UPI ID lets you pay them from any UPI app; phone fills in Messages when you send a request.") }
      Section("History") {
        ForEach(mine) { e in
          HStack {
            VStack(alignment: .leading) {
              Text(e.note ?? (e.txnId == nil ? "Settle up" : "Split"))
              Text(e.occurredAt.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.format(e.amount)).fontDesign(.rounded).foregroundStyle(e.amount > 0 ? Color.income : Color.expense)
          }
        }
        .onDelete { idx in idx.map { mine[$0] }.forEach { context.delete($0) }; try? context.save() }
      }
    }
    .navigationTitle(friend.name)
    .onDisappear { try? context.save() }
    .onChange(of: scenePhase) { _, phase in if phase == .active, paying != nil { askPaid = true } }
    .alert("Did it go through?", isPresented: $askPaid) {
      Button("Yes, I Paid") {
        if let amount = paying {
          let accountId = accounts.first { $0.id == lastAccountId }?.id ?? accounts.first?.id
          if let accountId {
            context.insert(Txn(type: .expense, amount: amount, accountId: accountId, payee: friend.name, note: "Settled up", source: "settle"))
          }
          context.insert(SplitEntry(friendId: friend.id, amount: amount, note: "Paid by UPI", groupId: groupId))
          try? context.save()
          WidgetRefresh.now()
          router.show("Settled with \(friend.name)")
        }
        paying = nil
      }
      Button("No", role: .cancel) { paying = nil }
    } message: { Text("If the UPI app says it worked, we'll record the payment and settle up.") }
    .alert(manual == 1 ? "\(friend.name) owes you" : "You owe \(friend.name)", isPresented: Binding(get: { manual != nil }, set: { if !$0 { manual = nil } })) {
      TextField("Amount", text: $manualAmount).keyboardType(.decimalPad)
      TextField("What for (optional)", text: $manualNote)
      Button("Add") {
        if let p = Money.parse(manualAmount), let sign = manual {
          context.insert(SplitEntry(friendId: friend.id, amount: sign * p, note: manualNote.nilIfEmpty ?? (sign > 0 ? "They owe me" : "I owe them"), groupId: groupId))
          try? context.save()
        }
        manualAmount = ""; manualNote = ""
      }
      Button("Cancel", role: .cancel) { manualAmount = ""; manualNote = "" }
    }
  }

  private func pay(_ url: URL, amount: Int) {
    paying = amount
    openURL(url)
  }

  private func settle(_ balance: Int) {
    let e = SplitEntry(friendId: friend.id, amount: -balance, note: "Settled up", groupId: groupId)
    context.insert(e)
    try? context.save()
    router.show("Settled") { context.delete(e); try? context.save() }
  }
}

// MARK: - Groups

struct GroupDetailView: View {
  @Bindable var group: SplitGroup
  @Query(sort: \Friend.name) private var friends: [Friend]
  @Query(sort: \SplitEntry.occurredAt, order: .reverse) private var entries: [SplitEntry]
  @Environment(\.modelContext) private var context
  @Environment(\.dismiss) private var dismiss
  @State private var editing = false

  var body: some View {
    let mine = entries.filter { $0.groupId == group.id }
    let balances = Splits.balances(mine)
    let members = friends.filter { group.memberIds.contains($0.id) }
    List {
      Section {
        HStack(spacing: 0) {
          SummaryCell(label: "Owed to you", value: balances.values.filter { $0 > 0 }.reduce(0, +), color: .income)
          SummaryCell(label: "You owe", value: -balances.values.filter { $0 < 0 }.reduce(0, +), color: .expense)
        }
        .frame(height: 52)
      }
      Section("Members") {
        ForEach(members) { f in
          NavigationLink { FriendDetailView(friend: f, groupId: group.id) } label: {
            HStack { Avatar(name: f.name); Text(f.name); Spacer(); BalanceLabel(balance: balances[f.id] ?? 0) }
          }
        }
      }
      if balances.values.contains(where: { $0 != 0 }) {
        Section {
          Button {
            for (f, b) in balances where b != 0 { context.insert(SplitEntry(friendId: f, amount: -b, note: "Settled up", groupId: group.id)) }
            try? context.save()
          } label: { Label("Settle Up Everyone", systemImage: "checkmark.circle") }
        } footer: { Text("Marks every balance in this group as paid.") }
      }
      Section("Activity") {
        ForEach(mine.prefix(50)) { e in
          HStack {
            VStack(alignment: .leading) {
              Text(e.note ?? "Split")
              Text("\(friends.first { $0.id == e.friendId }?.name ?? "Friend") · \(e.occurredAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.format(e.amount)).fontDesign(.rounded).foregroundStyle(e.amount > 0 ? Color.income : Color.expense)
          }
        }
      }
    }
    .navigationTitle(group.name)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button { editing = true } label: { Label("Edit", systemImage: "pencil") }
          Button(role: .destructive) { context.delete(group); try? context.save(); dismiss() } label: { Label("Delete Group", systemImage: "trash") }
        } label: { Image(systemName: "ellipsis") }
      }
    }
    .sheet(isPresented: $editing) { NavigationStack { GroupFormView(group: group) } }
  }
}

struct GroupFormView: View {
  var group: SplitGroup?
  @Query(sort: \Friend.name) private var friends: [Friend]
  @Environment(\.modelContext) private var context
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var members: [String] = []

  var body: some View {
    Form {
      TextField("Name (Flatmates, Goa trip…)", text: $name)
      Section("Members") {
        if friends.isEmpty { Text("Add people in Splits first.").foregroundStyle(.secondary) }
        ForEach(friends) { f in
          Button {
            if members.contains(f.id) { members.removeAll { $0 == f.id } } else { members.append(f.id) }
          } label: {
            HStack {
              Image(systemName: members.contains(f.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(members.contains(f.id) ? Color.accentColor : .secondary)
              Avatar(name: f.name, size: 28)
              Text(f.name).foregroundStyle(.primary)
            }
          }
        }
      }
    }
    .navigationTitle(group == nil ? "New Group" : "Edit Group")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          if let group { group.name = name; group.memberIds = members } else { context.insert(SplitGroup(name: name, memberIds: members)) }
          try? context.save(); dismiss()
        }
        .disabled(name.nilIfEmpty == nil || members.isEmpty)
      }
    }
    .onAppear { if let group { name = group.name; members = group.memberIds } }
  }
}
