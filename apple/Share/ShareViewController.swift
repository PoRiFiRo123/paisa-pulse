import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WidgetKit

/// Share a payment screenshot from any UPI app (GPay, PhonePe, Paytm, BHIM…) → read it on the phone,
/// check the details, tap Save. Writes straight into the shared database in the App Group.
final class ShareViewController: UIViewController {
  override func viewDidLoad() {
    super.viewDidLoad()
    let model = ShareModel(context: extensionContext)
    let host = UIHostingController(rootView: ShareView(model: model).modelContainer(Store.makeContainer()))
    addChild(host)
    host.view.frame = view.bounds
    host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(host.view)
    host.didMove(toParent: self)
  }
}

@MainActor @Observable final class ShareModel {
  let context: NSExtensionContext?
  var images: [CGImage] = []
  var drafts: [CaptureDraft] = []
  var reading = true
  var unread = 0
  /// Pictures the sharing app handed over in a form we couldn't open.
  var unopened = 0

  init(context: NSExtensionContext?) { self.context = context }

  func done() { context?.completeRequest(returningItems: nil) }

  /// The shared images, whichever way the app hands them over (file URL, data or UIImage).
  func loadImages() async {
    let providers = (context?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
      .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
    for p in providers.prefix(10) {
      if let img = await Self.image(from: p) { images.append(img) } else { unopened += 1 }
    }
  }

  /// Apps share pictures as data, a file or a UIImage; try each (CRED, GPay and Photos all differ).
  private static func image(from p: NSItemProvider) async -> CGImage? {
    let type = p.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .image) == true } ?? UTType.image.identifier
    if let data = await withCheckedContinuation({ (c: CheckedContinuation<Data?, Never>) in
      _ = p.loadDataRepresentation(forTypeIdentifier: type) { d, _ in c.resume(returning: d) }
    }), let img = UIImage(data: data)?.cgImage { return img }
    if let data = await withCheckedContinuation({ (c: CheckedContinuation<Data?, Never>) in
      _ = p.loadFileRepresentation(forTypeIdentifier: type) { url, _ in c.resume(returning: url.flatMap { try? Data(contentsOf: $0) }) }
    }), let img = UIImage(data: data)?.cgImage { return img }
    return await withCheckedContinuation { cont in
      p.loadItem(forTypeIdentifier: UTType.image.identifier) { item, _ in
        var image: UIImage?
        if let url = item as? URL, let data = try? Data(contentsOf: url) { image = UIImage(data: data) }
        else if let data = item as? Data { image = UIImage(data: data) }
        else if let ui = item as? UIImage { image = ui }
        cont.resume(returning: image?.cgImage)
      }
    }
  }

  func read(accounts: [Account], categories: [Category], txns: [Txn]) async {
    defer { reading = false }
    await loadImages()
    let last = AppGroup.defaults.string(forKey: PrefKey.lastAccountId)
    let ctx = CaptureDrafts.context(accounts: accounts, categories: categories, txns: txns, defaultAccountId: last?.isEmpty == false ? last : nil)
    for (i, img) in images.enumerated() {
      let lines = await ScreenText.read(img)
      guard var d = ScreenshotParser.parse(lines, ctx: ctx, key: "share-\(i)") else { unread += 1; continue }
      if d.warning == nil, txns.contains(where: { $0.amount == d.amount && abs($0.occurredAt.timeIntervalSince(d.occurredAt)) <= 86_400 }) {
        d.include = false; d.warning = "Looks like you've already added this one."
      }
      drafts.append(d)
    }
  }
}

struct ShareView: View {
  @Bindable var model: ShareModel
  @Environment(\.modelContext) private var context
  @Query(sort: \Account.sortOrder) private var accounts: [Account]
  @Query(sort: \Category.sortOrder) private var categories: [Category]
  @Query(filter: #Predicate<Txn> { $0.deletedAt == nil }) private var txns: [Txn]
  @AppStorage(PrefKey.accent, store: AppGroup.defaults) private var accent = "indigo"
  @AppStorage(PrefKey.theme, store: AppGroup.defaults) private var theme = "system"
  @State private var saved = false

  var body: some View {
    NavigationStack {
      Group {
        if model.reading {
          VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("Reading the screenshot…").font(.headline)
            Text("On this phone. Nothing is uploaded.").font(.footnote).foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if saved {
          VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(Color.income).symbolEffect(.bounce, value: saved)
            Text("Saved to Paisa Pulse").font(.headline)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.drafts.isEmpty {
          if model.unopened > 0 && model.images.isEmpty {
            ContentUnavailableView("Couldn't open the picture", systemImage: "photo.badge.exclamationmark",
                                   description: Text("This app shared it in a form Paisa Pulse can't read. Take a screenshot of the payment instead and share that from Photos."))
          } else {
            ContentUnavailableView("No payment found", systemImage: "doc.text.magnifyingglass",
                                   description: Text("Couldn't read an amount in this picture. Share the payment's success screen or receipt from GPay, PhonePe, Paytm, CRED or your bank."))
          }
        } else {
          List {
            ForEach($model.drafts) { $d in
              ShareDraftCard(draft: $d, accounts: accounts.filter { $0.archivedAt == nil }, categories: categories.filter { $0.archivedAt == nil })
            }
            if model.unread > 0 {
              Text("\(model.unread) picture\(model.unread == 1 ? "" : "s") had no amount we could read.").font(.footnote).foregroundStyle(.secondary)
            }
          }
        }
      }
      .navigationTitle("Paisa Pulse")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button(saved ? "Done" : "Cancel") { model.done() } }
        if !model.reading && !saved && !model.drafts.isEmpty {
          let n = model.drafts.filter { $0.include && $0.accountId != nil }.count
          ToolbarItem(placement: .confirmationAction) {
            Button(n > 1 ? "Save \(n)" : "Save") { save() }.fontWeight(.semibold).disabled(n == 0)
          }
        }
      }
    }
    .tint(Palette.accent(accent))
    .preferredColorScheme(theme == "light" ? .light : theme == "dark" ? .dark : nil)
    .sensoryFeedback(.success, trigger: saved)
    .task { await model.read(accounts: accounts, categories: categories, txns: Array(txns)) }
  }

  private func save() {
    for d in model.drafts where d.include {
      guard let accountId = d.accountId else { continue }
      context.insert(Txn(type: d.type, amount: d.amount, accountId: accountId, toAccountId: d.toAccountId, categoryId: d.categoryId,
                         payee: d.payee, note: d.note, occurredAt: d.occurredAt, source: "screenshot"))
    }
    try? context.save()
    WidgetCenter.shared.reloadAllTimelines()
    withAnimation(.spring) { saved = true }
    Task { try? await Task.sleep(for: .seconds(1.1)); model.done() }
  }
}

/// One payment to check: amount, payee, date, account, category, with the parser's warning.
struct ShareDraftCard: View {
  @Binding var draft: CaptureDraft
  let accounts: [Account]
  let categories: [Category]

  var body: some View {
    let cat = draft.categoryId.flatMap { id in categories.first { $0.id == id } }
    let account = draft.accountId.flatMap { id in accounts.first { $0.id == id } }
    Section {
      HStack {
        Text(draft.type == .income ? "Received" : draft.type == .transfer ? "Card bill" : "Paid").foregroundStyle(.secondary)
        Spacer()
        Text(Money.format(draft.amount)).font(.system(size: 30, weight: .bold, design: .rounded))
          .foregroundStyle(draft.type == .income ? Color.income : draft.type == .transfer ? Color.secondary : Color.expense)
      }
      if draft.type != .transfer {
        TextField("Payee", text: Binding(get: { draft.payee ?? "" }, set: { draft.payee = $0.isEmpty ? nil : $0 }))
      }
      DatePicker("Date", selection: $draft.occurredAt, displayedComponents: [.date, .hourAndMinute])
      Picker("Account", selection: Binding(get: { draft.accountId ?? "" }, set: { draft.accountId = $0 })) {
        if account == nil { Text("Choose").tag("") }
        ForEach(accounts) { Text($0.name).tag($0.id) }
      }
      if draft.type != .transfer {
        Picker(selection: Binding(get: { draft.categoryId ?? "" }, set: { draft.categoryId = $0.isEmpty ? nil : $0 })) {
          Text("Uncategorised").tag("")
          ForEach(categories.filter { $0.kind == (draft.type == .income ? .income : .expense) }) { c in
            Label(c.name, systemImage: c.icon).tag(c.id)
          }
        } label: {
          Label { Text("Category") } icon: { Image(systemName: cat?.icon ?? "tag").foregroundStyle(Color(hex: cat?.color ?? "#8E8E93")) }
        }
      }
      Picker("Type", selection: $draft.type) { ForEach(TxnType.allCases) { Text($0.label).tag($0) } }
      Toggle("Add this one", isOn: $draft.include)
    } footer: {
      if let w = draft.warning { Label(w, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
    }
  }
}
