import XCTest
@testable import PaisaPulse

/// Same case as Android NetWorthTest.
final class NetWorthTests: XCTestCase {
  func testAssetsOwedAndGroups() {
    let accs = [Account(id: "a", name: "Axis", type: .bank, color: "#000", icon: "x"), Account(id: "b", name: "BoB", type: .bank, color: "#000", icon: "x"),
                Account(id: "c", name: "MyZone", type: .card, color: "#000", icon: "x"), Account(id: "x", name: "Old", type: .bank, color: "#000", icon: "x", archivedAt: .now)]
    let b = NetWorth.breakdown(accounts: accs, balances: ["a": 100_000, "b": 50_000, "c": -30_000, "x": 999])
    XCTAssertEqual(b.assets, 150_000); XCTAssertEqual(b.owed, 30_000); XCTAssertEqual(b.total, 120_000)
    XCTAssertEqual(b.byType.map { $0.label }, ["Bank accounts", "Credit cards (owed)"])
  }
}
