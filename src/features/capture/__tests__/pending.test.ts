/**
 * @jest-environment node
 */
import { createTestDb } from '@/db/__tests__/testDb';
import { createAccount } from '@/features/accounts/mutations';
import { createCategory } from '@/features/categories/mutations';
import { listTransactions } from '@/features/transactions/list';

import { ingestPending, parsePending, type PendingEntry } from '../pending';

describe('Siri / Shortcuts queue', () => {
  it('adds each queued entry once, matching accounts and categories', async () => {
    const { db, raw } = createTestDb();
    const now = new Date(2026, 9, 10, 12).getTime();
    const axis = await createAccount(db, { name: 'Axis Bank', type: 'bank', color: '#000', icon: 'x' }, now);
    const card = await createAccount(db, { name: 'Axis MyZone', type: 'card', color: '#000', icon: 'x', last4: '3307' }, now);
    const food = await createCategory(db, { kind: 'expense', name: 'Food & Dining', icon: 'x', color: '#000' }, now);
    const ctx = {
      now,
      defaultAccountId: axis.id,
      accounts: [axis, card].map((a) => ({ id: a.id, name: a.name, type: a.type, institution: a.institution, last4: a.last4 })),
      categories: [{ id: food.id, name: food.name, kind: food.kind, parentId: null }],
    };
    const entries: PendingEntry[] = [
      { id: 'a', kind: 'expense', amount: 250, payee: 'lunch', note: null, account: null, category: null, at: now / 1000 - 60, source: 'siri' },
      { id: 'b', kind: 'expense', amount: 1299.5, payee: 'AMAZON PAY INDIA', note: null, account: 'Axis MyZone', category: null, at: now / 1000, source: 'wallet' },
      { id: 'c', kind: 'expense', amount: 0, payee: 'bad', note: null, account: null, category: null, at: now / 1000, source: 'siri' },
    ];
    const first = await ingestPending(db, entries, ctx);
    expect(first.added).toHaveLength(2);
    expect(first.handled).toEqual(['a', 'b', 'c']);
    const rows = await listTransactions(db);
    expect(rows.find((r) => r.amount === 250_00)).toMatchObject({ accountId: axis.id, categoryId: food.id, payee: 'Lunch', source: 'shortcut' });
    expect(rows.find((r) => r.amount === 1299_50)).toMatchObject({ accountId: card.id, payee: 'Amazon' });
    // Re-reading the same queue adds nothing.
    expect((await ingestPending(db, entries, ctx)).added).toHaveLength(0);
    raw.close();
  });

  it('parses the queue defensively', () => {
    expect(parsePending(null)).toEqual([]);
    expect(parsePending('not json')).toEqual([]);
    expect(parsePending('[{"id":"x","amount":5},{"nope":1}]')).toHaveLength(1);
  });
});
