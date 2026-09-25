/**
 * @jest-environment node
 */
import { createTestDb } from '@/db/__tests__/testDb';
import { createAccount } from '@/features/accounts/mutations';
import { accountsWithBalance } from '@/features/accounts/queries';
import { createCategory } from '@/features/categories/mutations';
import { listTransactions } from '@/features/transactions/list';

import {
  createRecurring,
  deleteRecurring,
  describeFrequency,
  MAX_CATCH_UP,
  occurrenceAfter,
  occurrenceAt,
  processDueRecurring,
  setRecurringPaused,
  upcomingRecurring,
  updateRecurring,
} from '../recurring';

const d = (y: number, m: number, day: number, h = 9) => new Date(y, m - 1, day, h).getTime();

describe('occurrences', () => {
  it('keeps the day of month, clamping short months', () => {
    const rule = { startAt: d(2026, 1, 31), frequency: 'monthly' as const, interval: 1 };
    expect([1, 2, 3].map((n) => new Date(occurrenceAt(rule, n)).getDate())).toEqual([28, 31, 30]);
  });

  it('finds the next occurrence after a time', () => {
    const weekly = { startAt: d(2026, 9, 1), frequency: 'weekly' as const, interval: 2 };
    expect(occurrenceAfter(weekly, d(2026, 8, 1))).toBe(d(2026, 9, 1));
    expect(occurrenceAfter(weekly, d(2026, 9, 1))).toBe(d(2026, 9, 15));
    expect(occurrenceAfter(weekly, d(2026, 9, 20))).toBe(d(2026, 9, 29));
    const yearly = { startAt: d(2024, 2, 29), frequency: 'yearly' as const, interval: 1 };
    expect(new Date(occurrenceAfter(yearly, d(2024, 3, 1))).getDate()).toBe(28);
  });

  it('describes frequencies', () => {
    expect(describeFrequency({ frequency: 'monthly', interval: 1 })).toBe('Monthly');
    expect(describeFrequency({ frequency: 'weekly', interval: 2 })).toBe('Every 2 weeks');
  });
});

async function setup() {
  const { db, raw } = createTestDb();
  const now = d(2026, 9, 25);
  const axis = await createAccount(db, { name: 'Axis', type: 'bank', color: '#000', icon: 'x' }, now);
  const card = await createAccount(db, { name: 'Card', type: 'card', color: '#000', icon: 'x' }, now);
  const rent = await createCategory(db, { kind: 'expense', name: 'Rent', icon: 'x', color: '#000' }, now);
  return { db, raw, axis, card, rent, now };
}

describe('processDueRecurring', () => {
  it('adds each due occurrence once and moves on', async () => {
    const { db, raw, axis, rent } = await setup();
    const rule = await createRecurring(db, { type: 'expense', amount: 15_000_00, accountId: axis.id, categoryId: rent.id, payee: 'Landlord', frequency: 'monthly', startAt: d(2026, 7, 5) });
    expect(await processDueRecurring(db, d(2026, 9, 25))).toBe(3); // Jul, Aug, Sep
    expect(await processDueRecurring(db, d(2026, 9, 25))).toBe(0);
    const txns = await listTransactions(db);
    expect(txns.map((t) => new Date(t.occurredAt).getMonth() + 1)).toEqual([9, 8, 7]);
    expect(txns.every((t) => t.source === 'recurring' && t.categoryId === rent.id && t.payee === 'Landlord')).toBe(true);
    expect(await processDueRecurring(db, d(2026, 10, 5))).toBe(1);
    expect((await upcomingRecurring(db, d(2026, 10, 25)))[0].id).toBe(rule.id);
    raw.close();
  });

  it('handles transfers, end dates and the catch-up cap', async () => {
    const { db, raw, axis, card } = await setup();
    await createRecurring(db, { type: 'transfer', amount: 5_000_00, accountId: axis.id, toAccountId: card.id, frequency: 'monthly', startAt: d(2026, 1, 10), endAt: d(2026, 3, 10) });
    await createRecurring(db, { type: 'expense', amount: 100, accountId: axis.id, frequency: 'daily', startAt: d(2025, 1, 1) });
    const added = await processDueRecurring(db, d(2026, 9, 25));
    expect(added).toBe(3 + MAX_CATCH_UP);
    const card$ = (await accountsWithBalance(db)).find((a) => a.id === card.id)!;
    expect(card$.balance).toBe(15_000_00);
    // The daily rule jumps to the future instead of back-filling the rest.
    expect(await processDueRecurring(db, d(2026, 9, 25))).toBe(0);
    raw.close();
  });

  it('continues after "Repeat…" from an existing transaction', async () => {
    const { db, raw, axis } = await setup();
    await createRecurring(db, { type: 'expense', amount: 649_00, accountId: axis.id, payee: 'Netflix', frequency: 'monthly', startAt: d(2026, 9, 12) }, { firstAlreadyAdded: true });
    expect(await processDueRecurring(db, d(2026, 9, 25))).toBe(0);
    expect(await processDueRecurring(db, d(2026, 10, 12, 10))).toBe(1);
    raw.close();
  });

  it('skips missed occurrences when resumed and unlinks on delete', async () => {
    const { db, raw, axis } = await setup();
    const rule = await createRecurring(db, { type: 'expense', amount: 100, accountId: axis.id, frequency: 'weekly', startAt: d(2026, 9, 1) });
    await processDueRecurring(db, d(2026, 9, 2)); // 1 Sep
    await setRecurringPaused(db, rule.id, true, d(2026, 9, 3));
    expect(await processDueRecurring(db, d(2026, 9, 25))).toBe(0);
    await setRecurringPaused(db, rule.id, false, d(2026, 9, 25));
    expect(await processDueRecurring(db, d(2026, 9, 26))).toBe(0);
    expect(await processDueRecurring(db, d(2026, 9, 29, 10))).toBe(1);
    await updateRecurring(db, rule.id, { type: 'expense', amount: 200, accountId: axis.id, frequency: 'weekly', startAt: d(2026, 9, 1) });
    expect(await processDueRecurring(db, d(2026, 10, 6, 10))).toBe(1);
    expect((await listTransactions(db))[0].amount).toBe(200);
    await deleteRecurring(db, rule.id);
    expect((await listTransactions(db)).every((t) => t.id && t.amount > 0)).toBe(true);
    raw.close();
  });

  it('rejects invalid rules', async () => {
    const { db, raw, axis } = await setup();
    await expect(createRecurring(db, { type: 'expense', amount: 0, accountId: axis.id, frequency: 'daily', startAt: 0 })).rejects.toThrow();
    await expect(createRecurring(db, { type: 'expense', amount: 1, accountId: axis.id, frequency: 'daily', interval: 0, startAt: 0 })).rejects.toThrow();
    await expect(createRecurring(db, { type: 'expense', amount: 1, accountId: axis.id, frequency: 'daily', startAt: 10, endAt: 5 })).rejects.toThrow();
    raw.close();
  });
});
