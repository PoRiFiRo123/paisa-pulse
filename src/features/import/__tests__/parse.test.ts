import { parseNarration, suggestCategoryName } from '../narration';
import {
  balanceMismatches,
  detectMapping,
  detectTemplate,
  extractRows,
  parseStatementAmount,
  parseStatementDate,
} from '../parse';
import { parseCsv } from '../readers/csv';
import { AXIS_CARD_CSV, AXIS_CSV, BOB_CSV, HDFC_CSV, ICICI_CSV, SBI_CSV } from './fixtures/statements';

const day = (ms: number | null) => (ms === null ? null : new Date(ms).toISOString().slice(0, 10));
const local = (y: number, m: number, d: number) => new Date(y, m - 1, d, 12).getTime();

describe('parseStatementDate', () => {
  it.each([
    ['01-09-2026', local(2026, 9, 1)],
    ['01/09/26', local(2026, 9, 1)],
    ['1-Sep-2026', local(2026, 9, 1)],
    ['01 SEP 26', local(2026, 9, 1)],
    ['1 Sept 2026', local(2026, 9, 1)],
    ['Sep 1, 2026', local(2026, 9, 1)],
    ['2026-09-01', local(2026, 9, 1)],
    ['46266', local(2026, 9, 1)],
  ])('%p', (input, expected) => expect(parseStatementDate(input)).toBe(expected));

  it('reads times and month-first dates when asked', () => {
    expect(parseStatementDate('01/09/2026 06:15 PM')).toBe(new Date(2026, 8, 1, 18, 15).getTime());
    expect(parseStatementDate('09/01/2026', 'mdy')).toBe(local(2026, 9, 1));
  });

  it.each(['', 'OPENING BALANCE', '31/02/2026', '99/99/99', '12345'])('rejects %p', (input) => {
    expect(parseStatementDate(input)).toBeNull();
  });
});

describe('parseStatementAmount', () => {
  it.each([
    ['1,23,456.78', 12345678, null],
    ['₹ 1,234', 123400, null],
    ['INR 50', 5000, null],
    ['(120.00)', -12000, null],
    ['-50', -5000, null],
    ['120.00 Dr', 12000, 'dr'],
    ['1,234.50CR', 123450, 'cr'],
    ['10.005', 1001, null],
  ])('%p', (input, paise, marker) => expect(parseStatementAmount(input)).toEqual({ paise, marker }));

  it.each(['', '-', '0.00', 'abc'])('no amount for %p', (input) => expect(parseStatementAmount(input)).toBeNull());
});

function run(csv: string, kind: 'bank' | 'card' = 'bank') {
  const sheet = parseCsv(csv);
  const template = detectTemplate(sheet);
  const mapping = detectMapping(sheet, template, kind)!;
  return { template, mapping, rows: extractRows(sheet, mapping) };
}

describe('bank statements', () => {
  it('Axis Bank: skips opening balance and totals, reconciles balances', () => {
    const { template, rows } = run(AXIS_CSV);
    expect(template?.id).toBe('axis-bank');
    expect(rows.map((r) => [day(r.date), r.direction, r.amount])).toEqual([
      ['2026-09-01', 'out', 420_00],
      ['2026-09-02', 'in', 90_000_00],
      ['2026-09-03', 'out', 2_000_00],
      ['2026-09-05', 'out', 8_360_00],
      ['2026-09-06', 'out', 7_500_00],
      ['2026-09-30', 'in', 245_00],
    ]);
    expect(balanceMismatches(rows)).toBe(0);
  });

  it('Bank of Baroda, HDFC (lakh commas, dd/mm/yy), ICICI (negative balances), SBI (named months)', () => {
    const bob = run(BOB_CSV);
    expect(bob.template?.id).toBe('bob');
    expect(bob.rows.map((r) => [r.direction, r.amount])).toEqual([['out', 1_245_00], ['out', 5_000_00], ['in', 25_000_00]]);

    const hdfc = run(HDFC_CSV);
    expect(hdfc.rows.map((r) => [day(r.date), r.direction, r.amount, r.reference])).toEqual([
      ['2026-09-01', 'out', 650_00, '0000424412345111'],
      ['2026-09-02', 'out', 2_499_00, '0000000000000000'],
      ['2026-09-03', 'in', 1_00_000_00, 'CITIN24245123'],
      ['2026-09-04', 'out', 4_210_00, '0000000000000456'],
    ]);
    expect(balanceMismatches(hdfc.rows)).toBe(0);

    const icici = run(ICICI_CSV);
    expect(icici.template?.id).toBe('icici');
    expect(icici.rows.map((r) => [r.amount, r.balance])).toEqual([[186_00, 12_314_00], [18_000_00, -5_686_00], [649_00, -6_335_00]]);
    expect(balanceMismatches(icici.rows)).toBe(0);

    const sbi = run(SBI_CSV);
    expect(sbi.template?.id).toBe('sbi');
    expect(sbi.rows.map((r) => [day(r.date), r.direction, r.amount])).toEqual([
      ['2026-09-01', 'out', 312_00],
      ['2026-09-02', 'out', 1_000_00],
      ['2026-09-15', 'in', 34_00],
    ]);
  });

  it('Axis credit card: single Amount with a Debit/Credit column', () => {
    const { template, mapping, rows } = run(AXIS_CARD_CSV, 'card');
    expect(template?.id).toBe('axis-card');
    expect(mapping.positiveIs).toBe('out');
    expect(rows.map((r) => [r.direction, r.amount])).toEqual([
      ['out', 580_00],
      ['out', 649_00],
      ['in', 8_360_00],
      ['out', 1_299_00],
      ['in', 299_00],
    ]);
  });
});

describe('parseNarration', () => {
  it.each([
    ['UPI/P2M/424412345678/SWIGGY LIMITED/swiggy@icici/Payment for order', 'UPI', 'Swiggy'],
    ['UPI/P2A/424912345/RAHUL SHARMA/rahul@okaxis/rent share', 'UPI', 'Rahul Sharma'],
    ['UPI-ZOMATO LTD-zomato-order@hdfcbank-HDFC0MERUPI-424412345111-Dinner', 'UPI', 'Zomato'],
    ['TO TRANSFER-UPI/DR/424412345444/BLINKIT/YESB/blinkit.payu@hdfcbank/Groceries', 'UPI', 'Blinkit'],
    ['UPI/424412345222/Payment for order/uber.rides@hdfcbank/HDFC Bank/ICI1234567890', 'UPI', 'Uber'],
    ['UPI/424512349876/DR/BIGBASKET/UTIB/bigbasket@axisbank', 'UPI', 'BigBasket'],
    ['NEFT/N245260123456/ACME TECHNOLOGIES PVT LTD/SALARY SEP', 'NEFT', 'Acme Technologies'],
    ['NEFT CR-CITI0100000-ACME TECHNOLOGIES-SALARY-CITIN24245123', 'NEFT', 'Acme Technologies'],
    ['IMPS/P2A/425112345678/PRIYA/SBIN0001234/gift', 'IMPS', 'Priya'],
    ['POS 512345XXXXXX1234 AMAZON PAY INDIA', 'POS', 'Amazon'],
    ['ATM-WDL/MG ROAD BANGALORE/S1AW0123', 'ATM', 'ATM withdrawal'],
    ['BILLDESK/AXIS BANK CREDIT CARD/XX3307 PAYMENT', 'CARD_PAYMENT', 'Credit card payment'],
    ['BBPS PAYMENT RECEIVED - THANK YOU', 'CARD_PAYMENT', 'Credit card payment'],
    ['Int.Pd:912010012345678:01-07-2026 to 30-09-2026', 'INTEREST', 'Interest'],
    ['ACH D- TP ACH BAJAJ FINANCE-CITI000000123', 'NACH', 'Bajaj Finance'],
  ])('%p', (text, channel, payee) => {
    const n = parseNarration(text);
    expect([n.channel, n.payee]).toEqual([channel, payee]);
  });

  it('keeps UPI notes and ids', () => {
    expect(parseNarration('UPI/P2A/424912345/RAHUL SHARMA/rahul@okaxis/rent share')).toMatchObject({ upiId: 'rahul@okaxis', note: 'rent share' });
  });
});

describe('suggestCategoryName', () => {
  it.each([
    ['UPI/…/SWIGGY', 'Swiggy', 'out', 'Food & Dining'],
    ['blinkit', 'Blinkit', 'out', 'Groceries'],
    ['uber rides', 'Uber', 'out', 'Metro/Auto/Cab'],
    ['NETFLIX-MONTHLY', 'Netflix', 'out', 'Subscriptions'],
    ['IMPS Rent NOBROKER', 'NoBroker', 'out', 'Rent'],
    ['ACH BAJAJ FINANCE EMI', null, 'out', 'EMI/Loans'],
    ['NEFT ACME SALARY SEP', 'Acme Technologies', 'in', 'Salary'],
    ['CREDIT INTEREST', 'Interest', 'in', 'Interest'],
    ['REFUND AMAZON PAY', 'Amazon', 'in', 'Refund'],
    ['random person', 'Priya', 'out', null],
  ] as const)('%p → %p', (narration, payee, direction, expected) => {
    expect(suggestCategoryName(narration, payee, direction)).toBe(expected);
  });
});
