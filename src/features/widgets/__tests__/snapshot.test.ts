/**
 * @jest-environment node
 */
import { createTestDb } from '@/db/__tests__/testDb';
import { createAccount } from '@/features/accounts/mutations';
import { setBudget } from '@/features/budgets/budgets';
import { createCategory } from '@/features/categories/mutations';
import { createTransaction } from '@/features/transactions/mutations';

import { buildWidgetSnapshot } from '../snapshot';

it('builds a formatted snapshot and masks amounts when hidden', async () => {
  const { db, raw } = createTestDb();
  const now = new Date(2026, 8, 25, 15).getTime();
  const a = await createAccount(db, { name: 'A', type: 'bank', color: '#000', icon: 'x' }, now);
  const food = await createCategory(db, { kind: 'expense', name: 'Food', icon: 'fork.knife', color: '#FF9500' }, now);
  await createTransaction(db, { type: 'expense', amount: 420_00, accountId: a.id, categoryId: food.id, occurredAt: now - 3_600_000 }, now);
  await createTransaction(db, { type: 'expense', amount: 1_000_00, accountId: a.id, occurredAt: new Date(2026, 8, 2).getTime() }, now);
  await setBudget(db, null, 1_000_00, now);

  const snap = await buildWidgetSnapshot(db, { now });
  expect(snap).toMatchObject({
    month: 'September',
    spent: '₹1,420',
    today: '₹420',
    budget: { label: '₹420 over', ratio: 1, over: true },
  });
  expect(snap.top.map((t) => t.name)).toEqual(['Uncategorised', 'Food']);

  const hidden = await buildWidgetSnapshot(db, { now, hideAmounts: true });
  expect([hidden.spent, hidden.today, hidden.budget?.label, hidden.top[0].amount]).toEqual(['₹••••', '₹••••', 'Budget', '₹••••']);
  raw.close();
});
