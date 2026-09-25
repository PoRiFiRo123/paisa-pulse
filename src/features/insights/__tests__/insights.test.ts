/**
 * @jest-environment node
 */
import { createTestDb } from '@/db/__tests__/testDb';
import { createAccount } from '@/features/accounts/mutations';
import { createCategory } from '@/features/categories/mutations';
import { createTransaction } from '@/features/transactions/mutations';

import { biggestExpenses, categoryBreakdown, daysElapsed, monthlyTotals, percentChange } from '../insights';

const AUG = { start: Date.UTC(2026, 7, 1), end: Date.UTC(2026, 8, 1), label: 'August 2026', short: 'Aug' };
const SEP = { start: Date.UTC(2026, 8, 1), end: Date.UTC(2026, 9, 1), label: 'September 2026', short: 'Sep' };

it('computes monthly totals, breakdown shares and biggest expenses', async () => {
  const { db, raw } = createTestDb();
  const now = Date.UTC(2026, 8, 20);
  const a = await createAccount(db, { name: 'A', type: 'bank', color: '#000', icon: 'x' }, now);
  const food = await createCategory(db, { kind: 'expense', name: 'Food', icon: 'x', color: '#FF9500' }, now);
  const rent = await createCategory(db, { kind: 'expense', name: 'Rent', icon: 'x', color: '#AF52DE' }, now);
  await createTransaction(db, { type: 'expense', amount: 3_000_00, accountId: a.id, categoryId: food.id, occurredAt: Date.UTC(2026, 8, 3) }, now);
  await createTransaction(db, { type: 'expense', amount: 9_000_00, accountId: a.id, categoryId: rent.id, payee: 'Landlord', occurredAt: Date.UTC(2026, 8, 5) }, now);
  await createTransaction(db, { type: 'income', amount: 50_000_00, accountId: a.id, occurredAt: Date.UTC(2026, 8, 1) }, now);
  await createTransaction(db, { type: 'expense', amount: 4_000_00, accountId: a.id, categoryId: food.id, occurredAt: Date.UTC(2026, 7, 10) }, now);

  const months = await monthlyTotals(db, [AUG, SEP]);
  expect(months.map((m) => [m.short, m.spent, m.received])).toEqual([
    ['Aug', 4_000_00, 0],
    ['Sep', 12_000_00, 50_000_00],
  ]);
  const breakdown = await categoryBreakdown(db, SEP);
  expect(breakdown.map((b) => [b.category?.name, b.share])).toEqual([
    ['Rent', 0.75],
    ['Food', 0.25],
  ]);
  expect((await biggestExpenses(db, SEP, 1))[0].payee).toBe('Landlord');
  raw.close();
});

it('averages over elapsed days and compares months', () => {
  expect(daysElapsed(SEP, Date.UTC(2026, 8, 20, 12))).toBe(20);
  expect(daysElapsed(AUG, Date.UTC(2026, 8, 20))).toBe(31);
  expect(daysElapsed(SEP, Date.UTC(2026, 8, 1))).toBe(1);
  expect(percentChange(120, 100)).toBe(20);
  expect(percentChange(50, 100)).toBe(-50);
  expect(percentChange(50, 0)).toBeNull();
});
