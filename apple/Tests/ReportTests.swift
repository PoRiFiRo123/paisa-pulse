import XCTest
@testable import PaisaPulse

/// Same case as Android ReportTest.
final class ReportTests: XCTestCase {
  func testRowsAndMovers() {
    let t0 = Date(timeIntervalSince1970: 0)
    let month = DateInterval(start: t0.addingTimeInterval(1_000), end: t0.addingTimeInterval(2_000))
    let prev = DateInterval(start: t0, end: t0.addingTimeInterval(1_000))
    let cats = Dictionary(uniqueKeysWithValues: ["food", "fun", "rent"].map { ($0, Category(id: $0, kind: .expense, name: $0, icon: "tag.fill", color: "#000")) })
    func e(_ c: String, _ a: Int, _ at: Double) -> Txn { Txn(type: .expense, amount: a, accountId: "a", categoryId: c, occurredAt: t0.addingTimeInterval(at)) }
    let txns = [e("food", 500, 1_100), e("food", 300, 100), e("fun", 100, 1_200), e("fun", 400, 200), e("rent", 2_000, 1_300), e("rent", 2_000, 300)]
    let rows = Report.rows(txns: txns, categories: cats, month: month, previous: prev)
    XCTAssertEqual(rows.map(\.categoryId), ["rent", "food", "fun"])
    let m = Report.movers(rows)
    XCTAssertEqual(m.up.map(\.categoryId), ["food"]); XCTAssertEqual(m.up.first?.diff, 200)
    XCTAssertEqual(m.down.map(\.categoryId), ["fun"]); XCTAssertEqual(m.down.first?.diff, -300)
    XCTAssertEqual(Report.biggest(txns: txns, month: month).map(\.amount), [2_000, 500, 100])
  }
}
