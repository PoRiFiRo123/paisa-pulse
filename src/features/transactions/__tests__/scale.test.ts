/**
 * @jest-environment node
 */
import { createTestDb } from '@/db/__tests__/testDb';
import { transactions } from '@/db/schema';
import { seedStarterCategories } from '@/db/seed';
import { createAccount } from '@/features/accounts/mutations';
import { accountsWithBalance } from '@/features/accounts/queries';
import { categoriesByKind } from '@/features/categories/queries';
import { toRows } from '@/features/transactions/TransactionDayList';
import { newId } from '@/lib/ids';

import { listTransactions, topCategories } from '../list';

jest.mock('@/features/transactions/TransactionListRow', () => ({ TransactionListRow: () => null }));
jest.mock('@/ui/TransactionRow', () => ({ TransactionRow: () => null }));
jest.mock('@/hooks/useMoney', () => ({ useMoney: () => ({}) }));
jest.mock('@/theme/useTheme', () => ({ useTheme: () => ({ colors: {} }) }));
jest.mock('@/stores/selection', () => ({ useSelection: () => false }));

// SPEC §10: the Activity list must stay smooth with 10,000 transactions.
it('lists, groups and totals 10,000 transactions quickly', async () => {
  const { db, raw } = createTestDb();
  const NOW = Date.UTC(2026, 8, 25);
  await seedStarterCategories(db, NOW);
  const cats = await categoriesByKind(db, 'expense');
  const axis = await createAccount(db, { name: 'Axis Bank', type: 'bank', color: '#AE275F', icon: 'building.columns.fill' }, NOW);
  const card = await createAccount(db, { name: 'Axis MyZone', type: 'card', color: '#5E5CE6', icon: 'creditcard.fill' }, NOW);
  const rows = Array.from({ length: 10_000 }, (_, i) => ({
    id: newId(),
    type: 'expense' as const,
    amount: 100 + (i % 5000),
    accountId: i % 3 ? axis.id : card.id,
    categoryId: cats[i % cats.length].id,
    payee: `Payee ${i % 200}`,
    occurredAt: NOW - i * 3_600_000,
    createdAt: NOW,
    updatedAt: NOW,
  }));
  for (let i = 0; i < rows.length; i += 500) await db.insert(transactions).values(rows.slice(i, i + 500));

  const t0 = performance.now();
  const items = await listTransactions(db);
  const grouped = toRows(items);
  const [balances, top] = await Promise.all([accountsWithBalance(db), topCategories(db, { start: 0, end: NOW + 1 })]);
  const elapsed = performance.now() - t0;

  expect(items).toHaveLength(10_000);
  expect(grouped.rows.length).toBe(10_000 + grouped.sticky.length);
  expect(balances.reduce((s, a) => s + a.balance, 0)).toBe(-rows.reduce((s, r) => s + r.amount, 0));
  expect(top[0].total).toBeGreaterThan(0);
  // Generous bound for slow CI machines; locally this is ~100–300 ms.
  expect(elapsed).toBeLessThan(3000);
  raw.close();
});
