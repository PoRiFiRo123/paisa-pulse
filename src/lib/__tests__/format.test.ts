import { daysUntilDay } from '@/features/accounts/presentation';

import { accountLabel, balance, dayHeader, MINUS, relativeWhen, signedAmount } from '../format';

const at = (y: number, m: number, d: number, h = 12, min = 0) => new Date(y, m - 1, d, h, min).getTime();
const NOW = at(2026, 9, 25, 15);

describe('format', () => {
  it('signs amounts like the designs', () => {
    expect(signedAmount(42000, 'expense')).toBe(`${MINUS}₹420`);
    expect(signedAmount(9000000, 'income')).toBe('+₹90,000');
    expect(signedAmount(500000, 'transfer')).toBe('₹5,000');
    expect(signedAmount(12345, 'expense')).toBe(`${MINUS}₹123.45`);
  });

  it('formats signed balances', () => {
    expect(balance(-836000)).toBe(`${MINUS}₹8,360`);
    expect(balance(18245000)).toBe('₹1,82,450');
    expect(balance(24830000, true)).toBe('₹2.48L');
  });

  it('labels accounts with last 4 digits', () => {
    expect(accountLabel('Axis Bank', '4521')).toBe('Axis Bank ••4521');
    expect(accountLabel('Cash', null)).toBe('Cash');
  });

  it('describes when a transaction happened', () => {
    expect(relativeWhen(at(2026, 9, 25, 13, 24), NOW)).toBe('1:24 PM');
    expect(relativeWhen(at(2026, 9, 24), NOW)).toBe('Yesterday');
    expect(relativeWhen(at(2026, 9, 1), NOW)).toBe('1 Sep');
    expect(relativeWhen(at(2025, 12, 31), NOW)).toBe('31 Dec 2025');
    expect(dayHeader(at(2026, 9, 25), NOW)).toBe('Today');
    expect(dayHeader(at(2026, 9, 20), NOW)).toBe('Sun, 20 Sep');
  });
});

describe('daysUntilDay', () => {
  it('counts to the next due day, rolling into next month and clamping short months', () => {
    expect(daysUntilDay(5, new Date(2026, 8, 25)).days).toBe(10);
    expect(daysUntilDay(25, new Date(2026, 8, 25)).days).toBe(0);
    expect(daysUntilDay(31, new Date(2026, 1, 10)).date).toEqual(new Date(2026, 1, 28));
    expect(daysUntilDay(1, new Date(2026, 11, 20)).date).toEqual(new Date(2027, 0, 1));
  });
});
