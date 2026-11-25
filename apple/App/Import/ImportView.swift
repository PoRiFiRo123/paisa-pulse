import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Runs pdf.js (pdf-extractor.html, the same file the Android app uses) in a hidden web view.
/// PDFs are read on the phone; nothing is uploaded and the page can't reach the network.
@MainActor final class PdfExtractor: NSObject, WKNavigationDelegate {
  static let shared = PdfExtractor()
  private var web: WKWebView?
  private var ready = false
  private var waiting: [CheckedContinuation<Void, Never>] = []

  enum Failure: Error { case password, incorrectPassword, other(String) }

  private func load() async {
    if ready { return }
    if web == nil {
      let config = WKWebViewConfiguration()
      let w = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
      w.navigationDelegate = self
      web = w
      let url = Bundle.main.url(forResource: "pdf-extractor", withExtension: "html")!
      let html = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
      w.loadHTMLString(html, baseURL: URL(string: "https://paisapulse.local/"))
    }
    await withCheckedContinuation { waiting.append($0) }
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    ready = true
    waiting.forEach { $0.resume() }
    waiting = []
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
    let url = navigationAction.request.url?.absoluteString ?? ""
    return url.hasPrefix("https://paisapulse.local") || url.hasPrefix("about:") ? .allow : .cancel
  }

  func extract(_ data: Data, password: String?) async throws -> [TextItem] {
    await load()
    guard let web else { throw Failure.other("PDF reader didn't start") }
    let result = try await web.callAsyncJavaScript("return await window.extractPdf(b64, pw);",
                                                   arguments: ["b64": data.base64EncodedString(), "pw": password ?? ""],
                                                   in: nil, in: .page)
    guard let dict = result as? [String: Any] else { throw Failure.other("Couldn't read this PDF") }
    if dict["ok"] as? Bool == true, let items = dict["items"] as? [[String: Any]] {
      return items.compactMap { i in
        guard let str = i["str"] as? String else { return nil }
        func d(_ k: String) -> Double { (i[k] as? NSNumber)?.doubleValue ?? 0 }
        return TextItem(str: str, x: d("x"), y: d("y"), w: d("w"), h: d("h"), page: Int(d("page")))
      }
    }
    switch dict["error"] as? String {
    case "password": throw Failure.password
    case "incorrect-password": throw Failure.incorrectPassword
    case let e: throw Failure.other(e ?? "Couldn't read this PDF")
    }
  }
}

/// Settings › Import Statement: pick a bank or card statement (PDF, CSV, XLSX), check the columns, review, import as one batch.
struct ImportView: View {
  var accountId: String?
  @Query(sort: \Account.sortOrder) private var accounts: [Account]
  @Query(sort: \Category.sortOrder) private var categories: [Category]
  @Query(filter: #Predicate<Txn> { $0.deletedAt == nil }) private var txns: [Txn]
  @Query(sort: \ImportBatch.createdAt, order: .reverse) private var batches: [ImportBatch]
  @Environment(\.modelContext) private var context
  @Environment(Router.self) private var router
  @Environment(\.dismiss) private var dismiss

  @State private var picking = false
  @State private var busy = false
  @State private var error: String?
  @State private var pdf: (data: Data, name: String)?
  @State private var password = ""
  @State private var wrongPassword = false
  @State private var session: Session?

  struct Session {
    var fileName: String
    var sheet: Sheet
    var template: StatementTemplate?
    var mapping: Mapping
    var accountId: String
    var rows: [PlannedRow] = []
    var mismatches: Int?
  }

  private static let types: [UTType] = [.pdf, .commaSeparatedText, .plainText, .spreadsheet, .html, .data]
    + ["xlsx", "xls", "csv"].compactMap { UTType(filenameExtension: $0) }

  var body: some View {
    Group {
      if let s = session { review(s) } else { startView }
    }
    .navigationTitle(session == nil ? "Import Statement" : session!.template?.name ?? "Review")
    .navigationBarTitleDisplayMode(session == nil ? .large : .inline)
    .fileImporter(isPresented: $picking, allowedContentTypes: Self.types) { result in
      if case .success(let url) = result { open(url) }
    }
    .alert("Password-protected PDF", isPresented: Binding(get: { pdf != nil }, set: { if !$0 { pdf = nil } })) {
      SecureField("Password", text: $password)
      Button("Cancel", role: .cancel) { password = "" }
      Button("Open") { if let p = pdf { Task { await readPdf(p.data, name: p.name, password: password) } } }
    } message: {
      Text(wrongPassword ? "That password didn't work. Banks often use your date of birth or customer ID." :
            "Banks usually lock statements with your date of birth or customer ID.")
    }
    .alert("Can't import this file", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
      Button("OK", role: .cancel) {}
    } message: { Text(error ?? "") }
  }

  private var startView: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 10) {
          Image(systemName: "doc.text.viewfinder").font(.system(size: 40)).foregroundStyle(Color.accentColor)
          Text("Bring in a bank or card statement").font(.headline)
          Text("PDF, CSV or Excel from Axis, Bank of Baroda, HDFC, ICICI, SBI and most others. Read on this phone; nothing is uploaded.")
            .font(.subheadline).foregroundStyle(.secondary)
          Button { picking = true } label: {
            Label(busy ? "Reading…" : "Choose File", systemImage: "folder").frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent).controlSize(.large).disabled(busy)
        }
        .padding(.vertical, 6)
      }
      if !batches.isEmpty {
        Section("Recent imports") {
          ForEach(batches.prefix(20)) { b in
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(b.fileName).lineLimit(1)
                Text("\(b.count) transactions · \(accounts.first { $0.id == b.accountId }?.name ?? "Account") · \(b.createdAt.formatted(date: .abbreviated, time: .omitted))")
                  .font(.footnote).foregroundStyle(.secondary)
              }
              Spacer()
              if b.undoneAt == nil {
                Button("Undo") { undo(b) }.buttonStyle(.bordered).controlSize(.small).tint(.red)
              } else {
                Button("Restore") { restore(b) }.buttonStyle(.bordered).controlSize(.small)
              }
            }
          }
        }
      }
    }
  }

  // MARK: Review

  private func review(_ s: Session) -> some View {
    let lookups = Lookups(accounts: accounts, categories: categories)
    let chosen = s.rows.filter(\.include)
    let out = chosen.filter { $0.row.out }.reduce(0) { $0 + $1.row.amount }
    let inn = chosen.filter { !$0.row.out }.reduce(0) { $0 + $1.row.amount }
    return List {
      Section {
        Picker("Account", selection: Binding(get: { s.accountId }, set: { id in update { $0.accountId = id } })) {
          ForEach(accounts.filter { $0.archivedAt == nil }) { Text($0.name).tag($0.id) }
        }
        DisclosureGroup("Columns") {
          ForEach(Array(s.mapping.columns.enumerated()), id: \.offset) { i, role in
            let header = s.mapping.headerRow < s.sheet.count && i < s.sheet[s.mapping.headerRow].count ? s.sheet[s.mapping.headerRow][i] : "Column \(i + 1)"
            Picker(header.isEmpty ? "Column \(i + 1)" : header, selection: Binding(get: { role }, set: { r in update { $0.mapping.columns[i] = r } })) {
              ForEach(ColumnRole.allCases) { Text($0.label).tag($0) }
            }
          }
          Picker("Dates", selection: Binding(get: { s.mapping.dateOrder }, set: { o in update { $0.mapping.dateOrder = o } })) {
            Text("Day first (31/12)").tag(DateOrder.dmy); Text("Month first (12/31)").tag(DateOrder.mdy)
          }
          if s.mapping.columns.contains(.amount) && !s.mapping.columns.contains(.debit) {
            Picker("A positive amount is", selection: Binding(get: { s.mapping.positiveIsIn }, set: { v in update { $0.mapping.positiveIsIn = v } })) {
              Text("Money in").tag(true); Text("Money out").tag(false)
            }
          }
        }
      } footer: {
        if let m = s.mismatches, m > 0 {
          Text("\(m) rows don't match the running balance. Check the columns.").foregroundStyle(Color.expense)
        } else {
          Text("\(s.rows.count) transactions found\(s.mismatches == 0 ? ", balances check out" : "").")
        }
      }

      Section {
        HStack(spacing: 0) {
          SummaryCell(label: "Out", value: out, color: .expense)
          SummaryCell(label: "In", value: inn, color: .income)
        }
      }

      Section {
        ForEach(s.rows) { p in row(p, lookups) }
      } header: {
        HStack {
          Text("\(chosen.count) of \(s.rows.count) selected")
          Spacer()
          Button(chosen.count == s.rows.count ? "None" : "All") {
            let all = chosen.count != s.rows.count
            update(replan: false) { for i in $0.rows.indices { $0.rows[i].include = all } }
          }
          .font(.subheadline).textCase(nil)
        }
      }
    }
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("Back") { session = nil } }
      ToolbarItem(placement: .confirmationAction) {
        Button("Import \(chosen.count)") { commit(s) }.fontWeight(.semibold).disabled(chosen.isEmpty)
      }
    }
  }

  private func row(_ p: PlannedRow, _ lookups: Lookups) -> some View {
    let binding = Binding<PlannedRow>(
      get: { session?.rows.first { $0.key == p.key } ?? p },
      set: { new in update(replan: false) { s in if let i = s.rows.firstIndex(where: { $0.key == p.key }) { s.rows[i] = new } } }
    )
    let c = p.categoryId.flatMap { lookups.categories[$0] }
    return HStack(alignment: .top, spacing: 12) {
      Button { binding.wrappedValue.include.toggle() } label: {
        Image(systemName: p.include ? "checkmark.circle.fill" : "circle").font(.title3)
          .foregroundStyle(p.include ? Color.accentColor : Color.secondary)
      }
      .buttonStyle(.pressable)
      .accessibilityLabel(p.include ? "Included" : "Skipped")
      VStack(alignment: .leading, spacing: 3) {
        HStack {
          Text(p.payee ?? "Unknown").lineLimit(1)
          Spacer()
          AmountText(amount: p.row.amount, type: p.type == .transfer ? .transfer : p.row.out ? .expense : .income)
        }
        Text(p.row.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        HStack(spacing: 8) {
          Text(p.row.date.formatted(.dateTime.day().month(.abbreviated))).font(.caption).foregroundStyle(.secondary)
          if p.type == .transfer {
            Menu {
              ForEach(accounts.filter { $0.archivedAt == nil && $0.id != session?.accountId }) { a in
                Button(a.name) { binding.wrappedValue.otherAccountId = a.id }
              }
              Divider()
              Button("Not a transfer") { binding.wrappedValue.type = p.row.out ? .expense : .income; binding.wrappedValue.otherAccountId = nil }
            } label: {
              Label(p.otherAccountId.flatMap { lookups.accounts[$0]?.name } ?? "Pick account", systemImage: "arrow.left.arrow.right")
                .font(.caption.weight(.medium))
            }
          } else {
            Menu {
              Button("Uncategorised") { binding.wrappedValue.categoryId = nil }
              ForEach(categories.filter { $0.archivedAt == nil && $0.kind == (p.row.out ? .expense : .income) }) { cat in
                Button { binding.wrappedValue.categoryId = cat.id } label: { Label(cat.name, systemImage: cat.icon) }
              }
              Divider()
              Menu("Make it a transfer") {
                ForEach(accounts.filter { $0.archivedAt == nil && $0.id != session?.accountId }) { a in
                  Button(a.name) { binding.wrappedValue.type = .transfer; binding.wrappedValue.otherAccountId = a.id }
                }
              }
            } label: {
              Label(c?.name ?? "Uncategorised", systemImage: c?.icon ?? "questionmark.circle").font(.caption.weight(.medium))
            }
          }
        }
        if let hint = p.hint {
          Label(hint, systemImage: p.status == "new" ? "info.circle" : "exclamationmark.triangle.fill")
            .font(.caption).foregroundStyle(p.status == "new" ? Color.secondary : Color.orange)
        }
      }
    }
    .opacity(p.include ? 1 : 0.6)
    .padding(.vertical, 2)
  }

  // MARK: Actions

  private func update(replan: Bool = true, _ change: (inout Session) -> Void) {
    guard var s = session else { return }
    change(&s)
    if replan { s = plan(s) }
    session = s
  }

  private func plan(_ s: Session) -> Session {
    var s = s
    let rows = StatementParser.extractRows(s.sheet, s.mapping)
    s.mismatches = StatementParser.balanceMismatches(rows)
    s.rows = ImportPlan.plan(accountId: s.accountId, rows: rows, accounts: accounts, categories: categories, txns: Array(txns))
    return s
  }

  private func open(_ url: URL) {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard let data = try? Data(contentsOf: url) else { error = "Couldn't open the file."; return }
    let name = url.lastPathComponent
    switch StatementReaders.detect(data) {
    case .pdf: Task { await readPdf(data, name: name, password: nil) }
    case .xlsx: begin(StatementReaders.xlsx(data), name: name)
    case .html: begin(StatementReaders.html(StatementReaders.text(data)), name: name)
    case .csv: begin(StatementReaders.csv(StatementReaders.text(data)), name: name)
    case .xlsBinary: error = "Old Excel (.xls) files aren't supported. Download the statement as PDF, CSV or XLSX instead."
    case .unknown: error = "This doesn't look like a statement. Try the PDF, CSV or Excel download from your bank."
    }
  }

  private func readPdf(_ data: Data, name: String, password: String?) async {
    busy = true
    defer { busy = false }
    do {
      let items = try await PdfExtractor.shared.extract(data, password: password)
      self.password = ""; wrongPassword = false
      begin(PdfLayout.toSheet(items), name: name)
    } catch PdfExtractor.Failure.password {
      wrongPassword = false; pdf = (data, name)
    } catch PdfExtractor.Failure.incorrectPassword {
      wrongPassword = true; pdf = (data, name)
    } catch {
      self.error = "Couldn't read this PDF. Try the CSV or Excel download."
    }
  }

  private func begin(_ sheet: Sheet, name: String) {
    let template = StatementParser.detectTemplate(sheet)
    let preset = accountId.flatMap { id in accounts.first { $0.id == id } }
    guard let account = preset ?? StatementParser.guessAccount(Array(accounts), template) else { error = "Add an account first."; return }
    guard let mapping = StatementParser.detectMapping(sheet, template: template, cardAccount: account.type == .card) else {
      error = "Couldn't find the transactions table in this file. Try another format (PDF, CSV or Excel)."
      return
    }
    session = plan(Session(fileName: name, sheet: sheet, template: template, mapping: mapping, accountId: account.id))
  }

  private func commit(_ s: Session) {
    let batch = ImportPlan.commit(accountId: s.accountId, fileName: s.fileName, template: s.template?.id, rows: s.rows, context: context)
    WidgetRefresh.now()
    session = nil
    router.show("Imported \(batch.count)") { undo(batch) }
  }

  private func undo(_ b: ImportBatch) {
    let now = Date.now
    let id: String? = b.id
    let list = ((try? context.fetch(FetchDescriptor<Txn>(predicate: #Predicate { $0.importBatchId == id }))) ?? []).filter { $0.deletedAt == nil }
    list.forEach { $0.deletedAt = now; $0.updatedAt = now }
    b.undoneAt = now
    try? context.save()
    WidgetRefresh.now()
  }

  private func restore(_ b: ImportBatch) {
    guard let undone = b.undoneAt else { return }
    let id: String? = b.id
    let list = (try? context.fetch(FetchDescriptor<Txn>(predicate: #Predicate { $0.importBatchId == id }))) ?? []
    for t in list where t.deletedAt.map({ abs($0.timeIntervalSince(undone)) < 1 }) == true { t.deletedAt = nil; t.updatedAt = .now }
    b.undoneAt = nil
    try? context.save()
    WidgetRefresh.now()
  }
}
