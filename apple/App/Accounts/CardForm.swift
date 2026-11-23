import SwiftData
import SwiftUI
import VisionKit

/// Add or edit a debit/credit card linked to an account. Scan with the camera or type it in.
/// Stores the network, last 4 digits and expiry only.
struct CardFormView: View {
  let card: PaymentCard?
  let account: Account
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @State private var network = "visa"
  @State private var last4 = ""
  @State private var month = 0
  @State private var year = 0
  @State private var name = ""
  @State private var label = ""
  @State private var color = ""
  @State private var scanning = false
  /// Forex markup: off, or a percent with/without 18% GST on top.
  @State private var markupOn = false
  @State private var markupPercent = 3.5
  @State private var markupGst = true

  private var kind: String { account.type == .card ? "credit" : "debit" }
  private var valid: Bool { last4.count == 4 && last4.allSatisfy(\.isNumber) }
  private var preview: PaymentCard {
    PaymentCard(accountId: account.id, kind: kind, network: network, last4: last4.isEmpty ? "0000" : last4,
                expiryMonth: month > 0 ? month : nil, expiryYear: year > 0 ? year : nil, nameOnCard: name.isEmpty ? nil : name.uppercased(),
                label: label.isEmpty ? nil : label, color: color.isEmpty ? nil : color)
  }

  var body: some View {
    Form {
      Section {
        PaymentCardFace(card: preview, accountColor: account.color)
          .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
          .animation(.spring, value: network)
      }
      Section {
        Button { scanning = true } label: { Label("Scan with Camera", systemImage: "camera.viewfinder") }
          .disabled(!(DataScannerViewController.isSupported && DataScannerViewController.isAvailable))
      } footer: {
        Text(DataScannerViewController.isSupported ? "Hold the card in view. The full number is read once to check it, then only the last 4 digits are kept." : "This iPhone can't scan text with the camera. Type the details instead.")
      }
      Section("Card") {
        Picker("Network", selection: $network) { ForEach(CardNumber.networks, id: \.self) { Text(CardNumber.networkName($0)).tag($0) } }
        TextField("Last 4 digits", text: $last4).keyboardType(.numberPad)
          .onChange(of: last4) { _, v in last4 = String(v.filter(\.isNumber).prefix(4)) }
        Picker("Expiry month", selection: $month) { Text("Not set").tag(0); ForEach(1...12, id: \.self) { Text(String(format: "%02d", $0)).tag($0) } }
        Picker("Expiry year", selection: $year) {
          Text("Not set").tag(0)
          ForEach(Calendar.current.component(.year, from: .now)...(Calendar.current.component(.year, from: .now) + 12), id: \.self) { Text(String($0)).tag($0) }
        }
        TextField("Name on card (optional)", text: $name).textInputAutocapitalization(.characters)
        TextField("Nickname (optional), e.g. MyZone Debit", text: $label)
      }
      Section {
        Toggle("Foreign currency markup", isOn: $markupOn)
        if markupOn {
          Stepper(value: $markupPercent, in: 0...10, step: 0.25) {
            LabeledContent("Markup", value: String(format: "%.2f%%", markupPercent))
          }
          Toggle("Plus 18% GST on the markup", isOn: $markupGst)
          LabeledContent("You pay extra", value: ForexMarkup.label(ForexMarkup.bps(percent: markupPercent, withGst: markupGst)))
        }
      } header: { Text("Spending abroad") } footer: {
        Text("Most Indian cards add 2–3.5% plus GST on foreign spends. It's added automatically when you pay in another currency with this card. Check your card's fee page and edit it any time.")
      }
      Section("Colour") {
        ColorRow(selection: $color)
        if !color.isEmpty { Button("Use the account's colour") { color = "" } }
      }
      if let card {
        Section {
          Button("Remove Card", role: .destructive) { card.archivedAt = .now; try? context.save(); dismiss() }
        }
      }
    }
    .navigationTitle(card == nil ? (kind == "credit" ? "Card Details" : "Add Debit Card") : "Edit Card")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!valid) }
    }
    .sheet(isPresented: $scanning) {
      CardScannerView { scan in
        network = scan.network; last4 = scan.last4
        if let m = scan.month { month = m }; if let y = scan.year { year = y }
        if let n = scan.name { name = n }
        scanning = false
      }
      .ignoresSafeArea()
    }
    .onAppear {
      guard let c = card else { return }
      network = c.network; last4 = c.last4; month = c.expiryMonth ?? 0; year = c.expiryYear ?? 0
      name = c.nameOnCard ?? ""; label = c.label ?? ""; color = c.color ?? ""
      if let bps = c.forexMarkupBps, bps > 0 {
        markupOn = true
        // Shown as "3.5% + GST" when it divides evenly, else the plain percent.
        let base = Double(bps) / 118
        if abs(base * 1.18 * 100 - Double(bps) * 100 / 100) < 0.5, (base * 4).rounded() == base * 4 { markupPercent = base; markupGst = true }
        else { markupPercent = Double(bps) / 100; markupGst = false }
      }
    }
  }

  private func save() {
    let c = card ?? PaymentCard(accountId: account.id, kind: kind, last4: last4)
    c.network = network; c.last4 = last4; c.kind = kind
    c.expiryMonth = month > 0 ? month : nil; c.expiryYear = year > 0 ? year : nil
    c.nameOnCard = name.isEmpty ? nil : name.uppercased(); c.label = label.isEmpty ? nil : label; c.color = color.isEmpty ? nil : color
    c.forexMarkupBps = markupOn ? ForexMarkup.bps(percent: markupPercent, withGst: markupGst) : nil
    if card == nil { context.insert(c) }
    if account.type == .card, account.last4 == nil { account.last4 = last4 }
    try? context.save()
    dismiss()
  }
}

/// Live camera text scanner (VisionKit). Calls back once a valid card number is seen.
struct CardScannerView: UIViewControllerRepresentable {
  let onFound: (CardNumber.Scan) -> Void

  func makeUIViewController(context: Context) -> DataScannerViewController {
    let vc = DataScannerViewController(recognizedDataTypes: [.text()], qualityLevel: .accurate,
                                       recognizesMultipleItems: true, isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true)
    vc.delegate = context.coordinator
    try? vc.startScanning()
    return vc
  }
  func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}
  func makeCoordinator() -> Coordinator { Coordinator(onFound) }

  final class Coordinator: NSObject, DataScannerViewControllerDelegate {
    let onFound: (CardNumber.Scan) -> Void
    private var done = false
    init(_ f: @escaping (CardNumber.Scan) -> Void) { onFound = f }

    private func check(_ items: [RecognizedItem]) {
      guard !done else { return }
      let lines = items.compactMap { if case .text(let t) = $0 { return t.transcript } else { return nil } }
      if let scan = CardNumber.parse(lines) {
        done = true
        DispatchQueue.main.async { self.onFound(scan) }
      }
    }
    func dataScanner(_ s: DataScannerViewController, didAdd added: [RecognizedItem], allItems: [RecognizedItem]) { check(allItems) }
    func dataScanner(_ s: DataScannerViewController, didUpdate updated: [RecognizedItem], allItems: [RecognizedItem]) { check(allItems) }
  }
}
