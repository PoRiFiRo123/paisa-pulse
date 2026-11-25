import PhotosUI
import SwiftData
import SwiftUI

/// Receipt photos live in Documents/receipts on this phone (not in backups, to keep them small).
enum Receipts {
  static var folder: URL { URL.documentsDirectory.appending(path: "receipts") }
  static func url(_ name: String) -> URL { folder.appending(path: name) }
  static func save(_ image: UIImage, for id: String) -> String? {
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let scaled = image.preparingThumbnail(of: CGSize(width: 1600, height: 1600 * image.size.height / max(image.size.width, 1))) ?? image
    guard let data = scaled.jpegData(compressionQuality: 0.75) else { return nil }
    let name = "\(id)-\(Int(Date.now.timeIntervalSince1970)).jpg"
    do { try data.write(to: url(name)); return name } catch { return nil }
  }
  static func delete(_ name: String?) { if let name { try? FileManager.default.removeItem(at: url(name)) } }
  static func image(_ name: String?) -> UIImage? { name.flatMap { UIImage(contentsOfFile: url($0).path) } }
}

struct TransactionDetailView: View {
  @Bindable var txn: Txn
  @Environment(Router.self) private var router
  @Environment(\.modelContext) private var context
  @Environment(\.dismiss) private var dismiss
  @Query private var accounts: [Account]
  @Query private var categories: [Category]
  @Query private var friends: [Friend]
  @Query private var splitEntries: [SplitEntry]
  @Query private var trips: [Trip]
  @Query private var tripItems: [TripItem]
  @Query private var cards: [PaymentCard]
  @State private var editingRate = false
  @State private var rateText = ""
  @State private var repeatSheet = false
  @State private var photo: PhotosPickerItem?
  @State private var showingReceipt = false
  @State private var savingTemplate = false
  @State private var templateName = ""

  var body: some View {
    let lookups = Lookups(accounts: accounts, categories: categories)
    let badge = lookups.badge(txn)
    let mySplits = splitEntries.filter { $0.txnId == txn.id }
    List {
      Section {
        VStack(spacing: 10) {
          CategoryBadge(icon: badge.icon, color: badge.color, size: 64)
          Text(lookups.title(txn)).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
          AmountText(amount: txn.amount, type: txn.type, font: .system(size: 44, weight: .bold))
          if let c = txn.currency, let o = txn.originalAmount {
            Text(Money.format(o, code: c)).font(.title3.weight(.semibold)).fontDesign(.rounded).foregroundStyle(.secondary)
          }
          Text(txn.occurredAt.formatted(date: .complete, time: .shortened)).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
      }
      .listRowBackground(Color.clear)

      Section {
        LabeledContent("Type", value: txn.type.label)
        if txn.type == .transfer {
          LabeledContent("From", value: lookups.accounts[txn.accountId]?.displayName ?? "—")
          LabeledContent("To", value: txn.toAccountId.flatMap { lookups.accounts[$0]?.displayName } ?? "—")
        } else {
          LabeledContent("Category", value: txn.categoryId.flatMap { lookups.categories[$0]?.name } ?? "Uncategorised")
          LabeledContent("Account", value: lookups.accounts[txn.accountId]?.displayName ?? "—")
        }
        if let m = PaymentMethod(rawValue: txn.paymentMethod ?? "") {
          LabeledContent("Paid by") { Label(m.label, systemImage: m.icon) }
        }
        if let tid = txn.tripId, let trip = trips.first(where: { $0.id == tid }) {
          NavigationLink { TripDetailView(trip: trip) } label: {
            LabeledContent("Trip") {
              Text([trip.name, txn.tripItemId.flatMap { id in tripItems.first { $0.id == id }?.label }].compactMap { $0 }.joined(separator: " · "))
            }
          }
        }
        if let note = txn.note, !note.isEmpty { LabeledContent("Note", value: note) }
        if !txn.tags.isEmpty {
          LabeledContent("Tags") {
            Text(txn.tags.map { "#\($0)" }.joined(separator: " ")).foregroundStyle(Color.accentColor)
          }
        }
        if txn.source != "manual" { LabeledContent("Added by", value: txn.source.capitalized) }
      }

      if let c = txn.currency, let o = txn.originalAmount, o > 0 {
        Section {
          LabeledContent("Spent in \(c)", value: Money.format(o, code: c))
          let card = txn.cardId.flatMap { id in cards.first { $0.id == id } }
          let base = Double(txn.amount) / (1 + Double(card?.forexMarkupBps ?? 0) / 10_000)
          LabeledContent("Rate", value: "1 \(c) = \(Money.symbol)\(String(format: "%.4f", base / Double(o)))")
          if let bps = card?.forexMarkupBps, bps > 0 {
            LabeledContent("Card markup", value: "\(Money.format(txn.amount - Int(base.rounded()))) (\(ForexMarkup.label(bps)))")
          }
          Button("Fix the Rate") { rateText = String(format: "%.4f", base / Double(o)); editingRate = true }
        } header: { Text("Foreign currency") } footer: {
          Text("The rate is locked to the day you spent. Fix it to match your card statement.")
        }
        .alert("\(Money.symbol) per 1 \(c)", isPresented: $editingRate) {
          TextField("Rate", text: $rateText).keyboardType(.decimalPad)
          Button("Save") {
            if let r = Double(rateText), r > 0 {
              let card = txn.cardId.flatMap { id in cards.first { $0.id == id } }
              txn.amount = max(1, ForexMarkup.apply(Fx.convert(o, rate: r), bps: card?.forexMarkupBps)); txn.updatedAt = .now
              try? context.save(); WidgetRefresh.now()
            }
          }
          Button("Cancel", role: .cancel) {}
        }
      }

      if let share = txn.splitShare {
        Section("Split") {
          LabeledContent("Your share") { Text(Money.format(share)) }
          ForEach(mySplits) { e in
            LabeledContent(friends.first { $0.id == e.friendId }?.name ?? "Friend") {
              Text(e.amount >= 0 ? "owes \(Money.format(e.amount))" : "paid, you owe \(Money.format(-e.amount))")
                .foregroundStyle(e.amount >= 0 ? Color.income : Color.expense)
            }
          }
        }
      }

      Section("Receipt") {
        if let img = Receipts.image(txn.receipt) {
          Button { showingReceipt = true } label: {
            Image(uiImage: img).resizable().scaledToFill().frame(height: 180).frame(maxWidth: .infinity).clipped()
              .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          }
          .buttonStyle(.pressable)
          Button("Remove Receipt", role: .destructive) { Receipts.delete(txn.receipt); txn.receipt = nil; try? context.save() }
        } else {
          PhotosPicker(selection: $photo, matching: .images) { Label("Add a Photo of the Receipt", systemImage: "doc.text.image") }
        }
      }

      Section {
        Button { router.add = AddRequest(type: txn.type, editing: txn) } label: { Label("Edit", systemImage: "pencil") }
        Button { templateName = txn.payee ?? ""; savingTemplate = true } label: { Label("Save as Template", systemImage: "bolt") }
        Button { TxnOps.duplicate(txn, context: context, router: router) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
        if txn.recurringId == nil {
          Button { repeatSheet = true } label: { Label("Repeat…", systemImage: "repeat") }
        }
        Button(role: .destructive) {
          TxnOps.delete(txn, context: context, router: router)
          dismiss()
        } label: { Label("Delete", systemImage: "trash") }
      }
    }
    .navigationTitle("")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Edit") { router.add = AddRequest(type: txn.type, editing: txn) }
      }
    }
    .sheet(isPresented: $repeatSheet) {
      NavigationStack { RecurringFormView(from: txn) }
    }
    .onChange(of: photo) { _, item in
      guard let item else { return }
      Task {
        if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data), let name = Receipts.save(img, for: txn.id) {
          Receipts.delete(txn.receipt)
          txn.receipt = name
          try? context.save()
        }
        photo = nil
      }
    }
    .fullScreenCover(isPresented: $showingReceipt) {
      ZStack(alignment: .topTrailing) {
        Color.black.ignoresSafeArea()
        if let img = Receipts.image(txn.receipt) { Image(uiImage: img).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity) }
        Button { showingReceipt = false } label: { Image(systemName: "xmark").font(.headline).padding(12) }
          .buttonStyle(.borderedProminent).tint(.gray).padding()
      }
    }
    .alert("Save as template", isPresented: $savingTemplate) {
      TextField("Name, e.g. Metro", text: $templateName)
      Button("Save") {
        let n = templateName.nilIfEmpty ?? lookups.title(txn)
        context.insert(TxnTemplate(name: n, type: txn.type, amount: txn.amount, accountId: txn.accountId, toAccountId: txn.toAccountId,
                                   categoryId: txn.categoryId, payee: txn.payee, sortOrder: Int(Date.now.timeIntervalSince1970)))
        try? context.save()
        router.show("Template saved")
      }
      Button("Cancel", role: .cancel) {}
    } message: { Text("It shows in Quick Add and on Home for one-tap adding.") }
  }
}
