import SwiftData
import XCTest
@testable import PaisaPulse

final class MoneyTests: XCTestCase {
  func testFormatHasNoMinusAndUsesLakhGrouping() {
    XCTAssertEqual(Money.format(12_345_600), "₹1,23,456")
    XCTAssertEqual(Money.format(-12_345_650), "₹1,23,456.50")
    XCTAssertEqual(Money.format(0), "₹0")
    XCTAssertEqual(Money.format(500, hidden: true), "₹••••")
  }

  func testCompact() {
    XCTAssertEqual(Money.compact(95_000), "₹950")
    XCTAssertEqual(Money.compact(3_845_000), "₹38K")
    XCTAssertEqual(Money.compact(12_000_000), "₹1.2L")
    XCTAssertEqual(Money.compact(-230_000_000), "₹2.3Cr")
  }

  func testParse() {
    XCTAssertEqual(Money.parse("1,250.5"), 125_050)
    XCTAssertEqual(Money.parse("₹ 99"), 9_900)
    XCTAssertNil(Money.parse(""))
    XCTAssertNil(Money.parse("0"))
    XCTAssertNil(Money.parse("abc"))
  }

  func testKeypadMath() {
    XCTAssertEqual(KeypadMath.evaluate("250+80×2"), 410)
    XCTAssertEqual(KeypadMath.evaluate("100÷4−5"), 20)
    XCTAssertEqual(KeypadMath.evaluate("120+"), 120)
    XCTAssertNil(KeypadMath.evaluate("5÷0"))
    XCTAssertEqual(Money.paise(from: KeypadMath.evaluate("10÷3")!), 333)
  }
}

final class LedgerTests: XCTestCase {
  func testBalancesTransfersAndCards() {
    let bank = Account(id: "b", name: "Bank", type: .bank, openingBalance: 100_000, color: "#000000", icon: "x")
    let card = Account(id: "c", name: "Card", type: .card, openingBalance: 0, color: "#000000", icon: "x")
    let txns = [
      Txn(type: .expense, amount: 30_000, accountId: "c"),
      Txn(type: .transfer, amount: 20_000, accountId: "b", toAccountId: "c"),
      Txn(type: .income, amount: 5_000, accountId: "b"),
      Txn(type: .expense, amount: 99_999, accountId: "b", deletedAt: .now),
    ]
    let b = Ledger.balances(accounts: [bank, card], txns: txns)
    XCTAssertEqual(b["b"], 85_000)
    XCTAssertEqual(b["c"], -10_000)
    XCTAssertEqual(Ledger.netWorth(accounts: [bank, card], balances: b), 75_000)
  }

  func testSplitShareCountsAsSpending() {
    let range = DateInterval(start: .now.addingTimeInterval(-3600), duration: 7200)
    let txns = [Txn(type: .expense, amount: 90_000, accountId: "a", splitShare: 30_000), Txn(type: .transfer, amount: 5_000, accountId: "a", toAccountId: "b")]
    XCTAssertEqual(Ledger.summary(txns, in: range).spent, 30_000)
  }

  func testEqualShares() {
    let s = Splits.equalShares(total: 100_000, friends: 2)
    XCTAssertEqual(s.each, 33_333)
    XCTAssertEqual(s.yours, 33_334)
  }

  func testSalaryMonth() {
    let cal = Calendar(identifier: .gregorian)
    let d = cal.date(from: DateComponents(year: 2026, month: 11, day: 3))!
    let m = Periods.month(containing: d, startDay: 25, calendar: cal)
    XCTAssertEqual(cal.component(.day, from: m.start), 25)
    XCTAssertEqual(cal.component(.month, from: m.start), 10)
  }

  func testCardDueDate() {
    let cal = Calendar(identifier: .gregorian)
    let d = cal.date(from: DateComponents(year: 2026, month: 2, day: 20))!
    let due = Cards.nextDue(dueDay: 31, from: d, calendar: cal)
    XCTAssertEqual(cal.component(.day, from: due), 28)
  }

  func testRecurrenceCatchUpAndAnchor() {
    let cal = Calendar.current
    let start = cal.date(from: DateComponents(year: 2026, month: 1, day: 31))!
    let rule = RecurringRule(type: .expense, amount: 100, accountId: "a", frequency: .monthly, startAt: start)
    let due = Recurrence.due([rule], now: cal.date(from: DateComponents(year: 2026, month: 4, day: 1))!)
    XCTAssertEqual(due.count, 3)
    XCTAssertEqual(cal.component(.day, from: due[1].1), 28) // Feb
    XCTAssertEqual(cal.component(.day, from: due[2].1), 31) // Mar: back on the 31st
  }

  func testAppGroupResolve() {
    XCTAssertEqual(AppGroup.resolve([]), "group.com.paisapulse.app")
    XCTAssertEqual(AppGroup.resolve(["group.com.paisapulse.app.ABC123"]), "group.com.paisapulse.app.ABC123")
  }
}

@MainActor final class BackupTests: XCTestCase {
  func testRoundTripKeepsAndroidFormat() throws {
    let container = Store.makeContainer(inMemory: true)
    let ctx = container.mainContext
    let a = Account(id: "acc", name: "Axis", type: .bank, openingBalance: 500_000, color: "#97144D", icon: "building.columns.fill")
    ctx.insert(a)
    ctx.insert(Txn(id: "t1", type: .expense, amount: 42_800, accountId: "acc", payee: "Swiggy", splitShare: 21_400))
    ctx.insert(Friend(id: "f", name: "Ritwik"))
    try ctx.save()
    let data = try BackupCodec.export(ctx)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(json["format"] as? String, "paisa-pulse-backup")
    XCTAssertEqual(json["version"] as? Int, 4)
    let t = (json["transactions"] as! [[String: Any]])[0]
    XCTAssertEqual(t["accountId"] as? String, "acc")
    XCTAssertNotNil(t["occurredAt"] as? Int64 ?? (t["occurredAt"] as? Int).map(Int64.init))

    let file = try BackupCodec.decode(data)
    let other = Store.makeContainer(inMemory: true).mainContext
    try BackupCodec.restore(file, into: other)
    let restored = try other.fetch(FetchDescriptor<Txn>())
    XCTAssertEqual(restored.count, 1)
    XCTAssertEqual(restored[0].splitShare, 21_400)
    XCTAssertEqual(try other.fetch(FetchDescriptor<Friend>()).count, 1)
  }

  func testRejectsOtherFiles() {
    XCTAssertThrowsError(try BackupCodec.decode(Data("{\"hello\":1}".utf8)))
  }
}
