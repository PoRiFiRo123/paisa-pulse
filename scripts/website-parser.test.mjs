// Checks the website's SMS parser against the apps' BankAlerts cases. Run: node --test scripts/website-parser.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

vm.runInThisContext(readFileSync('website/js/data.js', 'utf8'));
vm.runInThisContext(readFileSync('website/js/parser.js', 'utf8'));
const P = globalThis.PaisaParser;
const d = (text) => P.parse(text).draft;

test('Axis UPI debit', () => {
  const x = d('INR 450.00 debited from A/c no. XX4321 on 25-11-26 at 10:15:30 IST. Info- UPI/P2M/533012345678/SWIGGY. Not you? SMS BLOCK 4321 to 919951860002 - Axis Bank');
  assert.equal(x.amount, 45000); assert.equal(x.type, 'expense'); assert.equal(x.payee, 'Swiggy'); assert.equal(x.key, 'alert:533012345678');
  assert.equal(x.last4, '4321'); assert.equal(x.bank, 'Axis Bank'); assert.equal(x.category, 'Food & Dining'); assert.equal(x.method, 'UPI');
});
test('BoB transfer', () => {
  const x = d('Rs.199.00 transferred from A/c ...7556 to:UPI/533098765432. Total Bal:Rs.12,345.67CR. Avlbl Amt:Rs.12,345.67(25-11-2026 07:43:21) - Bank of Baroda');
  assert.equal(x.amount, 19900); assert.equal(x.type, 'expense'); assert.equal(x.last4, '7556'); assert.equal(x.key, 'alert:533098765432');
});
test('HDFC sent', () => {
  const x = d('Sent Rs.250.00 From HDFC Bank A/C *9999 To Rahul Sharma On 25/11/26 Ref 533011112222 Not You? Call 18002586161');
  assert.equal(x.amount, 25000); assert.equal(x.payee, 'Rahul Sharma'); assert.equal(x.type, 'expense');
});
test('SBI UPI', () => {
  const x = d('Dear UPI user A/C X7556 debited by 80.0 on date 25Nov26 trf to CHAI POINT Refno 533055556666. If not u? call 1800111109. -SBI');
  assert.equal(x.amount, 8000); assert.equal(x.payee, 'Chai Point');
});
test('ICICI debit', () => {
  const x = d('ICICI Bank Acct XX321 debited for Rs 1,299.00 on 25-Nov-26; AMAZON PAY credited. UPI:533077778888. Call 18002662 for dispute.');
  assert.equal(x.amount, 129900); assert.equal(x.type, 'expense');
});
test('card spend', () => {
  const x = d('Spent INR 2,499.00 Axis Bank Card no. XX1234 25-11-26 13:45:12 IST at MYNTRA DESIGNS. Avl Lmt INR 97,501.00. Not you? SMS BLOCK 1234');
  assert.equal(x.amount, 249900); assert.equal(x.last4, '1234'); assert.equal(x.type, 'expense'); assert.equal(x.accountKind, 'card'); assert.equal(x.payee, 'Myntra');
});
test('salary credit', () => {
  const x = d('INR 90,000.00 credited to A/c no. XX4321 on 01-11-26 by NEFT from BOOMI SOFTWARE PVT LTD. Avl Bal INR 1,02,345.00 - Axis Bank');
  assert.equal(x.amount, 9000000); assert.equal(x.type, 'income'); assert.equal(x.method, 'NEFT');
});
test('balance is not the amount', () => {
  assert.equal(d('Avl Bal: Rs 5,000.00. Rs 120.00 debited from A/c XX4321 towards UPI/533000001111/ZEPTO').amount, 12000);
});
test('card bill payment', () => {
  const x = d('Payment of INR 6,400.00 has been received towards your Axis Bank Credit Card XX1234. Thank you.');
  assert.equal(x.type, 'transfer'); assert.equal(x.payee, null);
});
test('ignores OTPs, dues, requests', () => {
  for (const t of [
    '123456 is your OTP for a transaction of INR 450.00 at SWIGGY. Do not share it.',
    'Your Axis Bank Credit Card XX1234 statement: Total due INR 6,400.00, minimum amount due INR 320. Due date 05-12-26.',
    'Rahul has requested money of Rs 200.00 on Google Pay. Pay or decline.',
    'Rs 499.00 will be debited from your A/c XX4321 on 28-11-26 for Netflix e-mandate.',
    'Transaction of Rs 450.00 failed. Amount will be refunded.',
  ]) assert.ok(P.parse(t).skipped, t);
});
test('key matches the Kotlin hash', () => {
  const a = 'Rs 99.00 debited from A/c XX4321. Info: SPOTIFY';
  assert.equal(P.key(a, 9900), P.key(a, 9900));
  // "hello".hashCode() == 99162322 on the JVM; "rs99" normalises from "Rs 99" and must hash the same way.
  assert.equal(P.key('hello', 1), 'alert:1:' + (99162322).toString(16));
});
