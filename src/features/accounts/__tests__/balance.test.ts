import type { Transaction } from '@/db/schema';

import { balanceEffect, computeBalance, computeNetWorth } from '../balance';

type T = Pick<Transaction, 'type' | 'amount' | 'accountId' | 'toAccountId' | 'deletedAt'>;
const expense = (accountId: string, amount: number): T => ({ type: 'expense', amount, accountId, toAccountId: null, deletedAt: null });
const income = (accountId: string, amount: number): T => ({ type: 'income', amount, accountId, toAccountId: null, deletedAt: null });
const transfer = (from: string, to: string, amount: number): T => ({ type: 'transfer', amount, accountId: from, toAccountId: to, deletedAt: null });

describe('balanceEffect', () => {
  it('moves money in the right direction', () => {
    expect(balanceEffect(expense('a', 500), 'a')).toBe(-500);
    expect(balanceEffect(income('a', 500), 'a')).toBe(500);
    expect(balanceEffect(transfer('a', 'b', 500), 'a')).toBe(-500);
    expect(balanceEffect(transfer('a', 'b', 500), 'b')).toBe(500);
  });

  it('ignores other accounts and deleted transactions', () => {
    expect(balanceEffect(expense('a', 500), 'b')).toBe(0);
    expect(balanceEffect(transfer('a', 'b', 500), 'c')).toBe(0);
    expect(balanceEffect({ ...expense('a', 500), deletedAt: 1 }, 'a')).toBe(0);
  });
});

describe('computeBalance', () => {
  // Salary into Axis, spend on the MyZone card, pay the card bill from Axis.
  const txns = [
    income('axis', 80_000_00),
    expense('axis', 1_200_00),
    expense('card', 4_500_00),
    expense('card', 500_00),
    transfer('axis', 'card', 5_000_00),
    transfer('axis', 'bob', 10_000_00),
    { ...expense('axis', 99_999_00), deletedAt: 123 },
  ];

  it('adds opening balance and every live transaction', () => {
    expect(computeBalance({ id: 'axis', openingBalance: 20_000_00 }, txns)).toBe(83_800_00);
    expect(computeBalance({ id: 'bob', openingBalance: 0 }, txns)).toBe(10_000_00);
  });

  it('keeps credit cards negative while you owe, and a bill payment clears them', () => {
    expect(computeBalance({ id: 'card', openingBalance: 0 }, txns)).toBe(0);
    expect(computeBalance({ id: 'card', openingBalance: 0 }, txns.slice(0, 4))).toBe(-5_000_00);
  });

  it('keeps total money unchanged by transfers', () => {
    const ids = ['axis', 'card', 'bob'];
    const total = (list: T[]) => ids.reduce((s, id) => s + computeBalance({ id, openingBalance: 0 }, list), 0);
    const withoutTransfers = txns.filter((t) => t.type !== 'transfer');
    expect(total(txns)).toBe(total(withoutTransfers));
  });
});

describe('computeNetWorth', () => {
  it('skips archived and excluded accounts', () => {
    expect(
      computeNetWorth([
        { balance: 100, archivedAt: null, excludeFromTotals: false },
        { balance: -40, archivedAt: null, excludeFromTotals: false },
        { balance: 1_000, archivedAt: 5, excludeFromTotals: false },
        { balance: 1_000, archivedAt: null, excludeFromTotals: true },
      ]),
    ).toBe(60);
  });
});
