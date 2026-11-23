import XCTest
@testable import PaisaPulse

// Expected values come from the RN app's parsers (the Android port matches them exactly).
enum Fixtures {
  static let axis = """
Name :- NISHIT KIRANI
Account No :- 912010012345678
Statement of Account for the period 01-09-2026 To 30-09-2026 AXIS BANK

Tran Date,CHQNO,PARTICULARS,DR,CR,BAL,SOL
01-09-2026,,OPENING BALANCE,,,10000.00,
01-09-2026,,UPI/P2M/424412345678/SWIGGY LIMITED/swiggy@icici/Payment for order,420.00,,9580.00,1234
02-09-2026,,NEFT/N245260123456/ACME TECHNOLOGIES PVT LTD/SALARY SEP,,90000.00,99580.00,1234
03-09-2026,,ATM-WDL/MG ROAD BANGALORE/S1AW0123,2000.00,,97580.00,1234
05-09-2026,,BILLDESK/AXIS BANK CREDIT CARD/XX3307 PAYMENT,8360.00,,89220.00,1234
06-09-2026,,UPI/P2A/424912345/RAHUL SHARMA/rahul@okaxis/rent share,7500.00,,81720.00,1234
30-09-2026,,Int.Pd:912010012345678:01-07-2026 to 30-09-2026,,245.00,81965.00,1234
,,TRANSACTION TOTAL,17920.00,90245.00,,
"""

  static let bob = """
Bank of Baroda
Account Statement
DATE,NARRATION,CHQ.NO.,WITHDRAWAL(DR),DEPOSIT(CR),BALANCE(INR)
04/09/2026,UPI/424512349876/DR/BIGBASKET/UTIB/bigbasket@axisbank,,"1,245.00",,"48,755.00"
08/09/2026,IMPS/P2A/425112345678/PRIYA/SBIN0001234/gift,,"5,000.00",,"43,755.00"
10/09/2026,TRF FROM AXIS BANK XX5678,,,"25,000.00","68,755.00"
"""

  static let hdfc = """
Date,Narration,Chq./Ref.No.,Value Dt,Withdrawal Amt.,Deposit Amt.,Closing Balance
01/09/26,UPI-ZOMATO LTD-zomato-order@hdfcbank-HDFC0MERUPI-424412345111-Dinner,0000424412345111,01/09/26,650.00,,24350.00
02/09/26,POS 512345XXXXXX1234 AMAZON PAY INDIA,0000000000000000,02/09/26,"2,499.00",,21851.00
03/09/26,NEFT CR-CITI0100000-ACME TECHNOLOGIES-SALARY-CITIN24245123,CITIN24245123,03/09/26,,"1,00,000.00","1,21,851.00"
04/09/26,ACH D- TP ACH BAJAJ FINANCE-CITI000000123,0000000000000456,04/09/26,"4,210.00",,"1,17,641.00"
"""

  static let icici = """
ICICI Bank Limited
Detailed Statement
S No.,Value Date,Transaction Date,Cheque Number,Transaction Remarks,Withdrawal Amount (INR ),Deposit Amount (INR ),Balance (INR )
1,01/09/2026,01/09/2026,,UPI/424412345222/Payment for order/uber.rides@hdfcbank/HDFC Bank/ICI1234567890,186.00,0.00,"12,314.00"
2,02/09/2026,02/09/2026,,MMT/IMPS/424512345333/Rent/NOBROKER/ICIC0000011,"18,000.00",0.00,"-5,686.00"
3,05/09/2026,05/09/2026,,BIL/ONL/000123456/NETFLIX/NETFLIX-MONTHLY,649.00,0.00,"-6,335.00"
"""

  static let sbi = """
State Bank of India
Account Statement from 1 Sep 2026 to 30 Sep 2026
Txn Date,Value Date,Description,Ref No./Cheque No.,Debit,Credit,Balance
1 Sep 2026,1 Sep 2026,TO TRANSFER-UPI/DR/424412345444/BLINKIT/YESB/blinkit.payu@hdfcbank/Groceries,TRANSFER TO 4897693162093,312.00,,"5,688.00"
2 Sep 2026,2 Sep 2026,ATM WDL-ATM CASH 1234 SBI MG ROAD,,"1,000.00",,"4,688.00"
15 Sep 2026,15 Sep 2026,CREDIT INTEREST,,,34.00,"4,722.00"
"""

  static let axiscard = """
Axis Bank MyZone Credit Card Statement
Card No: 5241XXXXXXXX3307
Date,Transaction Details,Merchant Category,Amount (INR),Debit/Credit
03/09/2026,SWIGGY BANGALORE IN,FOOD,580.00,Debit
07/09/2026,NETFLIX.COM MUMBAI,SUBSCRIPTION,649.00,Debit
06/09/2026,BBPS PAYMENT RECEIVED - THANK YOU,,"8,360.00",Credit
15/09/2026,AMAZON PAY INDIA PRIVATE,SHOPPING,"1,299.00",Debit
16/09/2026,REFUND AMAZON PAY INDIA,SHOPPING,299.00,Credit
"""

}

final class StatementTests: XCTestCase {
  private func run(_ csv: String, card: Bool = false) -> (StatementTemplate?, Mapping?, [StatementRow]) {
    let sheet = StatementReaders.csv(csv)
    let t = StatementParser.detectTemplate(sheet)
    guard let m = StatementParser.detectMapping(sheet, template: t, cardAccount: card) else { return (t, nil, []) }
    return (t, m, StatementParser.extractRows(sheet, m))
  }

  private func check(_ csv: String, card: Bool = false, template: String, columns: String, expected: [(String, String, Int, Bool, String, String, String)]) {
    let (t, m, rows) = run(csv, card: card)
    XCTAssertEqual(t?.id, template)
    XCTAssertEqual(m?.columns.map(\.rawValue).joined(separator: ","), columns)
    XCTAssertEqual(rows.count, expected.count)
    let keys = ImportPlan.rowKeys(accountId: "acc1", rows: rows)
    for (i, e) in expected.enumerated() where i < rows.count {
      let n = Narrations.parse(rows[i].description)
      XCTAssertEqual(rows[i].amount, e.2, "amount \(i)")
      XCTAssertEqual(rows[i].out, e.3, "direction \(i)")
      XCTAssertEqual(n.channel, e.0, "channel \(i)")
      XCTAssertEqual(n.payee ?? "", e.1, "payee \(i)")
      XCTAssertEqual(Narrations.suggestCategory(rows[i].description, payee: n.payee, out: rows[i].out) ?? "", e.4, "category \(i)")
      XCTAssertEqual(n.note ?? "", e.5, "note \(i)")
      XCTAssertEqual(keys[i], e.6, "fingerprint \(i)")
    }
  }

  func testAxis() {
    check(Fixtures.axis, card: false, template: "axis-bank", columns: "date,reference,description,debit,credit,balance,ignore", expected: [
      ("UPI", "Swiggy", 42000, true, "Food & Dining", "", "cbf43cbb22c02940"),
      ("NEFT", "Acme Technologies", 9000000, false, "Salary", "SALARY SEP", "b25bd2b30dc0f6c0"),
      ("ATM", "ATM withdrawal", 200000, true, "", "", "394c171bb9f6e140"),
      ("CARD_PAYMENT", "Credit card payment", 836000, true, "", "", "98bfead2aba4e740"),
      ("UPI", "Rahul Sharma", 750000, true, "Rent", "rent share", "e9fff5bbfb2dcf20"),
      ("INTEREST", "Interest", 24500, false, "Interest", "", "774f5c399a8b5618"),
    ])
  }

  func testBob() {
    check(Fixtures.bob, card: false, template: "bob", columns: "date,description,reference,debit,credit,balance", expected: [
      ("UPI", "BigBasket", 124500, true, "Groceries", "", "ec87c2809e8857c8"),
      ("IMPS", "Priya", 500000, true, "Gifts & Donations", "", "00bd8979fe534788"),
      ("OTHER", "Trf From Axis Bank Xx5678", 2500000, false, "", "", "6bc5970b8c8c8ac8"),
    ])
  }

  func testHdfc() {
    check(Fixtures.hdfc, card: false, template: "hdfc", columns: "date,description,reference,valueDate,debit,credit,balance", expected: [
      ("UPI", "Zomato", 65000, true, "Food & Dining", "Dinner", "40734076f1a48550"),
      ("POS", "Amazon", 249900, true, "Shopping", "", "bee846f2e2656688"),
      ("NEFT", "Acme Technologies", 10000000, false, "Salary", "SALARY CITIN24245123", "ffb84787cb6d1f88"),
      ("NACH", "Bajaj Finance", 421000, true, "EMI/Loans", "", "4f31acd5fbec6578"),
    ])
  }

  func testIcici() {
    check(Fixtures.icici, card: false, template: "icici", columns: "ignore,valueDate,date,reference,description,debit,credit,balance", expected: [
      ("UPI", "Uber", 18600, true, "Metro/Auto/Cab", "", "5c9a2e737c01e1b0"),
      ("IMPS", "NoBroker", 1800000, true, "Rent", "", "d9ec05893aee9730"),
      ("OTHER", "Netflix", 64900, true, "Subscriptions", "NETFLIX MONTHLY", "8faa4fd19fa78b68"),
    ])
  }

  func testSbi() {
    check(Fixtures.sbi, card: false, template: "sbi", columns: "date,valueDate,description,reference,debit,credit,balance", expected: [
      ("UPI", "Blinkit", 31200, true, "Groceries", "Groceries", "1be3e265ae5c6e20"),
      ("ATM", "ATM withdrawal", 100000, true, "", "", "d30f5ea0dfc51be0"),
      ("INTEREST", "Interest", 3400, false, "Interest", "", "32e82fe295ebd010"),
    ])
  }

  func testAxiscard() {
    check(Fixtures.axiscard, card: true, template: "axis-card", columns: "date,description,ignore,amount,drcr", expected: [
      ("OTHER", "Swiggy", 58000, true, "Food & Dining", "", "dadb03dacc28a178"),
      ("OTHER", "Netflix", 64900, true, "Subscriptions", "", "2a63864c3ba2d590"),
      ("CARD_PAYMENT", "Credit card payment", 836000, false, "", "", "b768e3404ce6ecf0"),
      ("OTHER", "Amazon", 129900, true, "Shopping", "", "ac851659e9367280"),
      ("REFUND", "Amazon", 29900, false, "Refund", "", "abe91d475f1710d0"),
    ])
  }

  func testBalancesReconcile() {
    XCTAssertEqual(StatementParser.balanceMismatches(run(Fixtures.axis).2), 0)
    XCTAssertNil(StatementParser.balanceMismatches(run(Fixtures.axiscard, card: true).2))
  }

  func testDatesAndAmounts() {
    let cal = Calendar.current
    for s in ["01-09-2026", "01/09/26", "1-Sep-2026", "01 SEP 26", "1 Sept 2026", "Sep 1, 2026", "2026-09-01", "46266"] {
      let d = StatementParser.parseDate(s)
      XCTAssertNotNil(d, s)
      if let d { XCTAssertEqual(cal.dateComponents([.year, .month, .day, .hour], from: d), DateComponents(year: 2026, month: 9, day: 1, hour: 12), s) }
    }
    let pm = StatementParser.parseDate("01/09/2026 06:15 PM")!
    XCTAssertEqual(cal.component(.hour, from: pm), 18)
    XCTAssertNil(StatementParser.parseDate("31/02/2026"))
    XCTAssertNil(StatementParser.parseDate("12345"))
    XCTAssertEqual(StatementParser.parseAmount("1,23,456.78")?.paise, 12_345_678)
    XCTAssertEqual(StatementParser.parseAmount("(120.00)")?.paise, -12_000)
    XCTAssertEqual(StatementParser.parseAmount("120.00 Dr")?.marker, "d")
    XCTAssertEqual(StatementParser.parseAmount("1,234.50CR")?.paise, 123_450)
    XCTAssertEqual(StatementParser.parseAmount("10.005")?.paise, 1001)
    XCTAssertNil(StatementParser.parseAmount("0.00"))
    XCTAssertNil(StatementParser.parseAmount("-"))
  }

  func testPdfLayoutRebuildsTheTable() throws {
    let url = try XCTUnwrap(Bundle(for: StatementTests.self).url(forResource: "axis-pdf-items", withExtension: "json"))
    let items = try JSONDecoder().decode([TextItem].self, from: Data(contentsOf: url))
    let sheet = PdfLayout.toSheet(items).map { $0.joined(separator: " ¦ ") }
    XCTAssertEqual(sheet, [

      "Tran Date ¦ Particulars ¦ Debit ¦ Credit ¦ Balance",
      "01-09-2026 ¦ OPENING BALANCE ¦  ¦  ¦ 10,000.00",
      "01-09-2026 ¦ UPI/P2M/424412345678/SWIGGY LIMITED/swiggy@icici/Payment for order 88231 ¦ 420.00 ¦  ¦ 9,580.00",
      "02-09-2026 ¦ NEFT/N245260123456/ACME TECHNOLOGIES PVT LTD/SALARY SEP ¦  ¦ 90,000.00 ¦ 99,580.00",
      "03-09-2026 ¦ ATM-WDL/MG ROAD BANGALORE/S1AW0123 ¦ 2,000.00 ¦  ¦ 97,580.00",
      "05-09-2026 ¦ BILLDESK/AXIS BANK CREDIT CARD/XX3307 PAYMENT ¦ 8,360.00 ¦  ¦ 89,220.00",
      "06-09-2026 ¦ UPI/P2A/424912345/RAHUL SHARMA/rahul@okaxis/rent share ¦ 7,500.00 ¦  ¦ 81,720.00",
      "Closing Balance 81,720.00 ¦  ¦  ¦  ¦ ",
    ])
  }

  func testHtmlAndDelimiters() {
    let html = "<table><tr><th>Date</th><th>Narration</th><th>Debit</th><th>Credit</th><th>Balance</th></tr><tr><td>01/09/2026</td><td>UPI&amp;X</td><td>10.00</td><td></td><td>90.00</td></tr></table>"
    XCTAssertEqual(StatementReaders.html(html), [["Date", "Narration", "Debit", "Credit", "Balance"], ["01/09/2026", "UPI&X", "10.00", "", "90.00"]])
    XCTAssertEqual(StatementReaders.csv("a;b;c\r\n1;\"2;3\";4\r\n"), [["a", "b", "c"], ["1", "2;3", "4"]])
  }
}

final class CaptureTests: XCTestCase {
  private let ctx = CaptureContext(
    accounts: [CaptureAccount(id: "axis", name: "Axis Bank", type: .bank, institution: "Axis Bank", last4: "5678"),
               CaptureAccount(id: "bob", name: "Bank of Baroda", type: .bank, institution: "Bank of Baroda", last4: "9012"),
               CaptureAccount(id: "card", name: "Axis MyZone", type: .card, institution: "Axis Bank", last4: "3307")],
    categories: [CaptureCategory(id: "food", name: "Food & Dining", kind: .expense, parentId: nil),
                 CaptureCategory(id: "groceries", name: "Groceries", kind: .expense, parentId: nil),
                 CaptureCategory(id: "other", name: "Other", kind: .income, parentId: nil)],
    defaultAccountId: "axis",
    now: Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 18))!)

  private func hm(_ d: Date) -> [Int] { let c = Calendar.current.dateComponents([.month, .day, .hour, .minute], from: d); return [c.month!, c.day!, c.hour!, c.minute!] }

  func testGooglePay() {
    let d = ScreenshotParser.parse(["To Swiggy", "₹420", "Completed", "10 Oct 2026, 2:15 pm", "Split with friends", "UPI transaction ID", "424412345678", "To: SWIGGY LIMITED", "swiggy@icici", "From: NISHIT KIRANI (Bank of Baroda)", "Bank of Baroda 9012", "Google transaction ID", "CICAgOCx8aqHGw"], ctx: ctx)!
    XCTAssertEqual(d.type, .expense); XCTAssertEqual(d.amount, 42_000); XCTAssertEqual(d.payee, "Swiggy")
    XCTAssertEqual(d.accountId, "bob"); XCTAssertEqual(d.categoryId, "food"); XCTAssertTrue(d.include)
    XCTAssertEqual(hm(d.occurredAt), [10, 10, 14, 15])
  }

  func testPhonePeAndPaytm() {
    let p = ScreenshotParser.parse(["Transaction Successful", "02:15 pm on 09 Oct 2026", "Paid to", "BLINKIT", "blinkit.payu@hdfcbank", "₹ 1,245", "Debited from", "XXXXXXXX5678", "UTR: 424512349876", "Transaction ID", "T2410091415221234567890"], ctx: ctx)!
    XCTAssertEqual(p.amount, 124_500); XCTAssertEqual(p.payee, "Blinkit"); XCTAssertEqual(p.accountId, "axis"); XCTAssertEqual(p.categoryId, "groceries")
    XCTAssertEqual(hm(p.occurredAt), [10, 9, 14, 15])
    let t = ScreenshotParser.parse(["Paid Successfully to\nRahul Sharma", "₹2,000", "UPI Ref No: 425112345678\n10 Oct, 09:41 AM", "From: Axis Bank - 5678"], ctx: ctx)!
    XCTAssertEqual(t.amount, 200_000); XCTAssertEqual(t.payee, "Rahul Sharma"); XCTAssertEqual(t.accountId, "axis")
    let r = ScreenshotParser.parse(["Received from", "Priya Mehta", "₹500", "Completed", "8 Oct 2026, 7:02 pm", "Credited to Axis Bank XX5678"], ctx: ctx)!
    XCTAssertEqual(r.type, .income); XCTAssertEqual(r.payee, "Priya Mehta")
  }

  func testCardBillIsATransfer() {
    let d = ScreenshotParser.parse(["payment successful", "₹8,360", "paid to Axis Bank credit card", "xxxx 3307", "05 Oct 2026, 11:20 am"], ctx: ctx)!
    XCTAssertEqual(d.type, .transfer); XCTAssertEqual(d.toAccountId, "card"); XCTAssertEqual(d.accountId, "axis"); XCTAssertNil(d.categoryId)
  }

  func testFailedAndEmpty() {
    let d = ScreenshotParser.parse(["Payment failed", "Paid to", "Zomato", "₹350", "10 Oct 2026"], ctx: ctx)!
    XCTAssertFalse(d.include); XCTAssertEqual(d.warning, "This payment may have failed or be pending.")
    XCTAssertNil(ScreenshotParser.parse(["Chats", "Hello there"], ctx: ctx))
    let lastYear = ScreenshotParser.findReceiptDate(["28 Dec, 10:00 AM"], now: ctx.now)!
    XCTAssertEqual(Calendar.current.component(.year, from: lastYear), 2025)
  }
}

final class Batch2LogicTests: XCTestCase {
  func testBrands() {
    XCTAssertEqual(Brands.match("UPI/SWIGGY INSTAMART/x")?.name, "Swiggy Instamart")
    XCTAssertEqual(Brands.match("AMAZON PRIME VIDEO")?.name, "Amazon Prime")
    XCTAssertNil(Brands.match("Rahul Sharma"))
    XCTAssertEqual(Brands.match("Tata 1mg")?.monogram, "T")
  }

  func testSubscriptionsDetectsAMonthlyPayment() {
    let cal = Calendar.current
    let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12))!
    let txns = (0..<4).map { i in
      Txn(type: .expense, amount: 64_900, accountId: "a", payee: "Netflix", occurredAt: cal.date(byAdding: .month, value: -i, to: cal.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 12))!)!)
    }
    let found = Subscriptions.detect(txns, rules: [], now: now)
    XCTAssertEqual(found.count, 1)
    XCTAssertEqual(found.first?.frequency, .monthly)
    XCTAssertEqual(Subscriptions.monthly(amount: 149_900, frequency: .yearly), 12_492)
    let rule = Subscriptions.rule(for: found[0], now: now)
    XCTAssertEqual(cal.dateComponents([.month, .day], from: rule.nextAt), DateComponents(month: 11, day: 5))
  }

  func testPeriods() {
    let cal = Calendar.current
    let d = cal.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 12))!
    let q = PeriodKind.quarter.range(offset: 0, from: d, startDay: 1, weekStart: 2)
    XCTAssertEqual(cal.dateComponents([.month, .day], from: q.start), DateComponents(month: 10, day: 1))
    XCTAssertEqual(cal.dateComponents([.year, .month], from: q.end), DateComponents(year: 2027, month: 1))
    let y = PeriodKind.year.range(offset: -1, from: d, startDay: 1, weekStart: 2)
    XCTAssertEqual(cal.component(.year, from: y.start), 2025)
    XCTAssertEqual(PeriodKind.quarter.short(q), "Q4 ’26")
  }

  func testFilterPayloadRoundTrip() {
    let f = ActivityFilter(monthOffset: -1, accountId: "a", categoryId: nil, type: .expense)
    let p = FilterPayload(f, search: "swiggy")
    XCTAssertEqual(FilterPayload.parse(p.json), p)
    XCTAssertEqual(FilterPayload.parse(p.json)?.filter, f)
    // The RN app's shape parses too.
    XCTAssertEqual(FilterPayload.parse(#"{"filters":{"monthOffset":null,"accountIds":[],"categoryIds":["c"],"types":[]},"search":""}"#)?.filter.categoryId, "c")
  }
}

final class Stage3Tests: XCTestCase {
  func testSplits() {
    let r = SplitMath.compute(total: 100_000, SplitSetup(people: ["a", "b"]))
    XCTAssertEqual(r.myShare, 33_334)
    XCTAssertEqual(r.entries, ["a": 33_333, "b": 33_333])
    XCTAssertEqual(SplitMath.compute(total: 90_000, SplitSetup(people: ["a", "b"], payer: "a")).entries, ["a": -30_000])
    let shares = SplitMath.compute(total: 90_000, SplitSetup(people: ["a"], mode: .shares, values: ["me": 2, "a": 1]))
    XCTAssertEqual(shares.myShare, 60_000)
    XCTAssertEqual(SplitMath.compute(total: 90_000, SplitSetup(people: ["a"], mode: .amount, values: ["me": 50_000, "a": 30_000])).unassigned, 10_000)
    XCTAssertEqual(SplitMath.compute(total: 90_000, SplitSetup(people: ["a", "b"], includeMe: false)).entries, ["a": 45_000, "b": 45_000])
  }

  func testPayLinks() {
    let upi = SplitMath.upiURL(to: "me@okaxis", name: "Nishit", amount: 50_000, note: "Dinner")!.absoluteString
    XCTAssertTrue(upi.hasPrefix("upi://pay?pa=me@okaxis&pn=Nishit&am=500.00&cu=INR"), upi)
    let page = SplitMath.payPageURL(to: "me@okaxis", name: "Nishit", amount: 1_250, note: nil)!.absoluteString
    XCTAssertEqual(page, "https://porifiro123.github.io/paisa-pulse/pay/#pa=me@okaxis&pn=Nishit&am=12.50")
  }

  func testCleanupFoldsIntoOpeningBalances() {
    let d = { (s: Double) in Date(timeIntervalSince1970: s) }
    let txns = [
      Txn(type: .expense, amount: 1_000, accountId: "a", occurredAt: d(1_000)),
      Txn(type: .income, amount: 5_000, accountId: "a", occurredAt: d(2_000)),
      Txn(type: .transfer, amount: 2_000, accountId: "a", toAccountId: "c", occurredAt: d(3_000)),
      Txn(type: .expense, amount: 700, accountId: "a", occurredAt: d(3_500), deletedAt: d(4_000)),
      Txn(type: .expense, amount: 9_999, accountId: "a", occurredAt: d(10_000)),
    ]
    let plan = Cleanup.plan(txns, before: d(5_000))
    XCTAssertEqual(plan.delta, ["a": 2_000, "c": 2_000])
    XCTAssertEqual(plan.remove.count, 4)
    XCTAssertEqual(Cleanup.months(key: "quarterly", custom: 0), 3)
    XCTAssertEqual(Cleanup.months(key: "custom", custom: 18), 18)
    XCTAssertNil(Cleanup.months(key: "off", custom: 5))
  }

  func testLoans() {
    let l = Loan(person: "Ashwin", amount: 10_000)
    XCTAssertEqual(LoanMath.outstanding(l, [LoanPayment(loanId: l.id, amount: 4_000), LoanPayment(loanId: "x", amount: 1)]), 6_000)
  }
}

final class Batch4Tests: XCTestCase {
  func testPayeeMemoryAndTags() {
    let txns = [
      Txn(type: .expense, amount: 100, accountId: "a", categoryId: "food", payee: "Swiggy", occurredAt: Date(timeIntervalSince1970: 1)),
      Txn(type: .expense, amount: 100, accountId: "b", categoryId: "food2", payee: "Swiggy", occurredAt: Date(timeIntervalSince1970: 5)),
      Txn(type: .expense, amount: 100, accountId: "a", payee: "Swiss Beauty", occurredAt: Date(timeIntervalSince1970: 3)),
    ]
    let s = PayeeMemory.suggestions("swi", txns: txns, type: .expense)
    XCTAssertEqual(s.map(\.payee), ["Swiggy", "Swiss Beauty"])
    XCTAssertEqual(s.first?.accountId, "b")
    XCTAssertEqual(Tags.parse("Goa Trip, #work, goa trip"), ["goa-trip", "work"])
  }

  func testValuationsAnchorInvestments() {
    let inv = Account(name: "Groww", type: .investment, color: "#000", icon: "x")
    let txns = [Txn(type: .transfer, amount: 1_000, accountId: "bank", toAccountId: inv.id, occurredAt: Date(timeIntervalSince1970: 10)),
                Txn(type: .transfer, amount: 500, accountId: "bank", toAccountId: inv.id, occurredAt: Date(timeIntervalSince1970: 30))]
    let v = [Valuation(accountId: inv.id, value: 5_000, at: Date(timeIntervalSince1970: 20))]
    XCTAssertEqual(Ledger.balances(accounts: [inv], txns: txns, valuations: v)[inv.id], 5_500)
    XCTAssertEqual(Ledger.balances(accounts: [inv], txns: txns, valuations: v, asOf: Date(timeIntervalSince1970: 15))[inv.id], 1_000)
  }

  func testHomeSectionsAndCrypto() throws {
    XCTAssertEqual(HomeSections.order("recent,hero,bogus").first, "recent")
    XCTAssertEqual(HomeSections.order("recent").count, HomeSections.all.count)
    let enc = try BackupCrypto.encrypt(Data("hello ₹".utf8), password: "pw", iterations: 1_000)
    XCTAssertTrue(BackupCrypto.isEncrypted(enc))
    XCTAssertEqual(String(data: try BackupCrypto.decrypt(enc, password: "pw"), encoding: .utf8), "hello ₹")
    XCTAssertThrowsError(try BackupCrypto.decrypt(enc, password: "nope"))
    XCTAssertFalse(String(data: enc, encoding: .utf8)!.contains("\\/"))
  }

  /// A file made by the Android app (same password, salt and IV format) opens here.
  func testAndroidEncryptedBackupOpens() throws {
    let android = #"{"paisaEncrypted":1,"kdf":"pbkdf2-sha256","iterations":1000,"salt":"6h3PSE+GI3Cj9J3rQkMoBg==","iv":"1TBb2mtOGUmVH4I7","data":"YIXToSwlOp9jkg0D1nBscKMFGVKbHmeuEw=="}"#
    XCTAssertEqual(String(data: try BackupCrypto.decrypt(Data(android.utf8), password: "pw"), encoding: .utf8), "hello ₹")
  }
}

/// More UPI apps' screenshots (same cases as Android ScreenshotAppsTest).
final class ScreenshotAppsTests: XCTestCase {
  private let ctx = CaptureContext(
    accounts: [CaptureAccount(id: "axis", name: "Axis Bank", type: .bank, institution: "Axis Bank", last4: "5678"),
               CaptureAccount(id: "bob", name: "Bank of Baroda", type: .bank, institution: "Bank of Baroda", last4: "9012")],
    categories: [CaptureCategory(id: "food", name: "Food & Dining", kind: .expense, parentId: nil),
                 CaptureCategory(id: "groceries", name: "Groceries", kind: .expense, parentId: nil)],
    defaultAccountId: "axis",
    now: Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 18))!)
  private func hm(_ d: Date) -> [Int] { let c = Calendar.current.dateComponents([.month, .day, .hour, .minute], from: d); return [c.month!, c.day!, c.hour!, c.minute!] }

  func testAmazonPay() {
    let d = ScreenshotParser.parse(["Payment successful", "₹ 199.00", "Paid to", "Airtel Prepaid", "Today, 10:15 AM", "Paid using Axis Bank ••5678", "Amazon Pay UPI"], ctx: ctx)!
    XCTAssertEqual(d.amount, 19_900); XCTAssertEqual(d.accountId, "axis"); XCTAssertTrue(d.payee!.hasPrefix("Airtel")); XCTAssertEqual(hm(d.occurredAt), [10, 10, 10, 15]); XCTAssertNil(d.warning)
  }
  func testWhatsApp() {
    let d = ScreenshotParser.parse(["Payment to Rohan Gupta", "₹250", "Completed", "9 Oct 2026, 8:30 pm", "Bank of Baroda ...9012", "UPI transaction ID: 428812345678"], ctx: ctx)!
    XCTAssertEqual(d.amount, 25_000); XCTAssertEqual(d.payee, "Rohan Gupta"); XCTAssertEqual(d.accountId, "bob"); XCTAssertEqual(hm(d.occurredAt), [10, 9, 20, 30])
  }
  func testOcrRupeeAsZAndCashback() {
    let d = ScreenshotParser.parse(["Cashback won ₹10", "Payment Successful", "Z349", "Paid to", "Swiggy", "Yesterday, 9:02 PM", "Axis Bank account ending 5678"], ctx: ctx)!
    XCTAssertEqual(d.amount, 34_900); XCTAssertEqual(d.payee, "Swiggy"); XCTAssertEqual(d.categoryId, "food"); XCTAssertEqual(d.accountId, "axis"); XCTAssertEqual(hm(d.occurredAt), [10, 9, 21, 2])
  }
  func testPaytmSkipsBalance() {
    let d = ScreenshotParser.parse(["Paid Successfully to", "Chai Point", "Wallet Balance ₹1,250", "₹40", "10 Oct, 09:41 AM"], ctx: ctx)!
    XCTAssertEqual(d.amount, 4_000); XCTAssertEqual(d.payee, "Chai Point")
  }
  func testBhimReceived() {
    let d = ScreenshotParser.parse(["Money received from", "Amit Kumar", "₹1,000", "Credited to", "Axis Bank XX5678", "Yesterday 7:10 pm"], ctx: ctx)!
    XCTAssertEqual(d.type, .income); XCTAssertEqual(d.payee, "Amit Kumar"); XCTAssertEqual(d.amount, 100_000)
  }
  func testCredReceipt() {
    let d = ScreenshotParser.parse(["Nishit Raghunandan Kirani paid", "Rohan Gouda D D", "8310228359@ibl", "₹160", "paid securely by", "CRED", "powered by", "23 NOV 2026, 12:51PM | TXN ID: 669329312874"], ctx: ctx)!
    XCTAssertEqual(d.amount, 16_000); XCTAssertEqual(d.payee, "Rohan Gouda D D"); XCTAssertEqual(hm(d.occurredAt), [11, 23, 12, 51]); XCTAssertNil(d.warning)
  }
  func testCredDetail() {
    let d = ScreenshotParser.parse(["R", "Rohan Gouda D D", "₹160", "PAID IN 1 SECOND", "12:51pm, 23rd nov'26", "Paid via CRED", "BANK OF BARODA", "XXXXXX7556",
      "Check balance", "payment initiated from your BANK OF BARODA account", "amount deducted from Nishit's bank", "amount credited to recipient's bank", "paying them again?"], ctx: ctx)!
    XCTAssertEqual(d.amount, 16_000); XCTAssertEqual(d.type, .expense); XCTAssertEqual(d.payee, "Rohan Gouda D D"); XCTAssertEqual(d.accountId, "bob")
    XCTAssertEqual(hm(d.occurredAt), [11, 23, 12, 51])
  }
  func testPendingIsUnticked() {
    let d = ScreenshotParser.parse(["Payment pending", "₹500", "Paid to", "Zepto"], ctx: ctx)!
    XCTAssertFalse(d.include); XCTAssertEqual(d.payee, "Zepto")
  }
}
