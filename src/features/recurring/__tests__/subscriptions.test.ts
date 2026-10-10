/**
 * @jest-environment node
 */
import { createTestDb } from '@/db/__tests__/testDb';
import { createAccount } from '@/features/accounts/mutations';
import { createTransaction } from '@/features/transactions/mutations';

import { createRecurring, processDueRecurring } from '../recurring';
import { detectSubscriptions, listSubscriptions, monthlyEquivalent, trackSubscription } from '../subscriptions';

const NOW = new Date(2026, 9, 10, 12).getTime();

async function setup() {
  const t = createTestDb();
  const card = await createAccount(t.db, { name: 'MyZone', type: 'card', color: '#000', icon: 'x' }, NOW);
  const spend = (payee: string, amount: number, y: number, m: number, d: number) =>
    createTransaction(t.db, { type: 'expense', amount, accountId: card.id, payee, occurredAt: new Date(y, m, d, 9).getTime() }, NOW);
  return { ...t, card, spend };
}

describe('monthlyEquivalent', () => {
  it('normalises every cadence to a month', () => {
    expect(monthlyEquivalent({ amount: 1499_00, frequency: 'yearly', interval: 1 })).toBe(12492);
    expect(monthlyEquivalent({ amount: 649_00, frequency: 'monthly', interval: 1 })).toBe(649_00);
    expect(monthlyEquivalent({ amount: 300_00, frequency: 'monthly', interval: 3 })).toBe(100_00);
    expect(monthlyEquivalent({ amount: 500_00, frequency: 'weekly', interval: 1 })).toBe(Math.round((500_00 * 52) / 12));
  });
});

describe('subscriptions', () => {
  it('lists recurring expenses with what they have cost so far', async () => {
    const { db, raw, card } = await setup();
    await createRecurring(db, { type: 'expense', amount: 649_00, accountId: card.id, payee: 'Netflix', frequency: 'monthly', startAt: new Date(2026, 6, 5).getTime() }, { now: NOW });
    await processDueRecurring(db, NOW);
    const [s] = await listSubscriptions(db, NOW);
    expect(s).toMatchObject({ monthly: 649_00, yearly: 7788_00, paid: 4 * 649_00, payments: 4, active: true });
    expect(new Date(s.rule.nextAt)).toEqual(new Date(2026, 10, 5));
    raw.close();
  });

  it('detects steady monthly payments and starts tracking them', async () => {
    const { db, raw, spend } = await setup();
    for (const m of [5, 6, 7, 8]) await spend('Spotify', 119_00, 2026, m, 12);
    await spend('Spotify', 119_00, 2026, 9, 11);
    // Irregular payee: not a subscription.
    for (const [m, d] of [[8, 1], [8, 3], [9, 2]]) await spend('Swiggy', 400_00, 2026, m, d);
    // Stopped months ago.
    for (const m of [0, 1, 2]) await spend('Hotstar', 299_00, 2026, m, 1);
    const found = await detectSubscriptions(db, NOW);
    expect(found.map((f) => f.payee)).toEqual(['Spotify']);
    expect(found[0]).toMatchObject({ frequency: 'monthly', amount: 119_00 });
    expect(found[0].transactionIds).toHaveLength(5);

    const rule = await trackSubscription(db, found[0], NOW);
    expect(new Date(rule.nextAt)).toEqual(new Date(2026, 10, 11, 9));
    expect(await detectSubscriptions(db, NOW)).toEqual([]);
    const [s] = await listSubscriptions(db, NOW);
    expect(s).toMatchObject({ paid: 5 * 119_00, payments: 5 });
    raw.close();
  });

  it('ignores a price change before the current run and never invents an overdue payment', async () => {
    const { db, raw, spend } = await setup();
    await spend('Gym', 1000_00, 2026, 5, 1);
    for (const m of [6, 7, 8]) await spend('Gym', 1500_00, 2026, m, 1);
    const [g] = await detectSubscriptions(db, NOW);
    expect(g).toMatchObject({ amount: 1500_00, transactionIds: expect.any(Array) });
    expect(g.transactionIds).toHaveLength(3);
    const rule = await trackSubscription(db, g, NOW);
    expect(rule.nextAt).toBeGreaterThan(NOW);
    expect(await processDueRecurring(db, NOW)).toBe(0);
    raw.close();
  });
});
