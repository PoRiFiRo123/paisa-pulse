import XCTest
@testable import PaisaPulse

/// Bank SMS / notification alerts (same cases as Android BankAlertsTest).
final class BankAlertsTests: XCTestCase {
  private let t0 = Date(timeIntervalSince1970: 1_795_600_000)
  private lazy var ctx = CaptureContext(
    accounts: [CaptureAccount(id: "axis", name: "Axis Bank", type: .bank, institution: "Axis Bank", last4: "4321"),
               CaptureAccount(id: "bob", name: "Bank of Baroda", type: .bank, institution: "Bank of Baroda", last4: "7556"),
               CaptureAccount(id: "myzone", name: "Axis MyZone", type: .card, institution: "Axis Bank", last4: "1234")],
    categories: [CaptureCategory(id: "food", name: "Food & Dining", kind: .expense, parentId: nil),
                 CaptureCategory(id: "salary", name: "Salary", kind: .income, parentId: nil)],
    defaultAccountId: "axis", now: t0)
  private func p(_ text: String) -> CaptureDraft? { BankAlerts.parse(PendingAlert(text: text, sender: nil, receivedAt: t0), ctx: ctx) }

  func testAxisUpiDebit() {
    let d = p("INR 450.00 debited from A/c no. XX4321 on 25-11-26 at 10:15:30 IST. Info- UPI/P2M/533012345678/SWIGGY. Not you? SMS BLOCK 4321 to 919951860002 - Axis Bank")!
    XCTAssertEqual(d.amount, 45_000); XCTAssertEqual(d.type, .expense); XCTAssertEqual(d.accountId, "axis"); XCTAssertEqual(d.payee, "Swiggy")
    XCTAssertEqual(d.key, "alert:533012345678"); XCTAssertEqual(d.occurredAt, t0)
  }
  func testBobTransfer() {
    let d = p("Rs.199.00 transferred from A/c ...7556 to:UPI/533098765432. Total Bal:Rs.12,345.67CR. Avlbl Amt:Rs.12,345.67(25-11-2026 07:43:21) - Bank of Baroda")!
    XCTAssertEqual(d.amount, 19_900); XCTAssertEqual(d.type, .expense); XCTAssertEqual(d.accountId, "bob"); XCTAssertEqual(d.key, "alert:533098765432")
  }
  func testHdfcSent() {
    let d = p("Sent Rs.250.00 From HDFC Bank A/C *9999 To Rahul Sharma On 25/11/26 Ref 533011112222 Not You? Call 18002586161")!
    XCTAssertEqual(d.amount, 25_000); XCTAssertEqual(d.payee, "Rahul Sharma"); XCTAssertEqual(d.type, .expense)
  }
  func testSbiUpi() {
    let d = p("Dear UPI user A/C X7556 debited by 80.0 on date 25Nov26 trf to CHAI POINT Refno 533055556666. If not u? call 1800111109. -SBI")!
    XCTAssertEqual(d.amount, 8_000); XCTAssertEqual(d.accountId, "bob"); XCTAssertEqual(d.payee, "Chai Point")
  }
  func testIciciDebit() {
    let d = p("ICICI Bank Acct XX321 debited for Rs 1,299.00 on 25-Nov-26; AMAZON PAY credited. UPI:533077778888. Call 18002662 for dispute.")!
    XCTAssertEqual(d.amount, 129_900); XCTAssertEqual(d.type, .expense)
  }
  func testCardSpend() {
    let d = p("Spent INR 2,499.00 Axis Bank Card no. XX1234 25-11-26 13:45:12 IST at MYNTRA DESIGNS. Avl Lmt INR 97,501.00. Not you? SMS BLOCK 1234")!
    XCTAssertEqual(d.amount, 249_900); XCTAssertEqual(d.accountId, "myzone"); XCTAssertEqual(d.type, .expense)
  }
  func testSalaryCredit() {
    let d = p("INR 90,000.00 credited to A/c no. XX4321 on 01-11-26 by NEFT from BOOMI SOFTWARE PVT LTD. Avl Bal INR 1,02,345.00 - Axis Bank")!
    XCTAssertEqual(d.amount, 9_000_000); XCTAssertEqual(d.type, .income); XCTAssertEqual(d.accountId, "axis")
  }
  func testBalanceIsNotTheAmount() {
    XCTAssertEqual(p("Avl Bal: Rs 5,000.00. Rs 120.00 debited from A/c XX4321 towards UPI/533000001111/ZEPTO")!.amount, 12_000)
  }
  func testCardBillPayment() {
    let d = p("Payment of INR 6,400.00 has been received towards your Axis Bank Credit Card XX1234. Thank you.")!
    XCTAssertEqual(d.type, .transfer); XCTAssertEqual(d.toAccountId, "myzone"); XCTAssertEqual(d.accountId, "axis")
  }
  func testIgnoresOtpsDuesAndRequests() {
    XCTAssertNil(p("123456 is your OTP for a transaction of INR 450.00 at SWIGGY. Do not share it."))
    XCTAssertNil(p("Your Axis Bank Credit Card XX1234 statement: Total due INR 6,400.00, minimum amount due INR 320. Due date 05-12-26."))
    XCTAssertNil(p("Rahul has requested money of Rs 200.00 on Google Pay. Pay or decline."))
    XCTAssertNil(p("Rs 499.00 will be debited from your A/c XX4321 on 28-11-26 for Netflix e-mandate."))
    XCTAssertNil(p("Transaction of Rs 450.00 failed. Amount will be refunded."))
  }
  func testBobMandateDebit() {
    let d = p("Your A/c XX7556 is debited towards Mahanadi Coalfields for Rs. 14960.00 on 2026-11-26 06:13:43 AM UMN 01a2079d9c0470e2abf86e265b4a551c@yesg - Bank Of Baroda")!
    XCTAssertEqual(d.amount, 1_496_000); XCTAssertEqual(d.type, .expense); XCTAssertEqual(d.accountId, "bob"); XCTAssertEqual(d.payee, "Mahanadi Coalfields")
    XCTAssertEqual(PaymentMethod.fromText(d.source), .autoDebit)
  }
  func testIdIsNotAPayee() {
    XCTAssertNil(BankAlerts.payee("Rs 50.00 debited from A/c XX4321 UMN 01a2079d9c0470e2abf86e265b4a551c@yesg"))
  }
  func testSameAlertSameKey() {
    let a = "Rs 99.00 debited from A/c XX4321. Info: SPOTIFY"
    XCTAssertEqual(BankAlerts.key(a, amount: 9_900), BankAlerts.key(a, amount: 9_900))
  }
}
