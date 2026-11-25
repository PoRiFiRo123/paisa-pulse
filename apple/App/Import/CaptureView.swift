import PhotosUI
import SwiftData
import SwiftUI
import Vision

/// Read payment screenshots (GPay, PhonePe, Paytm, CRED, bank apps) with on-device text recognition,
/// then review and add them. Same flow as the Android app's screenshot capture.
struct CaptureView: View {
  @Query(sort: \Account.sortOrder) private var accounts: [Account]
  @Query(sort: \Category.sortOrder) private var categories: [Category]
  @Query(filter: #Predicate<Txn> { $0.deletedAt == nil }) private var txns: [Txn]
  @Environment(\.modelContext) private var context
  @Environment(Router.self) private var router
  @Environment(\.dismiss) private var dismiss
  @AppStorage(PrefKey.lastAccountId, store: AppGroup.defaults) private var lastAccountId = ""
  @State private var items: [PhotosPickerItem] = []
  @State private var drafts: [CaptureDraft] = []
  @State private var unread = 0
  @State private var reading = false

  var body: some View {
    let lookups = Lookups(accounts: accounts, categories: categories)
    List {
      Section {
        PhotosPicker(selection: $items, maxSelectionCount: 20, matching: .screenshots) {
          Label(reading ? "Reading…" : drafts.isEmpty ? "Choose Screenshots" : "Choose More", systemImage: "photo.on.rectangle")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent).controlSize(.large).disabled(reading)
        .listRowBackground(Color.clear)
      } footer: {
        Text(unread > 0 ? "\(unread) screenshot\(unread == 1 ? "" : "s") had no amount we could read."
             : "Payment screens from GPay, PhonePe, Paytm, BHIM, CRED, Amazon Pay, WhatsApp, Navi or your bank. Read on this phone. Tip: share a screenshot straight from any UPI app to Paisa Pulse.")
      }
      if drafts.isEmpty && !reading {
        EmptyHint(title: "Snap it, log it", icon: "camera.viewfinder",
                  message: "Take a screenshot after you pay, then pick it here. Amount, payee, date and account are filled in.")
      }
      ForEach($drafts) { $d in DraftRow(draft: $d, lookups: lookups, accounts: accounts.filter { $0.archivedAt == nil }, categories: categories) }
    }
    .navigationTitle("From Screenshots")
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        let n = drafts.filter { $0.include && $0.accountId != nil }.count
        Button("Add \(n)") { commit() }.fontWeight(.semibold).disabled(n == 0)
      }
    }
    .onChange(of: items) { _, picked in
      guard !picked.isEmpty else { return }
      Task { await read(picked); items = [] }
    }
  }

  private func read(_ picked: [PhotosPickerItem]) async {
    reading = true
    defer { reading = false }
    let ctx = CaptureDrafts.context(accounts: accounts, categories: categories, txns: Array(txns),
                                    defaultAccountId: lastAccountId.isEmpty ? nil : lastAccountId)
    var missed = 0
    for (i, item) in picked.enumerated() {
      guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data)?.cgImage else { missed += 1; continue }
      let lines = await Self.recognize(image)
      guard var d = ScreenshotParser.parse(lines, ctx: ctx, key: "shot-\(drafts.count + i)-\(UUID().uuidString.prefix(4))") else { missed += 1; continue }
      if d.warning == nil, looksLogged(d) { d.include = false; d.warning = "Looks like you've already added this one." }
      drafts.append(d)
    }
    unread = missed
  }

  private func looksLogged(_ d: CaptureDraft) -> Bool {
    txns.contains { $0.amount == d.amount && abs($0.occurredAt.timeIntervalSince(d.occurredAt)) <= 86_400 }
  }

  static func recognize(_ image: CGImage) async -> [String] { await ScreenText.read(image) }

  private func commit() {
    var added: [Txn] = []
    for d in drafts where d.include {
      guard let accountId = d.accountId else { continue }
      let t = Txn(type: d.type, amount: d.amount, accountId: accountId, toAccountId: d.toAccountId, categoryId: d.categoryId,
                  payee: d.payee, note: d.note, occurredAt: d.occurredAt, source: "screenshot")
      if d.type != .transfer { t.paymentMethod = PaymentMethod.upi.rawValue }
      context.insert(t)
      added.append(t)
    }
    try? context.save()
    WidgetRefresh.now()
    dismiss()
    router.show("Added \(added.count)") {
      added.forEach { $0.deletedAt = .now }
      try? context.save()
      WidgetRefresh.now()
    }
  }
}

/// One captured transaction to check before adding (shared look with Android's DraftCard).
struct DraftRow: View {
  @Binding var draft: CaptureDraft
  let lookups: Lookups
  let accounts: [Account]
  let categories: [Category]

  var body: some View {
    let c = draft.categoryId.flatMap { lookups.categories[$0] }
    HStack(alignment: .top, spacing: 12) {
      Button { draft.include.toggle() } label: {
        Image(systemName: draft.include ? "checkmark.circle.fill" : "circle").font(.title3)
          .foregroundStyle(draft.include ? Color.accentColor : Color.secondary)
      }
      .buttonStyle(.pressable)
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          if draft.type == .transfer {
            Text("To \(draft.toAccountId.flatMap { lookups.accounts[$0]?.name } ?? "card")").lineLimit(1)
          } else {
            TextField("Payee", text: Binding(get: { draft.payee ?? "" }, set: { draft.payee = $0.isEmpty ? nil : $0 }))
          }
          Spacer()
          AmountText(amount: draft.amount, type: draft.type)
        }
        HStack(spacing: 10) {
          DatePicker("", selection: $draft.occurredAt, displayedComponents: [.date, .hourAndMinute]).labelsHidden().scaleEffect(0.9, anchor: .leading)
        }
        HStack(spacing: 12) {
          Menu {
            Picker("Type", selection: $draft.type) { ForEach(TxnType.allCases) { Text($0.label).tag($0) } }
          } label: { Text(draft.type.label).font(.caption.weight(.medium)) }
          Menu {
            ForEach(accounts) { a in Button(a.name) { draft.accountId = a.id } }
          } label: {
            Label(draft.accountId.flatMap { lookups.accounts[$0]?.name } ?? "Account", systemImage: "building.columns").font(.caption.weight(.medium))
          }
          if draft.type != .transfer {
            Menu {
              Button("Uncategorised") { draft.categoryId = nil }
              ForEach(categories.filter { $0.archivedAt == nil && $0.kind == (draft.type == .income ? .income : .expense) }) { cat in
                Button { draft.categoryId = cat.id } label: { Label(cat.name, systemImage: cat.icon) }
              }
            } label: {
              Label(c?.name ?? "Category", systemImage: c?.icon ?? "questionmark.circle").font(.caption.weight(.medium))
            }
          }
        }
        if let w = draft.warning {
          Label(w, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
        }
      }
    }
    .opacity(draft.include ? 1 : 0.6)
    .padding(.vertical, 2)
  }
}
