import SwiftData
import SwiftUI

// Currency picker, bank picker, multi-currency converter, main currency, and the Insights
// sections for payment methods and spending abroad. Same screens on Android (ui/screens/MoneyScreens.kt).

/// Searchable list of every currency, main currency and common ones first.
struct CurrencyPickerSheet: View {
  var title = "Currency"
  var exclude: Set<String> = []
  let onPick: (String) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""

  var body: some View {
    let q = query.lowercased()
    NavigationStack {
      List {
        let popular = ["INR", "USD", "EUR", "GBP", "AED", "SGD", "THB"].filter { !exclude.contains($0) }
        if q.isEmpty, !popular.isEmpty {
          Section("Popular") { ForEach(popular, id: \.self) { row($0) } }
        }
        Section(q.isEmpty ? "All currencies" : "Results") {
          ForEach(matches(q).filter { !exclude.contains($0) }, id: \.self) { row($0) }
        }
      }
      .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Currency or country")
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }
    .presentationDetents([.medium, .large])
  }

  /// Codes whose code, name or any country using them matches the search.
  private func matches(_ q: String) -> [String] {
    World.currencies.map(\.code).filter { code in
      q.isEmpty || code.lowercased().contains(q) || World.currencyName(code).lowercased().contains(q)
        || World.countries.contains { $0.currency == code && $0.name.lowercased().contains(q) }
    }
  }

  private func row(_ code: String) -> some View {
    Button {
      onPick(code); dismiss()
    } label: {
      HStack(spacing: 12) {
        Text(World.symbol(code)).font(.headline).fontDesign(.rounded).frame(width: 44, alignment: .leading).foregroundStyle(Color.accentColor)
        VStack(alignment: .leading, spacing: 1) {
          Text(World.currencyName(code)).foregroundStyle(.primary)
          Text(([code] + World.countries.filter { $0.currency == code }.prefix(3).map(\.name)).joined(separator: " · "))
            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        Spacer()
        if code == Money.base { Text("Main").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
      }
    }
  }
}

/// Indian banks (or wallets) with their colours; popular ones first, search, or type your own.
struct BankPickerView: View {
  let wallets: Bool
  @Binding var selection: String
  var onPick: (Banks.Bank) -> Void = { _ in }
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""

  var body: some View {
    let q = query.lowercased()
    let list = Banks.all.filter { wallets ? $0.kind == "wallet" : $0.kind != "wallet" }
    let found = list.filter { q.isEmpty || $0.short.lowercased().contains(q) || $0.name.lowercased().contains(q) }
    List {
      if q.isEmpty && !wallets {
        Section("Popular") { ForEach(Banks.popular.compactMap(Banks.byId), id: \.id) { row($0) } }
      }
      Section(q.isEmpty ? (wallets ? "Wallets" : "All banks") : "Results") {
        ForEach(found.filter { q.isEmpty && !wallets ? !Banks.popular.contains($0.id) : true }) { row($0) }
        if !query.trimmingCharacters(in: .whitespaces).isEmpty && !list.contains(where: { $0.short.lowercased() == q || $0.name.lowercased() == q }) {
          Button { selection = query.trimmingCharacters(in: .whitespaces); dismiss() } label: { Label("Use \"\(query)\"", systemImage: "plus.circle") }
        }
      }
    }
    .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: wallets ? "Search wallets" : "Search banks")
    .navigationTitle(wallets ? "Wallet" : "Bank")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func row(_ b: Banks.Bank) -> some View {
    Button {
      selection = b.short; onPick(b); dismiss()
    } label: {
      HStack(spacing: 12) {
        Text(String(b.short.prefix(1))).font(.headline).foregroundStyle(.white)
          .frame(width: 34, height: 34).background(Color(hex: b.color), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        VStack(alignment: .leading, spacing: 1) {
          Text(b.short).foregroundStyle(.primary)
          if b.name != b.short { Text(b.name).font(.caption).foregroundStyle(.secondary) }
        }
        Spacer()
        if Banks.match(selection)?.id == b.id { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
      }
    }
  }
}

/// Compare one amount across many currencies at once. Tap a row to type in that currency.
struct ConverterView: View {
  @AppStorage(PrefKey.converterCurrencies, store: AppGroup.defaults) private var saved = "USD,EUR,GBP,AED"
  @State private var codes: [String] = []
  @State private var active = Money.base
  @State private var amount = "100"
  @State private var rates: Currency.Rates? = Currency.cached
  @State private var loading = false
  @State private var adding = false
  @FocusState private var focused: Bool

  var body: some View {
    let value = Double(amount.replacingOccurrences(of: ",", with: "")) ?? 0
    List {
      Section {
        ForEach(codes, id: \.self) { code in
          let r = rates.flatMap { Fx.rate(from: active, to: code, inrPer: $0.inrPer) }
          let isActive = code == active
          HStack(spacing: 12) {
            Text(World.symbol(code)).font(.headline).fontDesign(.rounded).frame(width: 40, alignment: .leading)
              .foregroundStyle(isActive ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 1) {
              Text(code).font(.subheadline.weight(.semibold))
              Text(World.currencyName(code)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if isActive {
              TextField("0", text: $amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .font(.title2.weight(.bold)).fontDesign(.rounded).focused($focused).frame(maxWidth: 170)
            } else {
              VStack(alignment: .trailing, spacing: 1) {
                Text(r.map { Money.format(Int((value * $0 * 100).rounded()), code: code) } ?? "—").font(.title3.weight(.semibold)).fontDesign(.rounded)
                if let one = rates.flatMap({ Fx.rate(from: code, to: active, inrPer: $0.inrPer) }) {
                  Text("1 \(code) = \(World.symbol(active))\(String(format: one < 1 ? "%.4f" : "%.2f", one))").font(.caption2).foregroundStyle(.secondary)
                }
              }
            }
          }
          .contentShape(Rectangle())
          .onTapGesture {
            guard !isActive else { focused = true; return }
            if let r { amount = String(format: "%.2f", value * r).replacingOccurrences(of: ".00", with: "") }
            withAnimation(.quick) { active = code }
            focused = true
          }
          .listRowBackground(isActive ? Color.accentColor.opacity(0.08) : Color(.secondarySystemGroupedBackground))
        }
        .onMove { codes.move(fromOffsets: $0, toOffset: $1); persist(); Haptic.soft() }
        .onDelete { idx in
          let removed = idx.map { codes[$0] }
          codes.remove(atOffsets: idx)
          if removed.contains(active) { active = codes.first ?? Money.base }
          persist()
        }
        Button { adding = true } label: { Label("Add Currency", systemImage: "plus.circle.fill") }
      } footer: {
        Text("Tap a currency to type in it. Swipe to remove, Edit to reorder.")
      }
      Section {
        Button(loading ? "Refreshing…" : "Refresh Rates") { Task { loading = true; rates = await Currency.rates(force: true); loading = false } }.disabled(loading)
      } footer: {
        Text(rates.map { "Mid-market rates from open.er-api.com, updated \(Date(timeIntervalSince1970: $0.at).formatted(.relative(presentation: .named))). Banks and forex cards add a markup." }
             ?? "Rates need an internet connection the first time. Only currency codes are requested.")
      }
    }
    .navigationTitle("Converter")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) { EditButton() }
      ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } }
    }
    .sheet(isPresented: $adding) { CurrencyPickerSheet(title: "Add Currency", exclude: Set(codes)) { codes.append($0); persist() } }
    .onAppear {
      if codes.isEmpty {
        codes = [Money.base] + saved.split(separator: ",").map(String.init).filter { !$0.isEmpty && $0 != Money.base }
        active = Money.base
      }
    }
    .task { if rates == nil || Date.now.timeIntervalSince1970 - (rates?.at ?? 0) > Currency.maxAge { rates = await Currency.rates() } }
  }

  private func persist() { saved = codes.filter { $0 != Money.base }.joined(separator: ",") }
}

/// Settings › Main Currency: every amount is stored in it. Changing it converts at today's rate, or just relabels.
struct MainCurrencyView: View {
  @Environment(\.modelContext) private var context
  @Environment(Router.self) private var router
  @AppStorage(PrefKey.baseCurrency, store: AppGroup.defaults) private var base = "INR"
  @State private var picking = false
  @State private var pending: String?
  @State private var rate: Double?
  @State private var working = false

  var body: some View {
    List {
      Section {
        Button { picking = true } label: {
          HStack(spacing: 12) {
            Text(World.symbol(base)).font(.title2.weight(.bold)).fontDesign(.rounded).frame(width: 52, alignment: .leading)
            VStack(alignment: .leading) {
              Text(World.currencyName(base)).foregroundStyle(.primary)
              Text(base).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
          }
        }
      } footer: {
        Text("Totals, budgets and net worth are shown in this currency. Spends in other currencies keep their original amount too. ₹ uses lakh and crore; other currencies use thousands.")
      }
      if working { Section("Converting…") { SkeletonRows(count: 3) } }
    }
    .navigationTitle("Main Currency")
    .sheet(isPresented: $picking) {
      CurrencyPickerSheet(title: "Main Currency", exclude: [base]) { code in
        pending = code
        Task { rate = await Currency.rates().flatMap { Fx.rate(from: base, to: code, inrPer: $0.inrPer) } }
      }
    }
    .confirmationDialog("Change to \(pending ?? "")?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
      if let code = pending, let r = rate {
        Button("Convert Everything (1 \(base) = \(World.symbol(code))\(String(format: r < 1 ? "%.4f" : "%.2f", r)))") { change(to: code, rate: r) }
      }
      if let code = pending { Button("Just Change the Symbol") { change(to: code, rate: 1) } }
      Button("Cancel", role: .cancel) { pending = nil }
    } message: {
      Text(rate == nil ? "Rates aren't loaded (offline?), so amounts can only keep their numbers." : "Convert every amount at today's rate, or keep the numbers as they are (if you entered them in the new currency already). A backup is saved first.")
    }
  }

  private func change(to code: String, rate r: Double) {
    working = true
    do {
      try AutoBackup.write(context)
      let data = try BackupCodec.export(context)
      let converted = try BaseCurrencyChange.convert(data, rate: r, newCode: code)
      try BackupCodec.restore(try BackupCodec.decode(converted), into: context)
      base = code
      try context.save()
      WidgetRefresh.now()
      router.show("Main currency is now \(code)")
    } catch {
      router.show("Couldn't change the currency: \(error.localizedDescription)")
    }
    working = false; pending = nil
  }
}

/// Converts every stored amount in a backup at one rate (same fields as Android's BaseCurrency.convert).
enum BaseCurrencyChange {
  static func convert(_ data: Data, rate: Double, newCode: String) throws -> Data {
    guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw BackupError.notBackup }
    func c(_ v: Any?) -> Any? { (v as? NSNumber).map { NSNumber(value: Int((Double(truncating: $0) * rate).rounded())) } ?? v }
    func map(_ key: String, _ f: (inout [String: Any]) -> Void) {
      guard let list = root[key] as? [[String: Any]] else { return }
      root[key] = list.map { var o = $0; f(&o); return o }
    }
    func fields(_ key: String, _ names: [String], min1: Bool = false) {
      map(key) { o in for n in names where o[n] is NSNumber { let v = c(o[n]) as? NSNumber; o[n] = min1 ? NSNumber(value: max(1, v?.intValue ?? 1)) : v } }
    }
    fields("accounts", ["openingBalance", "creditLimit"])
    map("transactions") { o in
      if o["currency"] as? String == newCode, let orig = o["originalAmount"] as? NSNumber {
        o["amount"] = orig; o["currency"] = NSNull(); o["originalAmount"] = NSNull()
      } else if let a = o["amount"] as? NSNumber {
        o["amount"] = NSNumber(value: max(1, Int((Double(truncating: a) * rate).rounded())))
      }
    }
    fields("txnSplitShares", ["share"])
    fields("recurringRules", ["amount"], min1: true)
    fields("budgets", ["amount"])
    fields("splitEntries", ["amount"])
    fields("loans", ["amount"]); fields("loanPayments", ["amount"])
    fields("goals", ["target", "saved"])
    fields("templates", ["amount"], min1: true)
    fields("valuations", ["value"])
    fields("tripItems", ["budget"])
    map("tripWallets") { o in
      if o["currency"] == nil || o["currency"] is NSNull { o["amount"] = c(o["amount"]) }
      else if let r = o["rate"] as? NSNumber { o["rate"] = NSNumber(value: Double(truncating: r) * rate) }
    }
    return try JSONSerialization.data(withJSONObject: root)
  }
}

/// Insights: how you paid, for the period.
struct PaymentMethodSection: View {
  let txns: [Txn]
  var body: some View {
    let spent = txns.filter { $0.type == .expense }
    let groups = Dictionary(grouping: spent, by: { PaymentMethod(rawValue: $0.paymentMethod ?? "") })
      .map { (method: $0.key, total: $0.value.reduce(0) { $0 + $1.effectiveAmount }, count: $0.value.count) }
      .sorted { $0.total > $1.total }
    let all = max(1, groups.reduce(0) { $0 + $1.total })
    if groups.contains(where: { $0.method != nil }) {
      Section("How you paid") {
        ForEach(groups, id: \.method?.rawValue) { g in
          VStack(alignment: .leading, spacing: 6) {
            HStack {
              Label(g.method?.label ?? "Not set", systemImage: g.method?.icon ?? "questionmark.circle")
              Spacer()
              Text(Money.format(g.total)).fontDesign(.rounded)
            }
            ProgressView(value: Double(g.total), total: Double(all)).tint(g.method == nil ? .secondary : .accentColor)
            Text("\(g.count) payments · \(Int((Double(g.total) / Double(all) * 100).rounded()))%").font(.caption).foregroundStyle(.secondary)
          }
          .padding(.vertical, 2)
        }
      }
    }
  }
}

/// Insights: spending in other currencies, in both the foreign amount and the main currency.
struct SpentAbroadSection: View {
  let txns: [Txn]
  var body: some View {
    let foreign = txns.filter { $0.type == .expense && $0.currency != nil && $0.originalAmount != nil }
    let groups = Dictionary(grouping: foreign, by: { $0.currency ?? "" })
      .map { (code: $0.key, original: $0.value.reduce(0) { $0 + ($1.originalAmount ?? 0) }, base: $0.value.reduce(0) { $0 + $1.effectiveAmount }, count: $0.value.count) }
      .sorted { $0.base > $1.base }
    if !groups.isEmpty {
      Section {
        ForEach(groups, id: \.code) { g in
          HStack {
            Text(World.symbol(g.code)).font(.headline).fontDesign(.rounded).frame(width: 40, alignment: .leading).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
              Text(Money.format(g.original, code: g.code)).fontDesign(.rounded).fontWeight(.semibold)
              Text("\(g.count) spends · \(World.currencyName(g.code))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.format(g.base)).fontDesign(.rounded).foregroundStyle(Color.expense)
          }
        }
      } header: { Text("Spent abroad") } footer: {
        Text("In \(Money.base), as charged (including card markup).")
      }
    }
  }
}

// MARK: - Appearance

/// Accent colour: presets or any colour from the wheel.
struct AppearanceColorsView: View {
  @AppStorage(PrefKey.accent, store: AppGroup.defaults) private var accent = "indigo"
  @AppStorage(PrefKey.customAccent, store: AppGroup.defaults) private var customHex = "#5E5CE6"

  var body: some View {
    List {
      Section {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 18) {
          ForEach(Palette.accents, id: \.key) { a in
            swatch(Color.dynamic(light: a.light, dark: a.dark), name: a.name, on: accent == a.key) { accent = a.key }
          }
          swatch(Color(hex: customHex), name: "Custom", on: accent == "custom") { accent = "custom" }
        }
        .padding(.vertical, 10)
      } header: { Text("Accent colour") }
      Section {
        ColorPicker(selection: Binding(get: { Color(hex: customHex) }, set: { customHex = $0.hexString; accent = "custom" }), supportsOpacity: false) {
          Label("Pick Any Colour", systemImage: "eyedropper.halffull")
        }
      } footer: { Text("Buttons, links, the + button and highlights use this colour. Very light colours can be hard to read on white.") }
      Section("Preview") {
        HStack(spacing: 12) {
          Image(systemName: "plus").font(.headline).foregroundStyle(.white).frame(width: 44, height: 44).background(Color.accentColor, in: Circle())
          Text("Save").font(.headline).padding(.vertical, 10).padding(.horizontal, 20).background(Color.accentColor, in: Capsule()).foregroundStyle(.white)
          Text("Link").foregroundStyle(Color.accentColor)
          Spacer()
          Toggle("", isOn: .constant(true)).labelsHidden()
        }
      }
    }
    .navigationTitle("Accent Colour")
  }

  private func swatch(_ c: Color, name: String, on: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      VStack(spacing: 6) {
        Circle().fill(c).frame(width: 44, height: 44)
          .overlay(Circle().strokeBorder(.background, lineWidth: 3).padding(3).opacity(on ? 1 : 0))
          .overlay(Circle().strokeBorder(c, lineWidth: 2).padding(-3).opacity(on ? 1 : 0))
        Text(name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
      }
    }
    .buttonStyle(.pressable)
    .accessibilityLabel(name)
    .accessibilityAddTraits(on ? .isSelected : [])
  }
}

/// App icon picker with real previews of each icon.
struct AppIconPickerView: View {
  @State private var current = AppIcons.current
  var body: some View {
    ScrollView {
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 22) {
        ForEach(AppIcons.all, id: \.key) { i in
          Button {
            AppIcons.set(i.key); current = i.key
          } label: {
            VStack(spacing: 8) {
              Image(AppIcons.preview(i.key)).resizable().aspectRatio(1, contentMode: .fit).frame(maxWidth: 86)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 3).padding(-5).opacity(current == i.key ? 1 : 0))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
              Text(i.name).font(.subheadline.weight(current == i.key ? .semibold : .regular)).foregroundStyle(.primary)
            }
          }
          .buttonStyle(.pressable)
          .accessibilityAddTraits(current == i.key ? .isSelected : [])
        }
      }
      .padding(20)
      Text("iPhone asks to confirm the change. Home screen icons must be built into the app, so they come in these colours; the accent colour can be anything.")
        .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 20)
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle("App Icon")
  }
}

extension Color {
  /// "#RRGGBB" of this colour (sRGB).
  var hexString: String {
    let ui = UIColor(self)
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    ui.getRed(&r, green: &g, blue: &b, alpha: &a)
    return String(format: "#%02X%02X%02X", Int((max(0, min(1, r)) * 255).rounded()), Int((max(0, min(1, g)) * 255).rounded()), Int((max(0, min(1, b)) * 255).rounded()))
  }
}
