import type { CaptureContext } from '../drafts';
import { findReceiptDate, parsePaymentScreenshot } from '../screenshot';

const NOW = new Date(2026, 9, 10, 18).getTime();
const ctx: CaptureContext = {
  now: NOW,
  defaultAccountId: 'axis',
  accounts: [
    { id: 'axis', name: 'Axis Bank', type: 'bank', institution: 'Axis Bank', last4: '5678' },
    { id: 'bob', name: 'Bank of Baroda', type: 'bank', institution: 'Bank of Baroda', last4: '9012' },
    { id: 'card', name: 'Axis MyZone', type: 'card', institution: 'Axis Bank', last4: '3307' },
  ],
  categories: [
    { id: 'food', name: 'Food & Dining', kind: 'expense', parentId: null },
    { id: 'groceries', name: 'Groceries', kind: 'expense', parentId: null },
    { id: 'other', name: 'Other', kind: 'income', parentId: null },
  ],
};

// OCR lines shaped like each app's success screen (Vision returns one string per line).
const GPAY = ['To Swiggy', '₹420', 'Completed', '10 Oct 2026, 2:15 pm', 'Split with friends', 'UPI transaction ID', '424412345678', 'To: SWIGGY LIMITED', 'swiggy@icici', 'From: NISHIT KIRANI (Bank of Baroda)', 'Bank of Baroda 9012', 'Google transaction ID', 'CICAgOCx8aqHGw'];
const PHONEPE = ['Transaction Successful', '02:15 pm on 09 Oct 2026', 'Paid to', 'BLINKIT', 'blinkit.payu@hdfcbank', '₹ 1,245', 'Debited from', 'XXXXXXXX5678', 'UTR: 424512349876', 'Transaction ID', 'T2410091415221234567890'];
// Android ML Kit returns blocks with line breaks inside.
const PAYTM = ['Paid Successfully to\nRahul Sharma', '₹2,000', 'UPI Ref No: 425112345678\n10 Oct, 09:41 AM', 'From: Axis Bank - 5678'];
const RECEIVED = ['Received from', 'Priya Mehta', '₹500', 'Completed', '8 Oct 2026, 7:02 pm', 'Credited to Axis Bank XX5678'];
const CRED = ['payment successful', '₹8,360', 'paid to Axis Bank credit card', 'xxxx 3307', '05 Oct 2026, 11:20 am'];

describe('parsePaymentScreenshot', () => {
  it('reads a Google Pay payment', () => {
    const d = parsePaymentScreenshot(GPAY, ctx)!;
    expect(d).toMatchObject({ type: 'expense', amount: 420_00, payee: 'Swiggy', accountId: 'bob', categoryId: 'food', include: true });
    expect(new Date(d.occurredAt)).toEqual(new Date(2026, 9, 10, 14, 15));
  });

  it('reads a PhonePe payment with the debited account', () => {
    const d = parsePaymentScreenshot(PHONEPE, ctx)!;
    expect(d).toMatchObject({ amount: 1245_00, payee: 'Blinkit', accountId: 'axis', categoryId: 'groceries' });
    expect(new Date(d.occurredAt)).toEqual(new Date(2026, 9, 9, 14, 15));
  });

  it('reads Paytm blocks and money received', () => {
    expect(parsePaymentScreenshot(PAYTM, ctx)).toMatchObject({ type: 'expense', amount: 2000_00, payee: 'Rahul Sharma', accountId: 'axis' });
    expect(parsePaymentScreenshot(RECEIVED, ctx)).toMatchObject({ type: 'income', amount: 500_00, payee: 'Priya Mehta', accountId: 'axis' });
  });

  it('turns a card bill payment into a transfer to the card', () => {
    expect(parsePaymentScreenshot(CRED, ctx)).toMatchObject({ type: 'transfer', amount: 8360_00, toAccountId: 'card', accountId: 'axis', categoryId: null });
  });

  it('flags failed payments and ignores screens without an amount', () => {
    const d = parsePaymentScreenshot(['Payment failed', 'Paid to', 'Zomato', '₹350', '10 Oct 2026'], ctx)!;
    expect(d.include).toBe(false);
    expect(d.warning).toMatch(/failed/);
    expect(parsePaymentScreenshot(['Chats', 'Hello there'], ctx)).toBeNull();
  });
});

describe('findReceiptDate', () => {
  it('handles the common formats', () => {
    expect(new Date(findReceiptDate(['Oct 3, 2026 9:05 PM'], NOW)!)).toEqual(new Date(2026, 9, 3, 21, 5));
    expect(new Date(findReceiptDate(['07/10/2026 14:30'], NOW)!)).toEqual(new Date(2026, 9, 7, 14, 30));
    // No year and in the future → last year.
    expect(new Date(findReceiptDate(['28 Dec, 10:00 AM'], NOW)!).getFullYear()).toBe(2025);
  });
});
