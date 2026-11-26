import XCTest
@testable import PaisaPulse

/// Bills timeline (same cases as Android BillsTest).
final class BillsTests: XCTestCase {
  private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Kolkata")!; return c }
  private func day(_ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: m, day: d))! }
  private var now: Date { day(11, 26).addingTimeInterval(10 * 3600) }

  func testCardDueAndRecurringSorted() {
    let card = Account(id: "c", name: "MyZone", type: .card, dueDay: 5, color: "#000", icon: "creditcard.fill")
    let bank = Account(id: "b", name: "Axis", type: .bank, color: "#000", icon: "building.columns.fill")
    let rent = RecurringRule(id: "r", type: .expense, amount: 2_000_000, accountId: "b", payee: "Rent", frequency: .monthly, startAt: day(11, 1), nextAt: day(12, 1))
    let gym = RecurringRule(id: "g", type: .expense, amount: 150_000, accountId: "b", payee: "Gym", frequency: .monthly, startAt: day(11, 1), nextAt: day(11, 28))
    let paused = RecurringRule(id: "p", type: .expense, amount: 150_000, accountId: "b", payee: "Gym", frequency: .monthly, startAt: day(11, 1), nextAt: day(11, 28), pausedAt: day(11, 2))
    let bills = Bills.upcoming(accounts: [card, bank], txns: [], rules: [rent, gym, paused], balances: ["c": -640_000, "b": 100], now: now, calendar: cal)
    XCTAssertEqual(bills.map(\.id), ["rule-g", "rule-r", "card-c"])
    XCTAssertEqual(bills.last?.amount, 640_000); XCTAssertEqual(bills.last?.due, day(12, 5))
    XCTAssertEqual(Bills.dueText(bills[0], now: now, calendar: cal), "Due in 2 days")
  }

  func testNothingOwedNoCardBill() {
    let card = Account(id: "c", name: "MyZone", type: .card, dueDay: 5, color: "#000", icon: "creditcard.fill")
    XCTAssertTrue(Bills.upcoming(accounts: [card], txns: [], rules: [], balances: ["c": 0], now: now, calendar: cal).isEmpty)
  }
}
