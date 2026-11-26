import UIKit

/// The monthly report as an A4 PDF: totals, every category against last month, the biggest expenses.
enum ReportPDF {
  static func make(title: String, recap r: Recap.Result, rows: [Report.Row], biggest: [Txn], lookups: Lookups) -> URL? {
    let page = CGRect(x: 0, y: 0, width: 595, height: 842)
    let margin: CGFloat = 48, width = page.width - margin * 2
    let url = FileManager.default.temporaryDirectory.appending(path: "Paisa Pulse – \(title).pdf")
    let accent = UIColor(red: 0.37, green: 0.36, blue: 0.90, alpha: 1)
    func name(_ id: String) -> String { lookups.categories[id]?.name ?? "Uncategorised" }
    do {
      try UIGraphicsPDFRenderer(bounds: page).writePDF(to: url) { ctx in
        var y: CGFloat = 0
        func newPage() { ctx.beginPage(); y = margin }
        func ensure(_ h: CGFloat) { if y + h > page.height - margin { newPage() } }
        func draw(_ s: String, _ size: CGFloat, _ weight: UIFont.Weight = .regular, color: UIColor = .black, x: CGFloat = 0, w: CGFloat? = nil, right: Bool = false) {
          let p = NSMutableParagraphStyle(); p.alignment = right ? .right : .left
          (s as NSString).draw(in: CGRect(x: margin + x, y: y, width: w ?? width - x, height: size * 1.5),
                               withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: p])
        }
        func line() {
          let c = ctx.cgContext; c.setStrokeColor(UIColor(white: 0.88, alpha: 1).cgColor); c.setLineWidth(0.5)
          c.move(to: CGPoint(x: margin, y: y)); c.addLine(to: CGPoint(x: page.width - margin, y: y)); c.strokePath()
        }
        newPage()
        draw("Paisa Pulse · Monthly report", 11, .semibold, color: accent); y += 18
        draw(title, 26, .bold); y += 42
        let cols: [(String, String)] = [("Spent", Money.format(r.spent)), ("Income", Money.format(r.income)),
                                        (r.saved >= 0 ? "Saved" : "Overspent", Money.format(abs(r.saved)))]
        for (i, c) in cols.enumerated() {
          let x = CGFloat(i) * width / 3
          let yy = y; draw(c.0, 10, color: .gray, x: x, w: width / 3); y += 14
          draw(c.1, 18, .semibold, x: x, w: width / 3); y = yy
        }
        y += 40
        if let ch = r.change {
          draw(ch >= 0 ? "\(Int((ch * 100).rounded()))% more spending than last month" : "\(Int((-ch * 100).rounded()))% less spending than last month", 11, color: .darkGray)
          y += 24
        }
        draw("By category", 14, .semibold); y += 22
        draw("This month", 9, .medium, color: .gray, x: width - 200, w: 100, right: true)
        draw("Last month", 9, .medium, color: .gray, x: width - 100, w: 100, right: true); y += 16; line(); y += 6
        for row in rows {
          ensure(22)
          draw(name(row.categoryId), 11, w: width - 210)
          draw(Money.format(row.amount), 11, .medium, x: width - 200, w: 100, right: true)
          draw(Money.format(row.before), 11, color: .gray, x: width - 100, w: 100, right: true)
          y += 20
        }
        line(); y += 22
        let m = Report.movers(rows)
        if !m.up.isEmpty || !m.down.isEmpty {
          ensure(40); draw("What changed", 14, .semibold); y += 22
          for row in m.up { ensure(18); draw("\(name(row.categoryId)): \(Money.format(row.diff)) more", 11); y += 18 }
          for row in m.down { ensure(18); draw("\(name(row.categoryId)): \(Money.format(-row.diff)) less", 11); y += 18 }
          y += 14
        }
        if !biggest.isEmpty {
          ensure(40); draw("Biggest expenses", 14, .semibold); y += 22
          for t in biggest {
            ensure(18)
            draw("\(t.occurredAt.formatted(.dateTime.day().month()))  \(lookups.title(t))", 11, w: width - 110)
            draw(Money.format(t.effectiveAmount), 11, .medium, x: width - 100, w: 100, right: true); y += 18
          }
        }
        y = max(y + 20, page.height - margin - 14)
        draw("Made on this phone with Paisa Pulse. \(r.count) transactions.", 9, color: .gray)
      }
      return url
    } catch { return nil }
  }
}
